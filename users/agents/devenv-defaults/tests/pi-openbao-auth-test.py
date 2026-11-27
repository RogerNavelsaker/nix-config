#!/usr/bin/env python3
"""Fixture tests for the opt-in Pi OpenBao auth migration."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "configure-pi-openbao-auth.py"
FIXTURE_KEY = "fixture-not-a-real-api-key"
INJECTED_KEY = "injected-test-value"


class PiOpenBaoAuthTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.agent_dir = self.home / ".pi" / "agent"
        self.agent_dir.mkdir(parents=True)
        self.auth_path = self.agent_dir / "auth.json"
        self.auth = {
            "litellm": {
                "type": "api_key",
                "key": FIXTURE_KEY,
                "env": {"LITELLM_BASE_URL": "https://proxy.example.invalid", "keep": "yes"},
            },
            "openai": {"type": "oauth", "access": "fixture-access", "refresh": "fixture-refresh"},
            "other": {"type": "api_key", "key": "other-fixture"},
        }
        self.auth_path.write_text(json.dumps(self.auth, indent=2) + "\n")
        self.auth_path.chmod(0o640)
        self.original = self.auth_path.read_bytes()

    def tearDown(self):
        self.tmp.cleanup()

    def run_setup(self, *, injected=True, injected_value=INJECTED_KEY, expected_home=None):
        env = os.environ.copy()
        env["HOME"] = str(self.home)
        env.pop("PI_CODING_AGENT_DIR", None)
        if injected:
            env["LITELLM_API_KEY"] = injected_value
        else:
            env.pop("LITELLM_API_KEY", None)
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--expected-home", str(expected_home or self.home)],
            env=env, text=True, capture_output=True,
        )

    def test_replaces_only_litellm_key_and_restricts_permissions(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        updated = json.loads(self.auth_path.read_text())
        self.assertEqual(updated["litellm"]["key"], "$LITELLM_API_KEY")
        self.assertEqual(updated["litellm"]["env"], self.auth["litellm"]["env"])
        self.assertEqual(updated["openai"], self.auth["openai"])
        self.assertEqual(updated["other"], self.auth["other"])
        self.assertNotIn(FIXTURE_KEY.encode(), self.auth_path.read_bytes())
        self.assertNotIn(FIXTURE_KEY, result.stdout + result.stderr)
        self.assertEqual(stat.S_IMODE(self.auth_path.stat().st_mode), 0o600)
        backups = list((self.home / ".local/state/pi/backups").glob("pi-openbao-auth-pre-*"))
        self.assertEqual(len(backups), 1)
        backup = backups[0] / "auth.json"
        self.assertEqual(backup.read_bytes(), self.original)
        self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)
        self.assertNotIn(FIXTURE_KEY, result.stdout + result.stderr)

    def test_is_idempotent_without_creating_another_backup(self):
        first = self.run_setup()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.run_setup()
        self.assertEqual(second.returncode, 0, second.stderr)
        backups = list((self.home / ".local/state/pi/backups").glob("pi-openbao-auth-pre-*"))
        self.assertEqual(len(backups), 1)

    def test_requires_injected_key_before_any_change(self):
        result = self.run_setup(injected=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LITELLM_API_KEY", result.stderr)
        self.assertEqual(self.auth_path.read_bytes(), self.original)
        self.assertFalse((self.home / ".local/state/pi/backups").exists())

    def test_refuses_blank_injected_key(self):
        result = self.run_setup(injected_value="  	")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LITELLM_API_KEY", result.stderr)
        self.assertEqual(self.auth_path.read_bytes(), self.original)
        self.assertFalse((self.home / ".local/state/pi/backups").exists())

    def test_refuses_symlink_and_leaves_target_unchanged(self):
        target = self.root / "outside-auth.json"
        target.write_bytes(self.original)
        self.auth_path.unlink()
        self.auth_path.symlink_to(target)
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr.lower())
        self.assertEqual(target.read_bytes(), self.original)

    def test_refuses_symlinked_backup_parent(self):
        outside = self.root / "outside"
        backup_root = outside / "state" / "pi" / "backups"
        backup_root.mkdir(parents=True)
        for directory in (outside, outside / "state", outside / "state" / "pi", backup_root):
            directory.chmod(0o700)
        (self.home / ".local").symlink_to(outside, target_is_directory=True)

        result = self.run_setup()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr.lower())
        self.assertEqual(self.auth_path.read_bytes(), self.original)
        self.assertEqual(list(backup_root.iterdir()), [])

    def test_refuses_group_writable_backup_ancestor(self):
        local_dir = self.home / ".local"
        local_dir.mkdir(mode=0o755)
        local_dir.chmod(0o777)

        result = self.run_setup()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("writable", result.stderr.lower())
        self.assertEqual(self.auth_path.read_bytes(), self.original)
        self.assertFalse((local_dir / "state").exists())

    def test_refuses_unexpected_auth_type(self):
        bad = dict(self.auth)
        bad["litellm"] = {"type": "oauth", "key": FIXTURE_KEY}
        self.auth_path.write_text(json.dumps(bad) + "\n")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("api_key", result.stderr)
        self.assertEqual(json.loads(self.auth_path.read_text()), bad)

    def test_refuses_group_writable_home(self):
        self.home.chmod(0o777)

        result = self.run_setup()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("writable", result.stderr.lower())
        self.assertEqual(self.auth_path.read_bytes(), self.original)

    def test_refuses_wrong_home(self):
        result = self.run_setup(expected_home=self.root / "other-home")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.auth_path.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()