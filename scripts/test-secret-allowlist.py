#!/usr/bin/env python3
# Copyright © 2026 mikrokhoros contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Regression checks for the single narrow gitleaks false-positive exception."""

from __future__ import annotations

import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".gitleaks.toml"
SOURCE_PATH = "Sources/" + "Mikro" + "Khoros" + "/Credit.swift"
DECLARATION = "private let privateKey: Curve25519.Signing.PrivateKey"
KNOWN_COMMIT = "d2f11844ec6ba70ba1e2bf5317cd22720c813821"
PATH_PATTERN = r"^Sources/" + "Mikro" + "Khoros" + r"/Credit\.swift$"
REGEX_PATTERN = r"^\s*private let privateKey: Curve25519\.Signing\.PrivateKey\s*$"
DOCS_PATH_PATTERN = r"^docs/security\.md$"
DOCS_REGEX_PATTERN = (
    r"^`private let privateKey: Curve25519\.Signing\.PrivateKey` declaration in$"
)
TEST_PATH_PATTERN = r"^scripts/test-secret-allowlist\.py$"
TEST_REGEX_PATTERN = (
    r'^DECLARATION = "private let privateKey: Curve25519\.Signing\.PrivateKey"$'
)


def git_source(revision: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{revision}:{SOURCE_PATH}"],
        cwd=ROOT,
        text=True,
    )


def gitleaks_binary() -> str | None:
    """Return the fixed scanner command when it is available on ``PATH``.

    CI supplies the pinned scanner directory on ``PATH`` after verifying its
    release checksum. Local unit runs may use an already installed binary, but
    never download one. Returning the command name instead of an environment-
    supplied executable path keeps the subprocess invocation allowlisted.
    """
    return "gitleaks" if shutil.which("gitleaks") else None


class SecretAllowlistTests(unittest.TestCase):
    def test_config_is_path_and_line_exact(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        self.assertIn(f"paths = ['{PATH_PATTERN}']", config)
        self.assertIn('regexTarget = "line"', config)
        self.assertIn(f"regexes = ['{REGEX_PATTERN}']", config)
        self.assertIn(f"paths = ['{DOCS_PATH_PATTERN}']", config)
        self.assertIn(f"regexes = ['{DOCS_REGEX_PATTERN}']", config)
        self.assertIn(f"paths = ['{TEST_PATH_PATTERN}']", config)
        self.assertIn(f"regexes = ['{TEST_REGEX_PATTERN}']", config)
        self.assertEqual(config.count('regexTarget = "line"'), 3)
        self.assertNotIn("privateKey.*=", config)
        self.assertNotIn("generic-api-key", config)

    def test_current_declaration_has_no_value(self) -> None:
        matches = [
            line.strip()
            for line in git_source("HEAD").splitlines()
            if line.strip() == DECLARATION
        ]
        self.assertEqual(matches, [DECLARATION])
        self.assertNotIn("=", matches[0])

    def test_known_historical_finding_is_the_same_type_only_declaration(self) -> None:
        matches = [
            line.strip()
            for line in git_source(KNOWN_COMMIT).splitlines()
            if line.strip() == DECLARATION
        ]
        self.assertEqual(matches, [DECLARATION])
        self.assertNotIn("=", matches[0])
        self.assertTrue(re.fullmatch(REGEX_PATTERN, matches[0]))

    def test_full_history_scan_uses_this_allowlist_when_available(self) -> None:
        binary = gitleaks_binary()
        if binary is None:
            self.skipTest("gitleaks is not installed; CI installs its pinned binary")

        result = subprocess.run(
            [
                binary,
                "git",
                "--config",
                str(CONFIG),
                "--no-banner",
                "--redact",
                "--log-level",
                "error",
                "--log-opts=--all --full-history --reflog",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        # Keep command output out of test diagnostics: even redacted scanner
        # output should not become part of a public CI transcript.
        self.assertEqual(result.returncode, 0, "full-history gitleaks scan failed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
