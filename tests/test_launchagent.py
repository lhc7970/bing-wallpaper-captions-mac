"""Exercise the README's launchd command with offline stand-ins for both steps."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


README = Path(__file__).resolve().parents[1] / "README.md"


class LaunchAgentTests(unittest.TestCase):
    def test_daily_job_runs_both_steps_and_reports_failures(self):
        section = README.read_text().split("## Run daily with launchd\n", 1)[1]
        xml = section.split("```xml\n", 1)[1].split("\n```", 1)[0]
        template = plistlib.loads(xml.encode())["ProgramArguments"]

        with tempfile.TemporaryDirectory(prefix="launch agent ") as folder:
            args = [
                arg.replace("/Users/YOU/bing-wallpaper-captions-mac", folder)
                for arg in template
            ]
            for script, status in (("bing.sh", "DOWNLOAD_EXIT"), ("rotation.sh", "ROTATION_EXIT")):
                stub = Path(folder, script)
                stub.write_text(f'#!/bin/bash\necho {script}\nexit "${status}"\n')
                stub.chmod(0o755)

            for download, rotation in ((0, 0), (2, 0), (0, 1), (2, 1)):
                with self.subTest(download=download, rotation=rotation):
                    env = dict(os.environ, DOWNLOAD_EXIT=str(download), ROTATION_EXIT=str(rotation))
                    run = subprocess.run(args, cwd=folder, env=env, capture_output=True, text=True)
                    self.assertEqual(run.stdout.splitlines(), ["bing.sh", "rotation.sh"])
                    self.assertEqual(run.returncode, rotation or download, run.stderr)
