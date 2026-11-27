import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def build_config(base_config, command):
    command_json = json.dumps(command)
    return (
        base_config.rstrip()
        + "\n\nexec {\n"
        + f"  command = {command_json}\n"
        + '  restart_on_secret_changes = "always"\n'
        + '  restart_stop_signal = "SIGTERM"\n'
        + "}\n"
    )


def clean_agent_environment(environment):
    return {
        key: value
        for key, value in environment.items()
        if key != "LITELLM_API_KEY" and not key.startswith(("BAO_", "VAULT_"))
    }


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) < 3:
        raise SystemExit("usage: pi-with-openbao CONFIG BAO PI [PI-ARG ...]")

    config_path, bao_path, pi_path, *pi_args = argv
    base_config = Path(config_path).read_text(encoding="utf-8")
    rendered_config = build_config(base_config, [pi_path, *pi_args])

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir or not os.path.isdir(runtime_dir):
        runtime_dir = None

    try:
        fd, temporary_config = tempfile.mkstemp(
            prefix="pi-openbao-", suffix=".hcl", dir=runtime_dir
        )
    except OSError:
        if runtime_dir is None:
            raise
        fd, temporary_config = tempfile.mkstemp(
            prefix="pi-openbao-", suffix=".hcl"
        )

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(rendered_config)

        environment = clean_agent_environment(os.environ)
        try:
            return subprocess.run(
                [bao_path, "agent", f"-config={temporary_config}"],
                env=environment,
                check=False,
            ).returncode
        except KeyboardInterrupt:
            return 130
    finally:
        try:
            os.unlink(temporary_config)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
