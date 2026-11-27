#!/usr/bin/env python3
"""Fixture tests for the opt-in Pi memory setup app."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "setup-pi-memory.py"
EXPECTED_PACKAGES = [
    "npm:pi-lossless@0.1.0",
    "npm:@mnemosyne-oss/pi-mnemosyne@0.1.0",
    "npm:@zosmaai/pi-llm-wiki@0.12.5",
]


class PiMemorySetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.agent_dir = self.home / ".pi" / "agent"
        self.agent_dir.mkdir(parents=True)
        self.log = self.root / "pi-calls.jsonl"
        self.fake_pi = self.root / "pi"
        self.fake_pi.write_text(
            "#!" + sys.executable + "\n"
            "import json, os, sys\n"
            "with open(os.environ['PI_CALL_LOG'], 'a') as f:\n"
            "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        )
        self.fake_pi.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def run_setup(self, *, succeeds=True, extra_env=None):
        env = os.environ.copy()
        env.update({"HOME": str(self.home), "PI_CALL_LOG": str(self.log)})
        env.pop("PI_CODING_AGENT_DIR", None)
        if extra_env:
            env.update(extra_env)
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--expected-home",
                str(self.home),
                "--pi-bin",
                str(self.fake_pi),
            ],
            env=env,
            text=True,
            capture_output=True,
        )
        if succeeds and result.returncode:
            self.fail(f"setup failed ({result.returncode}): {result.stderr}\n{result.stdout}")
        if not succeeds:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_merges_settings_pins_packages_and_backs_up(self):
        settings_path = self.agent_dir / "settings.json"
        original_settings = {
            "theme": "system",
            "custom": {"keep": True},
            "packages": [
                "npm:other-package",
                {"source": "npm:pi-lossless@0.0.1", "autoload": False},
                "npm:@engram/pi-extension@1.2.3",
                {"source": "npm:@engram/old-extension", "autoload": False},
            ],
            "extensions": ["builtin:mcp", "extensions/engram.ts"],
            "llm-wiki": {
                "ambientPersonalVault": True,
                "trajectories": True,
                "notices": False,
            },
        }
        settings_path.write_text(json.dumps(original_settings, indent=2) + "\n")
        lcm_path = self.agent_dir / "lcm.json"
        original_lcm = {
            "summarizer": "auto",
            "smartZone": 1000,
            "zones": {"provider/model": {"swapAtTokens": 1000}},
        }
        lcm_path.write_text(json.dumps(original_lcm, indent=2) + "\n")
        original_settings_bytes = settings_path.read_bytes()
        original_lcm_bytes = lcm_path.read_bytes()

        self.run_setup()

        settings = json.loads(settings_path.read_text())
        self.assertEqual(settings["theme"], "system")
        self.assertEqual(settings["custom"], {"keep": True})
        self.assertEqual(settings["llm-wiki"], {
            "ambientPersonalVault": False,
            "trajectories": False,
            "notices": False,
        })
        self.assertIn("npm:other-package", settings["packages"])
        self.assertNotIn("npm:@engram/pi-extension@1.2.3", settings["packages"])
        self.assertNotIn(
            {"source": "npm:@engram/pi-lossless@0.0.1", "autoload": False},
            settings["packages"],
        )
        self.assertFalse(any(
            isinstance(package, dict) and "engram" in package.get("source", "").lower()
            for package in settings["packages"]
        ))
        self.assertNotIn("extensions/engram.ts", settings["extensions"])
        for package in EXPECTED_PACKAGES:
            self.assertIn(package, settings["packages"])
        self.assertIn("builtin:mcp", settings["extensions"])

        lcm = json.loads(lcm_path.read_text())
        self.assertEqual(lcm["swapAtRatio"], 0.7)
        self.assertEqual(lcm["recutAtRatio"], 0.7)
        self.assertEqual(lcm["summarizer"], "auto")
        self.assertNotIn("smartZone", lcm)
        self.assertNotIn("zones", lcm)

        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls, [["install", package, "--no-approve"] for package in EXPECTED_PACKAGES])

        backup_dirs = list((self.home / ".local/state/pi/backups").glob("pi-memory-setup-pre-*"))
        self.assertEqual(len(backup_dirs), 1)
        self.assertEqual((backup_dirs[0] / "settings.json").read_bytes(), original_settings_bytes)
        self.assertEqual((backup_dirs[0] / "lcm.json").read_bytes(), original_lcm_bytes)

        self.run_setup()
        self.assertEqual(
            len(list((self.home / ".local/state/pi/backups").glob("pi-memory-setup-pre-*"))),
            1,
        )

    def test_refuses_symlinked_settings_without_installing(self):
        target = self.root / "settings.json"
        target.write_text("{}\n")
        (self.agent_dir / "settings.json").symlink_to(target)

        result = self.run_setup(succeeds=False)

        self.assertIn("symlink", result.stderr.lower())
        self.assertEqual(target.read_text(), "{}\n")
        self.assertFalse(self.log.exists())

    def test_refuses_invalid_json_without_installing(self):
        settings_path = self.agent_dir / "settings.json"
        settings_path.write_text("{not json")

        result = self.run_setup(succeeds=False)

        self.assertIn("json", result.stderr.lower())
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
