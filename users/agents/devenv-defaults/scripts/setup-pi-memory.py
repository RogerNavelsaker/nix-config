#!/usr/bin/env python3
"""Opt-in, backup-first configuration of the agent's Pi memory packages."""

import argparse
import copy
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path


PACKAGES = (
    "npm:pi-lossless@0.1.0",
    "npm:@mnemosyne-oss/pi-mnemosyne@0.1.0",
    "npm:@zosmaai/pi-llm-wiki@0.12.5",
)
PACKAGE_NAMES = (
    "pi-lossless",
    "@mnemosyne-oss/pi-mnemosyne",
    "@zosmaai/pi-llm-wiki",
)


def fail(message):
    raise ValueError(message)


def ensure_directory(path, mode=0o700):
    path = Path(path)
    if path.is_symlink():
        fail(f"Refusing symlinked directory: {path}")
    if path.exists():
        if not path.is_dir():
            fail(f"Refusing non-directory path: {path}")
        return
    ensure_directory(path.parent, mode)
    path.mkdir(mode=mode)


def ensure_agent_dir(home):
    pi_dir = home / ".pi"
    agent_dir = pi_dir / "agent"
    override = os.environ.get("PI_CODING_AGENT_DIR")
    if override and Path(override).expanduser().absolute() != agent_dir.absolute():
        fail("Refusing non-default PI_CODING_AGENT_DIR; setup targets ~/.pi/agent.")
    ensure_directory(pi_dir)
    ensure_directory(agent_dir)
    return agent_dir


def validate_target(path):
    if path.is_symlink():
        fail(f"Refusing symlinked config file: {path}")
    if path.exists() and not path.is_file():
        fail(f"Refusing non-file config target: {path}")


def reject_constant(value):
    fail(f"Invalid JSON constant: {value}")


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load_object(path):
    validate_target(path)
    if not path.exists():
        return {}
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        fail(f"Refusing invalid JSON in {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"Refusing non-object JSON in {path}")
    return value


def package_source(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict):
        source = entry.get("source")
        return source if isinstance(source, str) else None
    return None


def matches_target_package(source):
    if not source:
        return False
    return any(
        source == f"npm:{name}" or source.startswith(f"npm:{name}@")
        for name in PACKAGE_NAMES
    )


def update_settings(settings):
    packages = settings.get("packages", [])
    extensions = settings.get("extensions", [])
    wiki = settings.get("llm-wiki", {})
    if not isinstance(packages, list):
        fail("Refusing non-array settings.packages")
    if not isinstance(extensions, list):
        fail("Refusing non-array settings.extensions")
    if not isinstance(wiki, dict):
        fail("Refusing non-object settings.llm-wiki")

    retained = []
    for entry in packages:
        source = package_source(entry)
        if source and "engram" in source.lower():
            continue
        if matches_target_package(source):
            continue
        retained.append(entry)
    for package in PACKAGES:
        if package not in retained:
            retained.append(package)

    settings["packages"] = retained
    settings["extensions"] = [
        entry
        for entry in extensions
        if not (isinstance(entry, str) and "engram" in entry.lower())
    ]
    wiki["ambientPersonalVault"] = False
    wiki["trajectories"] = False
    settings["llm-wiki"] = wiki
    return settings


def update_lcm(lcm):
    # These competing token/smart-zone settings override the requested ratio thresholds.
    for key in ("smartZone", "zones", "swapAtTokens", "recutAtTokens"):
        lcm.pop(key, None)
    lcm["swapAtRatio"] = 0.7
    lcm["recutAtRatio"] = 0.7
    return lcm


def serialize(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def backup_files(home, files):
    existing = [path for path in files if path.exists()]
    if not existing:
        return None

    backup_root = home / ".local" / "state" / "pi" / "backups"
    ensure_directory(backup_root)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    backup_dir = backup_root / f"pi-memory-setup-pre-{stamp}-{os.getpid()}"
    suffix = 0
    while backup_dir.exists():
        suffix += 1
        backup_dir = backup_root / f"pi-memory-setup-pre-{stamp}-{os.getpid()}-{suffix}"
    backup_dir.mkdir(mode=0o700)
    for path in existing:
        shutil.copy2(path, backup_dir / path.name)
    return backup_dir


def atomic_write(path, content):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-home", required=True)
    parser.add_argument("--pi-bin", required=True)
    args = parser.parse_args()

    home_value = os.environ.get("HOME")
    expected_home = Path(args.expected_home).absolute()
    if not home_value or Path(home_value).absolute() != expected_home:
        fail(f"Run with HOME={expected_home}")
    home = expected_home
    if home.is_symlink() or not home.is_dir() or home.stat().st_uid != os.getuid():
        fail(f"Refusing unexpected or unowned agent home: {home}")

    pi_bin = Path(args.pi_bin)
    if not pi_bin.is_file() or not os.access(pi_bin, os.X_OK):
        fail(f"Pi CLI is not executable: {pi_bin}")

    agent_dir = ensure_agent_dir(home)
    settings_path = agent_dir / "settings.json"
    lcm_path = agent_dir / "lcm.json"

    settings_before = load_object(settings_path)
    lcm_before = load_object(lcm_path)
    settings_after = update_settings(copy.deepcopy(settings_before))
    lcm_after = update_lcm(copy.deepcopy(lcm_before))
    writes = []
    for path, before, after in (
        (settings_path, settings_before, settings_after),
        (lcm_path, lcm_before, lcm_after),
    ):
        if not path.exists() or before != after:
            writes.append((path, serialize(after)))

    backup_dir = backup_files(home, [path for path, _ in writes])
    for path, content in writes:
        atomic_write(path, content)
    if backup_dir:
        print(f"Backed up existing Pi settings to {backup_dir}")

    env = os.environ.copy()
    env["HOME"] = str(home)
    for package in PACKAGES:
        subprocess.run(
            [str(pi_bin), "install", package, "--no-approve"],
            cwd=home,
            env=env,
            check=True,
        )
    print("Pi memory packages configured; restart Pi to load them.")
    print("For verbatim LCM recall, use lcm_expand_query with max_tokens=24000 when needed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"Pi memory setup failed: {exc}", file=sys.stderr)
        sys.exit(1)
