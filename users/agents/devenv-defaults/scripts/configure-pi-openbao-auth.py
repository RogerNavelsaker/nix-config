#!/usr/bin/env python3
"""Opt-in, backup-first migration of LiteLLM auth to an injected environment variable."""

import argparse
import json
import os
import shutil
import stat
import sys
import tempfile
import time
from pathlib import Path

ENV_KEY = "LITELLM_API_KEY"
KEY_REFERENCE = "$LITELLM_API_KEY"


def fail(message):
    raise ValueError(message)


def reject_constant(value):
    fail(f"Invalid JSON constant: {value}")


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def ensure_owned_directory(path):
    path = Path(path)
    if path.is_symlink():
        fail(f"Refusing symlinked directory: {path}")
    if path.exists():
        if not path.is_dir() or path.stat().st_uid != os.getuid():
            fail(f"Refusing unexpected or unowned directory: {path}")
        return
    ensure_owned_directory(path.parent)
    path.mkdir(mode=0o700)


def validate_home(home):
    if home.is_symlink() or not home.is_dir() or home.stat().st_uid != os.getuid():
        fail(f"Refusing unexpected or unowned agent home: {home}")
    if stat.S_IMODE(home.stat().st_mode) & 0o022:
        fail(f"Refusing group/other-writable agent home: {home}")
    expected = home / ".pi" / "agent"
    override = os.environ.get("PI_CODING_AGENT_DIR")
    if override and Path(override).expanduser().absolute() != expected.absolute():
        fail("Refusing non-default PI_CODING_AGENT_DIR; migration targets ~/.pi/agent.")
    for directory in (home / ".pi", expected):
        if directory.is_symlink() or not directory.is_dir():
            fail(f"Refusing unexpected Pi agent directory: {directory}")
        if directory.stat().st_uid != os.getuid():
            fail(f"Refusing unowned Pi agent directory: {directory}")
        if stat.S_IMODE(directory.stat().st_mode) & 0o022:
            fail(f"Refusing group/other-writable Pi agent directory: {directory}")
    return expected


def load_auth(path):
    if path.is_symlink():
        fail(f"Refusing symlinked auth file: {path}")
    if not path.is_file():
        fail(f"Refusing missing or non-file auth config: {path}")
    if path.stat().st_uid != os.getuid():
        fail(f"Refusing unowned auth file: {path}")
    try:
        data = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        fail(f"Refusing invalid JSON in {path}: {exc}")
    if not isinstance(data, dict):
        fail(f"Refusing non-object JSON in {path}")
    return data


def migrate_auth(auth):
    credential = auth.get("litellm")
    if not isinstance(credential, dict) or credential.get("type") != "api_key":
        fail("Refusing LiteLLM auth entry that is not type api_key")
    key = credential.get("key")
    if not isinstance(key, str) or not key:
        fail("Refusing missing or non-string LiteLLM auth key")
    if key == KEY_REFERENCE:
        return False
    if key.startswith(("$", "!")):
        fail("Refusing to replace an existing environment or command key reference")
    credential["key"] = KEY_REFERENCE
    return True


def backup_auth(home, path):
    backup_root = home / ".local" / "state" / "pi" / "backups"
    for directory in (
        home / ".local",
        home / ".local" / "state",
        home / ".local" / "state" / "pi",
        backup_root,
    ):
        ensure_owned_directory(directory)
        if stat.S_IMODE(directory.stat().st_mode) & 0o022:
            fail(f"Refusing group/other-writable backup directory: {directory}")
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    backup_dir = backup_root / f"pi-openbao-auth-pre-{stamp}-{os.getpid()}"
    suffix = 0
    while backup_dir.exists():
        suffix += 1
        backup_dir = backup_root / f"pi-openbao-auth-pre-{stamp}-{os.getpid()}-{suffix}"
    backup_dir.mkdir(mode=0o700)
    target = backup_dir / path.name
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with path.open("rb") as source, os.fdopen(fd, "wb") as destination:
            shutil.copyfileobj(source, destination)
            destination.flush()
            os.fsync(destination.fileno())
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        raise
    return backup_dir


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-home", required=True)
    args = parser.parse_args()

    if not os.environ.get(ENV_KEY, "").strip():
        fail(f"{ENV_KEY} is unset; run this migration only under OpenBao secret injection.")
    home_value = os.environ.get("HOME")
    expected_home = Path(args.expected_home).absolute()
    if not home_value or Path(home_value).absolute() != expected_home:
        fail(f"Run with HOME={expected_home}")
    agent_dir = validate_home(expected_home)
    auth_path = agent_dir / "auth.json"
    auth = load_auth(auth_path)
    if not migrate_auth(auth):
        print(f"{ENV_KEY} reference already configured; no changes made.")
        return

    backup_dir = backup_auth(expected_home, auth_path)
    data = (json.dumps(auth, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    atomic_write(auth_path, data)
    print(f"Configured LiteLLM auth to use {ENV_KEY}; backup saved at {backup_dir}.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as exc:
        print(f"Pi OpenBao auth setup failed: {exc}", file=sys.stderr)
        sys.exit(1)