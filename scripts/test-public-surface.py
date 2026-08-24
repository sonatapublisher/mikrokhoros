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

from __future__ import annotations

import importlib.util
import copy
import html
import json
import os
import tempfile
import unittest
import unicodedata
import urllib.parse
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_public_surface", ROOT / "scripts/check-public-surface.py"
)
assert SPEC and SPEC.loader
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)
PRODUCT_TOKEN = "Mikro" + "Khoros"
TERMINAL_SPEC = importlib.util.spec_from_file_location(
    "test_terminal", ROOT / "scripts/test-terminal.py"
)
assert TERMINAL_SPEC and TERMINAL_SPEC.loader
TERMINAL = importlib.util.module_from_spec(TERMINAL_SPEC)
TERMINAL_SPEC.loader.exec_module(TERMINAL)


class PublicSurfaceTests(unittest.TestCase):
    def test_unicode_normalization_is_applied_before_policy_checks(self) -> None:
        compatibility = "ＭｉｋｒｏＫｈｏｒｏｓ"
        self.assertEqual(CHECK.normalized(compatibility), PRODUCT_TOKEN)
        self.assertIsNotNone(CHECK.PRODUCT_CASE.search(CHECK.normalized(compatibility)))

    def test_technical_module_paths_are_not_public_brand_claims(self) -> None:
        text = "Keep Sources/" + PRODUCT_TOKEN + "CLIKit as the technical Swift target."
        self.assertIsNone(CHECK.PRODUCT_CASE.search(CHECK.public_text_for_case_check(text)))

    def test_forbidden_categories_have_deterministic_patterns(self) -> None:
        samples = {
            "account": "@iamducnhat",
            "auth": "ghp_" + "a" * 24,
            "prompt": "<|system|>",
            "tool-schema": "mcp__private_tool",
            "provider": "OPENAI_API_KEY",
            "secret": '"token": "literal-secret-value"',
            "local-path": "/Users/private-user/project",
            "private-endpoint": "https://10.0.0.1/private",
            "draft": "codex/private-branch",
        }
        for category, sample in samples.items():
            patterns = dict(CHECK.FORBIDDEN_PATTERNS)
            self.assertIsNotNone(patterns[category].search(sample), category)
        self.assertIsNone(dict(CHECK.FORBIDDEN_PATTERNS)["draft"].search("Open a pull request"))

    def test_bounded_decoding_catches_encoded_instruction_markers(self) -> None:
        samples = (
            html.escape("<|system|>"),
            urllib.parse.quote("<|system|>"),
            r"\u003c|system|\u003e",
            "PHxzeXN0ZW18Pg==",
            "3c7c73797374656d7c3e",
            '"PHxz" + "eXN0" + "ZW18" + "Pg=="',
        )
        prompt = dict(CHECK.FORBIDDEN_PATTERNS)["prompt"]
        for sample in samples:
            self.assertTrue(any(prompt.search(view) for view in CHECK.decoded_views(sample)))

    def test_built_textual_artifact_is_scanned_without_leaking_content(self) -> None:
        encoded_marker = "PHxzeXN0ZW18Pg=="
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=ROOT) as artifact:
            artifact.write("mikrokhoros CLI\n" + PRODUCT_TOKEN + "\n" + encoded_marker)
            artifact.flush()
            path = Path(artifact.name)
            case_errors = CHECK.validate_product_case([path])
            content_errors = CHECK.validate_forbidden_content([path])
        self.assertEqual(len(case_errors), 1)
        self.assertIn("product name must be lowercase", case_errors[0])
        self.assertTrue(any("forbidden prompt content" in error for error in content_errors))
        self.assertTrue(all(encoded_marker not in error for error in content_errors))

    def test_encoded_product_casing_is_rejected(self) -> None:
        samples = (
            "Mikro%4Bhoros",
            "Mikro%254Bhoros",
            "Mikro&#x4B;horos",
            "Mikro&amp;#x4B;horos",
            r"Mikro\u004Bhoros",
            "TWlrcm9LaG9yb3M=",
        )
        for sample in samples:
            with self.subTest(sample=sample):
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=ROOT) as artifact:
                    artifact.write(sample)
                    artifact.flush()
                    errors = CHECK.validate_product_case([Path(artifact.name)])
                self.assertEqual(len(errors), 1)
                self.assertIn("product name must be lowercase", errors[0])

    def test_encoded_and_noncanonical_product_urls_are_rejected(self) -> None:
        facts = CHECK.load_facts()
        samples = (
            urllib.parse.quote("https://mikrokhoros.org/?preview=1", safe=""),
            "https&#x3A;//mikrokhoros.org/#draft",
            r"https\u003a\u002f\u002fmikrokhoros.org\u002f\u003fpreview\u003d1",
            "https://github.com/sonatapublisher/mikrokhoros/private-internal-path",
            "https://github.com/sonatapublisher/mikrokhoros/tree/main/docs/unknown",
            "https://mikrokhoros.org.evil.example/",
            "https://github.com@evil.example/sonatapublisher/mikrokhoros",
            "https://github.com.evil.example/sonatapublisher/mikrokhoros",
            "https://evil.example/sonatapublisher/mikrokhoros",
        )
        for sample in samples:
            with self.subTest(sample=sample):
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=ROOT) as artifact:
                    artifact.write(sample)
                    artifact.flush()
                    errors = CHECK.validate_url_claims(facts, [Path(artifact.name)])
                self.assertTrue(any("absent from the fact contract" in error for error in errors))

    def test_url_claims_reject_deceptive_product_authorities(self) -> None:
        facts = CHECK.load_facts()
        samples = (
            "https://evil-mikrokhoros.org/",
            "https://mikrokhoros.org.evil.example/",
            "https://mikrokhoros.org@evil.example/",
            "https://github.com/sonatapublisher/mikrokhoros?preview=1",
            "https://github.com/sonatapublisher/mikrokhoros/private-internal-path",
        )
        for sample in samples:
            with self.subTest(sample=sample):
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=ROOT) as artifact:
                    artifact.write(sample)
                    artifact.flush()
                    errors = CHECK.validate_url_claims(facts, [Path(artifact.name)])
                self.assertTrue(any("absent from the fact contract" in error for error in errors))

    def test_terminal_binary_is_fixed_to_inherited_swiftpm_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            build_directory = Path(directory)
            binary = build_directory / "khoros"
            binary.write_bytes(b"fixture")
            binary.chmod(0o755)
            with mock.patch.object(
                TERMINAL.pathlib.Path,
                "cwd",
                return_value=build_directory,
            ):
                self.assertEqual(
                    TERMINAL.validated_build_directory(),
                    build_directory.resolve(),
                )
                binary.unlink()
                outside = build_directory / "outside"
                outside.write_bytes(b"fixture")
                outside.chmod(0o755)
                binary.symlink_to(outside)
                with self.assertRaisesRegex(ValueError, "symbolic link"):
                    TERMINAL.validated_build_directory()

    def test_terminal_wrapper_derives_the_binary_directory_from_swiftpm(self) -> None:
        wrapper = (ROOT / "scripts/test-terminal.sh").read_text(encoding="utf-8")
        self.assertIn("swift build $SWIFT_BUILD_FLAGS --show-bin-path", wrapper)
        self.assertIn('cd "$build_directory"', wrapper)
        self.assertIn('exec python3 "$project_root/scripts/test-terminal.py"', wrapper)
        self.assertNotIn("KHOROS_BIN", wrapper)

    def test_malformed_urls_fail_closed_without_echoing_content(self) -> None:
        facts = CHECK.load_facts()
        for sample in ("https://[", "https://[gggg]/x"):
            with self.subTest(sample=sample):
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=ROOT) as artifact:
                    artifact.write(sample)
                    artifact.flush()
                    errors = CHECK.validate_url_claims(facts, [Path(artifact.name)])
                self.assertTrue(any("malformed URL content" in error for error in errors))
                self.assertTrue(all(sample not in error for error in errors))

    def test_private_endpoint_variants_are_rejected(self) -> None:
        pattern = dict(CHECK.FORBIDDEN_PATTERNS)["private-endpoint"]
        for sample in (
            "http://localhost:4174/private",
            "http://127.99.1.2/x",
            "https://10.0.0.2/x",
            "https://172.16.0.2/x",
            "https://192.168.1.2/x",
            "https://169.254.169.254/latest",
            "http://[::1]/x",
            "http://[fe80::1]/x",
            "http://[fd00::1]/x",
            "https://service.local/x",
            "https://service.internal/x",
        ):
            with self.subTest(sample=sample):
                self.assertTrue(pattern.search(sample) or CHECK.contains_private_endpoint(sample))
        for sample in (
            "http://[::]/x",
            "http://[fe80::1%25en0]/x",
            "http://user@127.0.0.1/x",
            "http://2130706433/x",
            "http://0x7f000001/x",
        ):
            with self.subTest(sample=sample):
                self.assertTrue(CHECK.contains_private_endpoint(sample))

    def test_codeowners_allowance_is_exact(self) -> None:
        approved = "\n".join(CHECK.APPROVED_CODEOWNER_LINES)
        self.assertNotIn("@iamducnhat", CHECK.forbidden_scan_text(".github/CODEOWNERS", approved))
        unexpected = approved + "\nREADME.md @iamducnhat\n"
        scanned = CHECK.forbidden_scan_text(".github/CODEOWNERS", unexpected)
        self.assertIsNotNone(dict(CHECK.FORBIDDEN_PATTERNS)["account"].search(scanned or ""))

    def test_release_topology_binds_facts_only_commit_to_parent(self) -> None:
        facts = CHECK.load_facts()
        launch_parent = "a" * 40
        publication_commit = "c" * 40
        merge_commit = "d" * 40
        unrelated_parent = "f" * 40
        launch_tree = "e" * 40
        facts["sourceRevision"] = launch_parent
        facts["sourceTree"] = launch_tree
        parent_facts = copy.deepcopy(facts)
        parent_facts["sourceRevision"] = "b" * 40
        parent_facts["sourceTree"] = "9" * 40

        def fake_git_output(*args: str) -> str:
            if args == ("rev-parse", "HEAD"):
                return publication_commit
            if args == ("rev-list", "--parents", "-n", "1", publication_commit):
                return f"{publication_commit} {launch_parent}"
            if args == ("show", f"{publication_commit}:docs/public-facts.json"):
                return json.dumps(facts)
            if args == (
                "diff-tree", "--no-commit-id", "--name-only", "-r", publication_commit
            ):
                return "docs/public-facts.json"
            if args == (
                "diff-tree",
                "--no-commit-id",
                "--numstat",
                "-r",
                publication_commit,
                "--",
                "docs/public-facts.json",
            ):
                return "2\t2\tdocs/public-facts.json"
            if args == ("show", f"{launch_parent}:docs/public-facts.json"):
                return json.dumps(parent_facts)
            if args == ("rev-parse", f"{launch_parent}^{{tree}}"):
                return launch_tree
            if args == ("rev-parse", f"{publication_commit}^{{tree}}"):
                return "8" * 40
            if args == ("rev-parse", f"{merge_commit}^{{tree}}"):
                return "8" * 40
            if args == ("rev-list", "--parents", "-n", "1", merge_commit):
                return f"{merge_commit} {unrelated_parent} {publication_commit}"
            if args == ("show", f"{unrelated_parent}:docs/public-facts.json"):
                return json.dumps({})
            self.fail(f"unexpected Git call: {args}")

        with mock.patch.object(CHECK, "git_output", side_effect=fake_git_output):
            self.assertEqual(
                CHECK.validate_release_topology(facts),
                (publication_commit, launch_parent, launch_tree),
            )
            with mock.patch.object(CHECK, "git_output", side_effect=lambda *args: (
                merge_commit if args == ("rev-parse", "HEAD") else fake_git_output(*args)
            )):
                self.assertEqual(
                    CHECK.validate_release_topology(facts),
                    (publication_commit, launch_parent, launch_tree),
                )

    def test_release_topology_rejects_non_atomic_fact_change(self) -> None:
        facts = CHECK.load_facts()
        launch_parent = "a" * 40
        publication_commit = "c" * 40
        facts["sourceRevision"] = launch_parent
        facts["sourceTree"] = "e" * 40

        def fake_git_output(*args: str) -> str:
            if args == ("show", f"{publication_commit}:docs/public-facts.json"):
                return json.dumps(facts)
            if args == ("rev-list", "--parents", "-n", "1", publication_commit):
                return f"{publication_commit} {launch_parent}"
            if args == ("rev-parse", f"{launch_parent}^{{tree}}"):
                return "e" * 40
            if args == (
                "diff-tree", "--no-commit-id", "--name-only", "-r", publication_commit
            ):
                return "docs/public-facts.json"
            if args[:2] == ("diff-tree", "--no-commit-id"):
                return "3\t3\tdocs/public-facts.json"
            self.fail(f"unexpected Git call: {args}")

        with mock.patch.object(CHECK, "git_output", side_effect=fake_git_output):
            with self.assertRaisesRegex(CHECK.PublicSurfaceError, "exactly two"):
                CHECK.validate_publication_commit(facts, publication_commit)

    def test_merge_topology_rejects_tree_drift(self) -> None:
        facts = CHECK.load_facts()
        launch_parent = "a" * 40
        publication_commit = "c" * 40
        merge_commit = "d" * 40
        launch_tree = "e" * 40
        facts["sourceRevision"] = launch_parent
        facts["sourceTree"] = launch_tree
        parent_facts = copy.deepcopy(facts)
        parent_facts["sourceRevision"] = "b" * 40
        parent_facts["sourceTree"] = "9" * 40

        def fake_git_output(*args: str) -> str:
            values = {
                ("rev-parse", "HEAD"): merge_commit,
                ("rev-list", "--parents", "-n", "1", merge_commit): (
                    f"{merge_commit} {'f' * 40} {publication_commit}"
                ),
                ("show", f"{'f' * 40}:docs/public-facts.json"): "{}",
                ("show", f"{publication_commit}:docs/public-facts.json"): json.dumps(facts),
                ("rev-list", "--parents", "-n", "1", publication_commit): (
                    f"{publication_commit} {launch_parent}"
                ),
                (
                    "diff-tree", "--no-commit-id", "--name-only", "-r", publication_commit
                ): "docs/public-facts.json",
                (
                    "diff-tree", "--no-commit-id", "--numstat", "-r",
                    publication_commit, "--", "docs/public-facts.json",
                ): "2\t2\tdocs/public-facts.json",
                ("show", f"{launch_parent}:docs/public-facts.json"): json.dumps(parent_facts),
                ("rev-parse", f"{launch_parent}^{{tree}}"): launch_tree,
                ("rev-parse", f"{merge_commit}^{{tree}}"): "7" * 40,
                ("rev-parse", f"{publication_commit}^{{tree}}"): "8" * 40,
            }
            if args not in values:
                self.fail(f"unexpected Git call: {args}")
            return values[args]

        with mock.patch.object(CHECK, "git_output", side_effect=fake_git_output):
            with self.assertRaisesRegex(CHECK.PublicSurfaceError, "no reviewed"):
                CHECK.validate_release_topology(facts)

    def test_detector_sources_are_excluded_from_case_and_url_claim_scans(self) -> None:
        fixture = PRODUCT_TOKEN + " https://mikrokhoros.org/?adversarial=1"
        scanned = [("scripts/test-public-surface.py", fixture)]
        with mock.patch.object(CHECK, "_scan_paths", return_value=scanned):
            self.assertEqual(CHECK.validate_product_case(), [])
            self.assertEqual(CHECK.validate_url_claims(CHECK.load_facts()), [])

    def test_repository_text_reader_rejects_symlinks(self) -> None:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as outside:
            link = ROOT / ".public-surface-test-link"
            try:
                os.symlink(outside.name, link)
                with self.assertRaisesRegex(CHECK.PublicSurfaceError, "escapes repository"):
                    CHECK.repository_text_path(link.name)
            finally:
                link.unlink(missing_ok=True)

    def test_build_output_scan_rejects_outside_and_symlink_paths(self) -> None:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as outside:
            outside.write("mikrokhoros")
            outside.flush()
            with self.assertRaisesRegex(CHECK.PublicSurfaceError, "outside the repository"):
                CHECK.validate_product_case([Path(outside.name)])
            link = ROOT / ".public-surface-build-link"
            try:
                os.symlink(outside.name, link)
                with self.assertRaisesRegex(CHECK.PublicSurfaceError, "outside the repository"):
                    CHECK.validate_url_claims(CHECK.load_facts(), [link])
            finally:
                link.unlink(missing_ok=True)

    def test_fact_sheet_validates_assets_urls_and_ctas(self) -> None:
        facts = CHECK.load_facts()
        CHECK.validate_facts(facts)
        CHECK.validate_assets(facts)
        self.assertEqual(CHECK.validate_url_claims(facts), [])
        self.assertEqual(len(facts["approvedAssets"]), 4)
        self.assertEqual(facts["canonical"]["productURL"], "https://mikrokhoros.org/")
        self.assertEqual([cta["label"] for cta in facts["allowedCTAs"]], [
            "View source",
            "Read the docs",
            "Install khoros",
            "Open mikrokhoros Web",
        ])

    def test_fact_sheet_root_contract_rejects_unknown_keys(self) -> None:
        facts = CHECK.load_facts()
        facts["unexpected"] = True
        with self.assertRaisesRegex(CHECK.PublicSurfaceError, "root keys"):
            CHECK.validate_facts(facts)

    def test_public_file_inventory_is_discovered_not_curated(self) -> None:
        files = CHECK.public_text_files()
        self.assertIn("docs/ui-design.md", files)
        self.assertNotIn("docs/ui-design-draft.txt", files)
        self.assertNotIn("docs/idea-v2.txt", files)

    def test_technical_storage_paths_are_not_public_brand_claims(self) -> None:
        text = "PowerShell stores the executable under " + PRODUCT_TOKEN + r"\bin."
        self.assertIsNone(CHECK.PRODUCT_CASE.search(CHECK.public_text_for_case_check(text)))

    def test_checked_in_fact_sheet_passes(self) -> None:
        facts = CHECK.load_facts()
        CHECK.validate_facts(facts)
        self.assertEqual(CHECK.validate(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
