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

"""Validate the repository's canonical public facts and launch output.

The check is dependency-free and deterministic. It discovers tracked public
text rather than maintaining a prose allowlist, verifies the machine-readable
fact contract and approved PNG assets, and can additionally inspect generated
textual artifacts with ``--build-output``. Technical Swift identifiers and
paths are masked only by the narrow patterns documented in
``public_text_for_case_check``; user-visible prose is never masked.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import html
import ipaddress
import json
import os
import re
import subprocess
import sys
import unicodedata
import urllib.parse
from pathlib import Path
from typing import Any, Iterable, Iterator


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "docs/public-facts.json"
RESOURCE_INVENTORY_PATH = "docs/shipped-resource-inventory.json"
PRODUCT_ROOT = "Mikro" + "Khoros"

DESCRIPTION = (
    "Open source AI agent harness for object-first worlds. Every persistent world "
    "capability an agent can invoke is an exact concrete object with declared "
    "functions, identity, state, location, authority, and history; the runtime "
    "enforces locality, possession, permissions, bounded actions, and replayable "
    "trajectories."
)
CATEGORY = "AI agent harness"
PRIMARY_STATEMENT = "An open source AI agent harness for object-first worlds."
REPOSITORY_URL = "https://github.com/sonatapublisher/mikrokhoros"
HOMEPAGE_URL = "https://mikrokhoros.org/"
LICENSE_URL = "https://www.apache.org/licenses/LICENSE-2.0"

PRODUCT_CASE = re.compile(
    r"(?<![A-Za-z0-9_])" + re.escape(PRODUCT_ROOT) + r"(?![A-Za-z0-9_])"
)
HYPHENATED_OPEN_SOURCE = re.compile(r"(?i)\bopen-source\b")
# Public links in Markdown/HTML are tokenized at structural delimiters. The
# approved URL contract contains no parentheses/brackets, and treating those
# delimiters as token boundaries prevents a neighboring link from being
# accidentally accepted as one repository URL.
URL_TOKEN = re.compile(r"https?://[^\s<>\"'()]+", re.IGNORECASE)

# Binary files are reviewed through their fact-sheet hash/dimensions, not as
# text. Every tracked regular text file is discovered. A very small set of
# policy/test/governance files is excluded from the forbidden-content pass
# because those files necessarily contain detector patterns, adversarial
# fixtures, or repository-maintainer instructions; they remain covered by
# product-case, syntax, and dedicated regression checks. Swift implementation
# is discovered for exact technical-identifier casing checks. The Web
# resource directory and any explicitly supplied build output are shipped
# output.
BINARY_SUFFIXES = {
    ".7z",
    ".a",
    ".dylib",
    ".gif",
    ".gz",
    ".ico",
    ".jpeg",
    ".jpg",
    ".mov",
    ".mp3",
    ".mp4",
    ".pdf",
    ".png",
    ".so",
    ".tar",
    ".ttf",
    ".wav",
    ".webp",
    ".woff",
    ".woff2",
    ".zip",
}
PUBLIC_ASSET_ROOTS = ("assets", "docs/assets")
# These are governance or detector-test sources, not user-facing launch
# output. Keep this set exact and small: adding an entry requires a regression
# test and a matching explanation in docs/security.md.
SENSITIVE_EXCLUDED_FILES = {
    "scripts/check-public-surface.py",
    "scripts/test-public-surface.py",
}
APPROVED_CODEOWNER_LINES = (
    "* @iamducnhat",
    ".github/ @iamducnhat",
    "SECURITY.md @iamducnhat",
)

# These are exact technical exemptions, not a general case-insensitive brand
# allowance. Module/target identifiers can be title case; public prose cannot.
TECHNICAL_PATH = re.compile(
    r"(?:Sources|Tests|scripts)/" + PRODUCT_ROOT + r"(?:CLIKit|Services|Web|Tests)?(?=/|\\|\s|`|\b)"
)
STORAGE_PATH = re.compile(re.escape(PRODUCT_ROOT) + r"\\bin")
TECHNICAL_IDENTIFIER = re.compile(
    r"\b" + PRODUCT_ROOT + r"(?:CLIKit|Services|Web|Tests|Error|Paths|PathContext|WebHost)\b"
)
IMPORT_LINE = re.compile(
    r"(?m)^(\s*(?:@testable\s+)?import\s+)" + PRODUCT_ROOT + r"\b"
)

# Runtime implementation contracts. These masks are path-specific below and
# do not turn the detector into a general provider/endpoint allowlist.
TECHNICAL_PROVIDER = re.compile(
    r"(?i)(?:\bopenai(?:-compatible)?\b|\banthropic\b|\bgemini\b|\bdeepinfra\b|"
    r"\bollama\b|\blm[- ]studio\b|\bvllm\b|\bazure[- ]openai\b|"
    r"\b(?:OPENAI|ANTHROPIC|GEMINI|DEEPINFRA|AZURE_OPENAI)_[A-Z0-9_]*(?:KEY|TOKEN|SECRET)\b|"
    r"https?://(?:api\.)?(?:openai|anthropic|generativelanguage|deepinfra)\.[^\s\"']+"
    r")"
)
TECHNICAL_ROLE = re.compile(
    r"(?i)(?:\brole\s*:\s*\"(?:system|assistant|user|developer)\"|"
    r"[\"']role[\"']\s*[:=]\s*[\"'](?:system|assistant|user|developer)[\"'])"
)
TECHNICAL_LOOPBACK_URL = re.compile(
    r"(?i)https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::(?:[0-9]+|\\\\?\([^)]*\\\\?\)))?(?:[/#?][^\s\"']*)?"
)
TEST_TECHNICAL_PROVIDER = TECHNICAL_PROVIDER
TEST_TECHNICAL_ROLE = TECHNICAL_ROLE
TEST_TECHNICAL_LOOPBACK_URL = re.compile(
    r"(?i)https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::(?:[0-9]+|\\\\?\([^)]*\\\\?\)))?(?:[/#?][^\s\"']*)?"
)
TEST_SECRET_FIXTURE = re.compile(
    r'(?m)\blet\s+secret\s*=\s*(?:#".*?"#|"[^"\r\n]*")'
)
TEST_TOKEN_BODY = re.compile(
    r'(?m)body:\s*Data\(#[^\r\n]*\btoken\b[^\r\n]*#\.utf8\)'
)
TEST_TOKEN_DATA = re.compile(
    r'(?is)Data\(\s*(?:#?".*?\btoken\b.*?"#?|\'.*?\btoken\b.*?\')\s*\.utf8\s*\)'
)
TEST_SECRET_OBJECT = re.compile(r'(?is)["\']secret["\']\s*:\s*["\'][^"\'\r\n]*["\']')
TEST_ESCAPED_SECRET_STRING = re.compile(
    r'(?is)"(?:\\\\.|[^"\\\\])*\bsecret\b(?:\\\\.|[^"\\\\])*"'
)

# Sensitive-content patterns intentionally match values and protocol markers,
# not ordinary public security guidance such as the words "credential" or
# "provider". Named provider/model references are rejected in public output;
# technical adapter identifiers remain in implementation source by design.
FORBIDDEN_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "account",
        re.compile(r"(?i)(?:@iamducnhat\b|iamducnhat@gmail\.com\b|aeternitas-world\b)"),
    ),
    (
        "auth",
        re.compile(
            r"(?i)(?:gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|"
            r"Bearer\s+[A-Za-z0-9._~+/=-]{20,})"
        ),
    ),
    (
        "prompt",
        re.compile(
            r"(?i)(?:<\|(?:system|assistant|user|developer)\|>|"
            r"BEGIN\s+(?:PRIVATE|SYSTEM|CONFIDENTIAL)\s+PROMPT|PRIVATE_PROMPT\s*[:=])"
        ),
    ),
    (
        "role",
        re.compile(
            r"(?i)(?:\brole\s*:\s*[\"'](?:system|assistant|user|developer)[\"']|"
            r"[\"']role[\"']\s*[:=]\s*[\"'](?:system|assistant|user|developer)[\"']|"
            r"<\|(?:system|assistant|user|developer)\|>)"
        ),
    ),
    (
        "tool-schema",
        re.compile(
            r"(?i)(?:\bmcp__[A-Za-z0-9_-]+\b|\bexec_command\b|\btool_call\b|"
            r"\bfunction_call\b|[\"']tools?[\"']\s*:\s*\[)"
        ),
    ),
    (
        "provider",
        re.compile(
            r"(?i)(?:\bopenai\b|\banthropic\b|\bgemini\b|\bdeepinfra\b|"
            r"\bollama\b|\blm studio\b|\bvllm\b|\bazure openai\b|"
            r"https?://(?:api\.)?(?:openai|anthropic|generativelanguage|deepinfra)\b|"
            r"\b(?:OPENAI|ANTHROPIC|GEMINI|DEEPINFRA)_[A-Z0-9_]*(?:KEY|TOKEN|SECRET)\b)"
        ),
    ),
    (
        "secret",
        re.compile(
            r"(?i)(?:[\"']?\b(?:password|secret|token|api[_-]?key)\b[\"']?\s*[:=]\s*"
            r"(?:\"[^\"\r\n]{8,}\"|'[^'\r\n]{8,}'))"
        ),
    ),
    (
        "local-path",
        re.compile(
            r"(?i)(?:/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|"
            r"/private/tmp/[^\s`]+|[A-Z]:\\\\Users\\[^\s`]+)"
        ),
    ),
    (
        "private-endpoint",
        re.compile(
            r"(?i)(?<![A-Za-z0-9])https?://(?:"
            r"localhost|0\.0\.0\.0|"
            r"10(?:\.\d{1,3}){3}|127(?:\.\d{1,3}){3}|"
            r"169\.254(?:\.\d{1,3}){2}|"
            r"172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|"
            r"192\.168(?:\.\d{1,3}){2}|"
            r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:internal|local)|"
            r"\[(?:::1|fe[89a-fA-F][0-9a-fA-F:]*|f[cd][0-9a-fA-F:]*|"
            r"::ffff:(?:10|127|169\.254|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.[0-9a-fA-F:.]+)\]"
            r")(?:\:\d{1,5})?(?:[/#?][^\s<>\"']*)?"
        ),
    ),
    (
        "draft",
        re.compile(
            r"(?i)(?:\bcodex/|\bworktree\b|\bPR\s*#\d+|"
            r"\b(?:draft|wip)\s+(?:pull request|pr)\b|"
            r"\b(?:pull request|pr)\s+(?:draft|wip)\b)"
        ),
    ),
)

ESCAPED_UNICODE = re.compile(r"\\u([0-9a-fA-F]{4})|\\U([0-9a-fA-F]{8})|\\x([0-9a-fA-F]{2})")
ESCAPED_JSON = re.compile(r"\\([\"\\/bfnrt])")
BASE64_CANDIDATE = re.compile(r"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/_-]{12,}={0,2}(?![A-Za-z0-9+/=_-])")
HEX_CANDIDATE = re.compile(r"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}){8,}(?![0-9A-Fa-f])")
FRAGMENTED_BASE64 = re.compile(
    r"(?:(?:[A-Za-z0-9+/_-]{4,32})[\s\"'`+,:;\\]*){3,}[A-Za-z0-9+/_-]{4,32}={0,2}"
)
ENCODED_RUN = re.compile(r"[A-Za-z0-9+/_=-]{4,64}")
JSON_ESCAPES = {
    '"': '"',
    "\\": "\\",
    "/": "/",
    "b": "\b",
    "f": "\f",
    "n": "\n",
    "r": "\r",
    "t": "\t",
}
MAX_SCAN_CHARS = 1_000_000
MAX_DECODE_CANDIDATE = 4096
MAX_DECODE_VIEWS = 64


class PublicSurfaceError(Exception):
    """A deterministic public-surface validation failure."""


def normalized(value: str) -> str:
    """Normalize Unicode before applying any textual policy."""

    return unicodedata.normalize("NFKC", value)


def repository_file_path(relative_path: str) -> Path:
    candidate = Path(relative_path)
    if candidate.is_absolute():
        raise PublicSurfaceError(f"public-surface path must be repository-relative: {relative_path}")
    path = ROOT / candidate
    root_resolved = ROOT.resolve()
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise PublicSurfaceError(f"missing public-surface file: {relative_path}") from error
    try:
        contained = os.path.commonpath((str(root_resolved), str(resolved))) == str(root_resolved)
    except ValueError as error:
        raise PublicSurfaceError(f"public-surface path escapes repository: {relative_path}") from error
    if not contained or path.is_symlink():
        raise PublicSurfaceError(f"public-surface path escapes repository: {relative_path}")
    for parent in path.parents:
        if parent == ROOT:
            break
        if parent.is_symlink():
            raise PublicSurfaceError(f"public-surface path uses a symlink: {relative_path}")
    if not resolved.is_file():
        raise PublicSurfaceError(f"missing public-surface file: {relative_path}")
    return resolved


def repository_text_path(relative_path: str) -> Path:
    return repository_file_path(relative_path)


def read_text(relative_path: str) -> str:
    path = repository_text_path(relative_path)
    try:
        value = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise PublicSurfaceError(f"public text is not UTF-8: {relative_path}") from error
    if len(value) > MAX_SCAN_CHARS:
        raise PublicSurfaceError(f"public text exceeds bounded scan size: {relative_path}")
    return normalized(value)


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise PublicSurfaceError(f"duplicate fact-sheet key: {key}")
        result[key] = value
    return result


def load_facts() -> dict[str, Any]:
    try:
        value = json.loads(
            read_text("docs/public-facts.json"), object_pairs_hook=reject_duplicate_keys
        )
    except json.JSONDecodeError as error:
        raise PublicSurfaceError(f"fact sheet is not valid JSON: line {error.lineno}") from error
    if not isinstance(value, dict):
        raise PublicSurfaceError("fact sheet root must be an object")
    return value


def load_resource_inventory() -> dict[str, Any]:
    try:
        value = json.loads(
            read_text(RESOURCE_INVENTORY_PATH), object_pairs_hook=reject_duplicate_keys
        )
    except json.JSONDecodeError as error:
        raise PublicSurfaceError(
            f"resource inventory is not valid JSON: line {error.lineno}"
        ) from error
    if not isinstance(value, dict):
        raise PublicSurfaceError("resource inventory root must be an object")
    return value


def assert_exact(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise PublicSurfaceError(f"fact sheet claim mismatch: {label}")


def expected_assets() -> list[dict[str, Any]]:
    return [
        {
            "path": "assets/mikrokhoros-logo.png",
            "sha256": "cae4292b970468a9ce7930c07e2cbc5d3fb4271c8020eb776322812975c1ed1e",
            "width": 448,
            "height": 448,
            "role": "icon",
            "provenance": "tracked repository asset; reviewed without geometry or color changes",
        },
        {
            "path": "assets/mikrokhoros-world-map.png",
            "sha256": "617e65dcb6b119b0bdd195fc1955c105541ab593aa041bdef29a4a08359dfe39",
            "width": 1024,
            "height": 683,
            "role": "concept illustration",
            "provenance": "tracked repository asset; reviewed without geometry or color changes",
        },
        {
            "path": "assets/mikrokhoros-amphitheatre.png",
            "sha256": "0e6e10f94f61ad44c9a0fa8cf7e3d969eff7a9e2328dea980f2c47e15d0b0e00",
            "width": 1024,
            "height": 683,
            "role": "concept illustration",
            "provenance": "tracked repository asset; reviewed without geometry or color changes",
        },
        {
            "path": "docs/assets/design-v2-template-view.png",
            "sha256": "5c959b63501c684aa4061626eb5d9e189fa080c2effcb39981a4fdd4bb2847a7",
            "width": 1280,
            "height": 853,
            "role": "design reference",
            "provenance": "tracked repository asset; reviewed without geometry or color changes",
        },
    ]


def expected_facts_shape() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "sourceRevisionPolicy": "This immutable revision is the exact launch-source commit represented by this fact sheet.",
        "claimAuthority": {
            "canonical": "docs/public-facts.json",
            "runtime": [
                ".github/workflows/ci.yml",
                "Package.swift",
                "Sources/",
                "Tests/",
                "docs/design.md",
                "docs/security.md",
            ],
        },
        "canonical": {
            "publicName": "mikrokhoros",
            "repositorySlug": "mikrokhoros",
            "repositoryURL": REPOSITORY_URL,
            "productURL": HOMEPAGE_URL,
            "executable": "khoros",
        },
        "wordmark": {
            "text": "mikrokhoros",
            "kind": "text wordmark",
        },
        "product": {
            "name": "mikrokhoros",
            "slug": "mikrokhoros",
            "executable": "khoros",
            "category": CATEGORY,
            "primaryStatement": PRIMARY_STATEMENT,
            "description": DESCRIPTION,
            "openSource": True,
            "license": "Apache-2.0",
            "lifecycle": "pre-release",
            "stableRelease": False,
        },
        "runtime": {
            "language": "Swift",
            "swiftToolsVersion": "6.1",
            "platforms": {
                "macOS": {
                    "minimum": "13+",
                    "support": "supported",
                    "evidence": "Package.swift",
                },
                "Linux": {
                    "minimum": "Swift 6.1+",
                    "support": "supported",
                    "evidence": ".github/workflows/ci.yml",
                },
                "Windows": {
                    "minimum": "Swift 6.1+",
                    "support": "supported",
                    "evidence": ".github/workflows/ci.yml",
                },
            },
            "webSurface": {
                "name": "mikrokhoros Web",
                "kind": "native loopback browser interface",
                "executable": "khoros",
            },
        },
        "urls": {
            "repository": REPOSITORY_URL,
            "homepage": HOMEPAGE_URL,
            "license": LICENSE_URL,
        },
        "assetReview": {
            "baselineRevision": "4c993ecb86c73b18512e94fb0787ae36660bbe87",
            "geometryUnchanged": True,
            "colorsUnchanged": True,
        },
        "approvedAssets": expected_assets(),
        "allowedCTAs": [
            {
                "id": "source",
                "label": "View source",
                "url": REPOSITORY_URL,
            },
            {
                "id": "docs",
                "label": "Read the docs",
                "url": f"{REPOSITORY_URL}/tree/main/docs",
            },
            {
                "id": "install",
                "label": "Install khoros",
                "url": f"{REPOSITORY_URL}#install-khoros",
            },
            {
                "id": "web",
                "label": "Open mikrokhoros Web",
                "url": f"{REPOSITORY_URL}#open-mikrokhoros-web",
            },
        ],
    }


def git_output(*args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", *args], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise PublicSurfaceError("Git metadata is unavailable for public-surface validation") from error


def git_bytes(*args: str) -> bytes:
    try:
        return subprocess.check_output(["git", *args], cwd=ROOT, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError) as error:
        raise PublicSurfaceError("Git metadata is unavailable for public-surface validation") from error


def validate_facts(facts: dict[str, Any]) -> None:
    expected = expected_facts_shape()
    expected_root_keys = {"schemaVersion", "sourceRevision", "sourceTree", *expected.keys()}
    if set(facts) != expected_root_keys:
        raise PublicSurfaceError("fact sheet root keys do not match the closed public contract")
    assert_exact(facts.get("schemaVersion"), expected["schemaVersion"], "schemaVersion")
    source_revision = facts.get("sourceRevision")
    if not isinstance(source_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", source_revision):
        raise PublicSurfaceError("sourceRevision must be a full lowercase Git commit SHA")
    try:
        git_output("cat-file", "-e", f"{source_revision}^{{commit}}")
    except PublicSurfaceError as error:
        raise PublicSurfaceError("sourceRevision must identify an existing Git commit") from error
    source_tree = facts.get("sourceTree")
    if not isinstance(source_tree, str) or not re.fullmatch(r"[0-9a-f]{40}", source_tree):
        raise PublicSurfaceError("sourceTree must be a full lowercase Git tree SHA")
    if git_output("rev-parse", f"{source_revision}^{{tree}}") != source_tree:
        raise PublicSurfaceError("sourceTree must identify the sourceRevision tree")
    for key in (
        "sourceRevisionPolicy",
        "claimAuthority",
        "canonical",
        "wordmark",
        "product",
        "runtime",
        "urls",
        "assetReview",
        "approvedAssets",
        "allowedCTAs",
    ):
        assert_exact(facts.get(key), expected[key], key)
    for authority in facts["claimAuthority"]["runtime"]:
        target = authority.rstrip("/")
        try:
            object_type = git_output("cat-file", "-t", f"{source_revision}:{target}")
        except PublicSurfaceError as error:
            raise PublicSurfaceError(f"runtime claim authority is absent: {authority}") from error
        expected_type = "tree" if authority.endswith("/") else "blob"
        if object_type != expected_type:
            raise PublicSurfaceError(f"runtime claim authority has the wrong Git type: {authority}")


def parse_fact_sheet(value: str, label: str) -> dict[str, Any]:
    try:
        parsed = json.loads(value, object_pairs_hook=reject_duplicate_keys)
    except json.JSONDecodeError as error:
        raise PublicSurfaceError(f"{label} is not valid JSON: line {error.lineno}") from error
    if not isinstance(parsed, dict):
        raise PublicSurfaceError(f"{label} root must be an object")
    return parsed


def validate_publication_commit(
    facts: dict[str, Any], publication_commit: str
) -> tuple[str, str]:
    candidate_facts = parse_fact_sheet(
        git_output("show", f"{publication_commit}:docs/public-facts.json"),
        "publication fact sheet",
    )
    if candidate_facts != facts:
        raise PublicSurfaceError("publication commit does not contain the checked-out fact sheet")
    lineage = git_output(
        "rev-list", "--parents", "-n", "1", publication_commit
    ).split()
    if len(lineage) != 2:
        raise PublicSurfaceError("publication commit must have exactly one launch-source parent")
    parent = lineage[1]
    if facts.get("sourceRevision") != parent:
        raise PublicSurfaceError("sourceRevision must equal the launch-source parent commit")
    launch_tree = git_output("rev-parse", f"{parent}^{{tree}}")
    if facts.get("sourceTree") != launch_tree:
        raise PublicSurfaceError("sourceTree must equal the launch-source parent tree")
    changed_paths = tuple(
        path
        for path in git_output(
            "diff-tree", "--no-commit-id", "--name-only", "-r", publication_commit
        ).splitlines()
        if path
    )
    if changed_paths != ("docs/public-facts.json",):
        raise PublicSurfaceError("publication commit may change only docs/public-facts.json")
    numstat = git_output(
        "diff-tree",
        "--no-commit-id",
        "--numstat",
        "-r",
        publication_commit,
        "--",
        "docs/public-facts.json",
    ).split()
    if numstat != ["2", "2", "docs/public-facts.json"]:
        raise PublicSurfaceError("publication commit must replace exactly two fact-sheet lines")
    parent_facts = parse_fact_sheet(
        git_output("show", f"{parent}:docs/public-facts.json"),
        "launch-source fact sheet",
    )
    current_without_revision = dict(facts)
    parent_without_revision = dict(parent_facts)
    current_without_revision.pop("sourceRevision", None)
    parent_without_revision.pop("sourceRevision", None)
    current_without_revision.pop("sourceTree", None)
    parent_without_revision.pop("sourceTree", None)
    if current_without_revision != parent_without_revision:
        raise PublicSurfaceError("publication commit may replace only sourceRevision and sourceTree")
    if not re.fullmatch(r"[0-9a-f]{40}", launch_tree):
        raise PublicSurfaceError("launch-source tree identity is unavailable")
    return parent, launch_tree


def validate_release_topology(facts: dict[str, Any]) -> tuple[str, str, str]:
    """Bind the fact sheet to a facts-only commit on a branch or merge tip."""

    head = git_output("rev-parse", "HEAD")
    lineage = git_output("rev-list", "--parents", "-n", "1", head).split()
    if len(lineage) == 2:
        candidates = (head,)
    elif len(lineage) == 3:
        candidates = tuple(lineage[1:])
    else:
        raise PublicSurfaceError("checked-out revision has an unsupported publication topology")
    for candidate in candidates:
        try:
            parent, launch_tree = validate_publication_commit(facts, candidate)
            if git_output("rev-parse", f"{head}^{{tree}}") != git_output(
                "rev-parse", f"{candidate}^{{tree}}"
            ):
                continue
            return candidate, parent, launch_tree
        except PublicSurfaceError:
            continue
    raise PublicSurfaceError("no reviewed facts-only publication commit is reachable from HEAD")


def validate_codeowners() -> None:
    lines = tuple(
        line.strip()
        for line in read_text(".github/CODEOWNERS").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    if lines != APPROVED_CODEOWNER_LINES:
        raise PublicSurfaceError("CODEOWNERS must contain only the approved maintainer routes")


def tracked_paths() -> Iterator[str]:
    output = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    for raw_path in output.split(b"\0"):
        if raw_path:
            yield raw_path.decode("utf-8")


def is_public_text_path(relative_path: str) -> bool:
    if Path(relative_path).suffix.lower() in BINARY_SUFFIXES:
        return False
    return True


def public_text_files() -> list[str]:
    return sorted(path for path in tracked_paths() if is_public_text_path(path))


def _printable_utf8(data: bytes) -> str | None:
    if not data or len(data) > MAX_DECODE_CANDIDATE:
        return None
    try:
        value = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not value or sum(char.isprintable() or char.isspace() for char in value) < len(value) * 0.9:
        return None
    return normalized(value)


def _encoded_candidates(text: str) -> Iterable[str]:
    """Decode bounded base64/base64url, hex, and separated base64 candidates once."""

    candidates = list(BASE64_CANDIDATE.findall(text))
    candidates.extend(HEX_CANDIDATE.findall(text))
    candidates.extend(match.group(0) for match in FRAGMENTED_BASE64.finditer(text))
    runs = list(ENCODED_RUN.finditer(text))
    for index, first in enumerate(runs):
        chunks = [first.group(0)]
        for following in runs[index + 1 : index + 9]:
            separator = text[runs[index + len(chunks) - 1].end() : following.start()]
            if not separator or len(separator) > 16 or re.search(r"[^\s\"'`+,:;\\]", separator):
                break
            chunks.append(following.group(0))
            if len(chunks) >= 3:
                candidates.append("".join(chunks))
    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen or len(candidate) > MAX_DECODE_CANDIDATE:
            continue
        seen.add(candidate)
        compact = re.sub(r"[\s\"'`+,:;\\]", "", candidate)
        if len(compact) >= 16:
            padded = compact + "=" * ((4 - len(compact) % 4) % 4)
            try:
                decoded = base64.b64decode(padded, altchars=b"-_", validate=True)
            except (binascii.Error, ValueError):
                decoded = b""
            value = _printable_utf8(decoded)
            if value is not None:
                yield value
        if re.fullmatch(r"(?:[0-9A-Fa-f]{2})+", compact) and len(compact) >= 16:
            try:
                value = _printable_utf8(bytes.fromhex(compact))
            except ValueError:
                value = None
            if value is not None:
                yield value


def decoded_views(text: str) -> Iterable[str]:
    """Return at most two bounded decoding layers with a strict view budget."""

    def replace_escape(match: re.Match[str]) -> str:
        value = match.group(1) or match.group(2) or match.group(3)
        try:
            codepoint = int(value, 16)
            return chr(codepoint) if codepoint <= 0x10FFFF else match.group(0)
        except ValueError:
            return match.group(0)

    original = normalized(text)
    views = [original]
    frontier = [original]
    for _ in range(2):
        next_frontier: list[str] = []
        for source in frontier:
            escaped_view = normalized(ESCAPED_UNICODE.sub(replace_escape, source))
            candidates = (
                normalized(html.unescape(source)),
                normalized(urllib.parse.unquote(source)),
                escaped_view,
                normalized(
                    ESCAPED_JSON.sub(
                        lambda match: JSON_ESCAPES[match.group(1)], escaped_view
                    )
                ),
                *_encoded_candidates(source),
            )
            for candidate in candidates:
                if candidate != source and candidate not in views:
                    if len(views) >= MAX_DECODE_VIEWS:
                        break
                    views.append(candidate)
                    next_frontier.append(candidate)
            if len(views) >= MAX_DECODE_VIEWS:
                break
        frontier = next_frontier
        if not frontier or len(views) >= MAX_DECODE_VIEWS:
            break
    for view in views:
        if len(view) <= MAX_SCAN_CHARS:
            yield view


def public_text_for_case_check(text: str, relative_path: str = "") -> str:
    """Mask only explicit Swift/module/path identifiers before case checking."""

    text = TECHNICAL_PATH.sub("technical-module-path", text)
    text = STORAGE_PATH.sub("technical-storage-path", text)
    text = TECHNICAL_IDENTIFIER.sub("technical-identifier", text)
    text = IMPORT_LINE.sub(r"\1technical-import", text)
    if relative_path == "Package.swift":
        # Package target/product names are case-sensitive SwiftPM identifiers.
        text = text.replace(PRODUCT_ROOT, "technical-package-name")
    return text


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _scan_paths(build_outputs: Iterable[Path]) -> list[tuple[str, str]]:
    paths = [(relative_path, read_text(relative_path)) for relative_path in public_text_files()]
    for build_path in build_outputs:
        candidate = build_path if build_path.is_absolute() else ROOT / build_path
        try:
            relative_path = str(candidate.resolve(strict=True).relative_to(ROOT.resolve()))
            build_text = read_text(relative_path)
        except (OSError, UnicodeDecodeError, ValueError, PublicSurfaceError) as error:
            raise PublicSurfaceError(
                f"generated textual artifact is outside the repository or unreadable: {build_path}"
            ) from error
        paths.append((relative_path, build_text))
    return paths


def validate_product_case(build_outputs: Iterable[Path] = ()) -> list[str]:
    errors: set[str] = set()
    for relative_path, text in _scan_paths(build_outputs):
        if relative_path in SENSITIVE_EXCLUDED_FILES:
            continue
        # Mask reviewed case-sensitive implementation identifiers before and
        # after decoding. The first pass prevents JSON escape decoding from
        # turning a technical Windows path into ordinary-looking prose.
        case_source = public_text_for_case_check(text, relative_path)
        for view in decoded_views(case_source):
            case_view = public_text_for_case_check(view, relative_path)
            if PRODUCT_CASE.search(case_view):
                errors.add(f"{relative_path}: product name must be lowercase")
            if HYPHENATED_OPEN_SOURCE.search(view):
                errors.add(f"{relative_path}: use the canonical phrase 'Open source'")
    return sorted(errors)


def forbidden_scan_text(relative_path: str, text: str) -> str | None:
    """Return the content to inspect for forbidden public-surface values.

    The default is the complete tracked text. The only masks are exact,
    path-scoped implementation contracts: the AI adapter catalog and its
    protocol role/endpoint literals, loopback URLs emitted by the native Web
    server/CLI, and the same values in Swift integration fixtures. This keeps
    a newly introduced provider, prompt marker, credential literal, or
    private endpoint visible to the linter everywhere else.
    """

    if relative_path in SENSITIVE_EXCLUDED_FILES:
        return None

    if relative_path == ".github/CODEOWNERS":
        text = "\n".join(
            line.replace("@iamducnhat", "approved-maintainer")
            if line.strip() in APPROVED_CODEOWNER_LINES
            else line
            for line in text.splitlines()
        )

    if relative_path == "Sources/MikroKhoros/AI.swift":
        text = TECHNICAL_PROVIDER.sub("technical-provider", text)
        text = TECHNICAL_ROLE.sub("technical-role", text)
        text = TECHNICAL_LOOPBACK_URL.sub("technical-loopback-url", text)
    elif relative_path in {
        "Sources/MikroKhorosWeb/WebServer.swift",
        "Sources/MikroKhorosCLIKit/KhorosCommandRunner.swift",
    }:
        text = TECHNICAL_LOOPBACK_URL.sub("technical-loopback-url", text)
    elif relative_path.startswith("Tests/"):
        # Tests are tracked source but their adapter/loopback literals are
        # non-shipped protocol fixtures. Mask only the reviewed technical
        # forms; arbitrary new sensitive content still fails below.
        text = TEST_TECHNICAL_PROVIDER.sub("technical-provider", text)
        text = TEST_TECHNICAL_ROLE.sub("technical-role", text)
        text = TEST_TECHNICAL_LOOPBACK_URL.sub("technical-loopback-url", text)
        text = TEST_SECRET_FIXTURE.sub("technical-secret-fixture", text)
        text = TEST_TOKEN_BODY.sub("technical-token-fixture", text)
        text = TEST_TOKEN_DATA.sub("technical-token-fixture", text)
        text = TEST_SECRET_OBJECT.sub("technical-secret-fixture", text)
        text = TEST_ESCAPED_SECRET_STRING.sub("technical-secret-fixture", text)
    return text


def validate_forbidden_content(build_outputs: Iterable[Path] = ()) -> list[str]:
    errors: list[str] = []
    for relative_path, text in _scan_paths(build_outputs):
        text = forbidden_scan_text(relative_path, text)
        if text is None:
            continue
        if not text:
            errors.append(f"{relative_path}: generated textual artifact is unreadable")
            continue
        for view in decoded_views(text):
            # Decoding can materialize an adversarial fixture after the
            # path-scoped technical mask ran. Reapply the same narrow mask to
            # every bounded view before policy matching.
            view = forbidden_scan_text(relative_path, view)
            if view is None:
                continue
            for category, pattern in FORBIDDEN_PATTERNS:
                if pattern.search(view):
                    # Never include the matched value in diagnostics.
                    errors.append(f"{relative_path}: forbidden {category} content")
            if contains_private_endpoint(view):
                errors.append(f"{relative_path}: forbidden private-endpoint content")
    return sorted(set(errors))


def contains_private_endpoint(text: str) -> bool:
    for value in URL_TOKEN.findall(text):
        candidate = value.rstrip(".,;:!?])")
        try:
            parsed = urllib.parse.urlsplit(candidate)
            host = parsed.hostname
        except ValueError:
            host = None
        if not host:
            continue
        normalized_host = host.lower().rstrip(".")
        if normalized_host in {"localhost", "0.0.0.0"}:
            return True
        if normalized_host.endswith((".local", ".internal")):
            return True
        address_host = normalized_host.split("%", 1)[0]
        try:
            if re.fullmatch(r"0x[0-9a-f]+", address_host):
                address = ipaddress.ip_address(int(address_host, 16))
            elif address_host.isdigit() and int(address_host) <= 0xFFFFFFFF:
                address = ipaddress.ip_address(int(address_host))
            else:
                address = ipaddress.ip_address(address_host)
        except ValueError:
            continue
        if not address.is_global:
            return True
    return False


def png_dimensions(path: Path) -> tuple[int, int]:
    try:
        header = path.read_bytes()[:24]
    except OSError as error:
        raise PublicSurfaceError(f"approved asset is unreadable: {path}") from error
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise PublicSurfaceError(f"approved asset is not a PNG: {path}")
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def validate_assets(facts: dict[str, Any]) -> None:
    approved = facts["approvedAssets"]
    baseline_revision = facts["assetReview"]["baselineRevision"]
    try:
        git_output("cat-file", "-e", f"{baseline_revision}^{{commit}}")
    except PublicSurfaceError as error:
        raise PublicSurfaceError("asset-review baseline must identify an existing Git commit") from error
    approved_paths = {asset["path"] for asset in approved}
    discovered_paths = {
        path
        for root_name in PUBLIC_ASSET_ROOTS
        for candidate in (ROOT / root_name).rglob("*")
        if candidate.is_file() and candidate.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
        for path in [str(candidate.relative_to(ROOT)).replace("\\", "/")]
    }
    if discovered_paths != approved_paths:
        raise PublicSurfaceError("fact sheet approved asset set does not match tracked public assets")
    for asset in approved:
        path = ROOT / asset["path"]
        if not path.is_file():
            raise PublicSurfaceError(f"missing approved asset: {asset['path']}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != asset["sha256"]:
            raise PublicSurfaceError(f"approved asset hash mismatch: {asset['path']}")
        try:
            baseline_bytes = git_bytes("show", f"{baseline_revision}:{asset['path']}")
        except PublicSurfaceError as error:
            raise PublicSurfaceError(
                f"approved asset is absent from the asset-review baseline: {asset['path']}"
            ) from error
        if hashlib.sha256(baseline_bytes).hexdigest() != digest:
            raise PublicSurfaceError(
                f"approved asset differs from the asset-review baseline: {asset['path']}"
            )
        width, height = png_dimensions(path)
        if (width, height) != (asset["width"], asset["height"]):
            raise PublicSurfaceError(f"approved asset dimensions mismatch: {asset['path']}")


def validate_resource_inventory() -> None:
    inventory = load_resource_inventory()
    assert_exact(inventory.get("schemaVersion"), 1, "resource inventory schemaVersion")
    assert_exact(
        inventory.get("source"),
        "SwiftPM processed resources under Sources/MikroKhorosWeb/Resources",
        "resource inventory source",
    )
    files = inventory.get("files")
    if not isinstance(files, list) or not files:
        raise PublicSurfaceError("resource inventory files must be a non-empty list")
    inventory_paths: set[str] = set()
    for item in files:
        if not isinstance(item, dict) or set(item) != {"path", "sha256", "kind"}:
            raise PublicSurfaceError("resource inventory entry shape is invalid")
        path = item["path"]
        digest = item["sha256"]
        kind = item["kind"]
        expected_kind = resource_kind(path) if isinstance(path, str) else None
        if (
            not isinstance(path, str)
            or not path.startswith("Sources/MikroKhorosWeb/Resources/")
            or path in inventory_paths
            or not isinstance(digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", digest)
            or kind != expected_kind
        ):
            raise PublicSurfaceError("resource inventory entry value is invalid")
        inventory_paths.add(path)
        actual_path = repository_file_path(path)
        if hashlib.sha256(actual_path.read_bytes()).hexdigest() != digest:
            raise PublicSurfaceError(f"resource inventory hash mismatch: {path}")

    discovered_paths = {
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in (ROOT / "Sources/MikroKhorosWeb/Resources").rglob("*")
        if path.is_file() and resource_kind(str(path.relative_to(ROOT)).replace("\\", "/"))
    }
    if discovered_paths != inventory_paths:
        raise PublicSurfaceError("resource inventory does not cover every shipped font, SVG, and license")


def resource_kind(relative_path: str) -> str | None:
    suffix = Path(relative_path).suffix.lower()
    if "/fonts/" in relative_path and suffix in {".woff", ".woff2", ".ttf", ".otf"}:
        return "font"
    if "/icons/" in relative_path and suffix == ".svg":
        return "icon"
    if "/identity-shapes/" in relative_path and suffix == ".svg":
        return "identity-shape"
    if "/licenses/" in relative_path and suffix in {".txt", ".md"}:
        return "license"
    return None


def validate_tracked_symlinks() -> None:
    root_resolved = ROOT.resolve()
    for relative_path in tracked_paths():
        path = ROOT / relative_path
        if not path.is_symlink():
            continue
        resolved = path.resolve()
        try:
            os.path.commonpath((str(root_resolved), str(resolved)))
        except ValueError as error:
            raise PublicSurfaceError(f"tracked symlink escapes repository: {relative_path}") from error
        if os.path.commonpath((str(root_resolved), str(resolved))) != str(root_resolved):
            raise PublicSurfaceError(f"tracked symlink escapes repository: {relative_path}")
        raise PublicSurfaceError(f"tracked symlink is not allowed in public source: {relative_path}")


def validate_url_claims(
    facts: dict[str, Any], build_outputs: Iterable[Path] = ()
) -> list[str]:
    errors: list[str] = []
    allowed_cta_urls = {cta["url"] for cta in facts["allowedCTAs"]}
    allowed_asset_urls = {
        f"{REPOSITORY_URL}/raw/refs/heads/main/{asset['path']}" for asset in facts["approvedAssets"]
    }
    allowed_urls = {
        REPOSITORY_URL,
        f"{REPOSITORY_URL}/actions/workflows/ci.yml",
        f"{REPOSITORY_URL}/actions/workflows/ci.yml/badge.svg?branch=main",
        f"{REPOSITORY_URL}/discussions",
        f"{REPOSITORY_URL}/security/policy",
        *allowed_cta_urls,
        *allowed_asset_urls,
    }
    for relative_path, text in _scan_paths(build_outputs):
        if relative_path in SENSITIVE_EXCLUDED_FILES or not text:
            continue
        for view in decoded_views(text):
            for url in URL_TOKEN.findall(view):
                value = url.rstrip(".,;:!?])")
                try:
                    parsed = urllib.parse.urlsplit(value)
                    host = (parsed.hostname or "").lower()
                except ValueError:
                    errors.append(f"{relative_path}: malformed URL content")
                    continue
                host_tokens = tuple(
                    token for token in re.split(r"[^a-z0-9]+", host.casefold()) if token
                )
                username_tokens = tuple(
                    token
                    for token in re.split(r"[^a-z0-9]+", (parsed.username or "").casefold())
                    if token
                )
                product_like = (
                    "mikrokhoros" in host_tokens
                    or "mikrokhoros" in username_tokens
                    or host == "mikrokhoros.org"
                    or host.endswith(".mikrokhoros.org")
                )
                repository_segments = tuple(
                    urllib.parse.unquote(segment).casefold()
                    for segment in parsed.path.split("/")
                    if segment
                )
                repository_like = (
                    len(repository_segments) >= 2
                    and repository_segments[:2] == ("sonatapublisher", "mikrokhoros")
                )
                if product_like and value != HOMEPAGE_URL:
                    errors.append(f"{relative_path}: product URL claim is absent from the fact contract")
                if repository_like and value not in allowed_urls:
                    errors.append(f"{relative_path}: repository URL is absent from the fact contract")
    return sorted(set(errors))


def require_text(relative_path: str, value: str, label: str) -> None:
    text = read_text(relative_path)
    if value not in text:
        raise PublicSurfaceError(f"{relative_path} is missing canonical {label}")


def validate_claim_consistency(facts: dict[str, Any]) -> None:
    product = facts["product"]
    canonical = facts["canonical"]
    runtime = facts["runtime"]
    urls = facts["urls"]
    require_text("README.md", product["description"], "description")
    require_text("README.md", canonical["publicName"], "public name")
    require_text("README.md", canonical["repositorySlug"], "repository slug")
    require_text("README.md", product["executable"], "executable")
    require_text("README.md", urls["repository"], "repository URL")
    require_text("README.md", urls["homepage"], "homepage URL")
    require_text("README.md", urls["license"], "license URL")
    require_text("README.md", "Apache-2.0", "license identifier")
    require_text("README.md", "pre-release", "lifecycle")
    require_text("README.md", f"Swift {runtime['swiftToolsVersion']}", "Swift version")
    require_text("README.md", "macOS 13+", "macOS platform")
    require_text("README.md", "Linux with Swift 6.1+", "Linux platform")
    require_text("README.md", "Windows with Swift 6.1+", "Windows platform")
    require_text("README.md", runtime["webSurface"]["kind"], "Web surface")
    require_text("CITATION.cff", urls["repository"], "citation repository URL")
    require_text("docs/cli-reference.md", "khoros", "CLI executable")
    require_text("Sources/MikroKhorosWeb/Resources/index.html", "mikrokhoros", "Web wordmark")
    for cta in facts["allowedCTAs"]:
        require_text("README.md", cta["label"], f"CTA label {cta['id']}")
        require_text("README.md", cta["url"], f"CTA URL {cta['id']}")
    require_text("README.md", "geometry and colors are unchanged", "asset review")


def validate(
    build_outputs: Iterable[Path] = (), require_launch_topology: bool = False
) -> list[str]:
    errors: list[str] = []
    try:
        facts = load_facts()
        validate_facts(facts)
        if require_launch_topology:
            validate_release_topology(facts)
        validate_assets(facts)
        validate_resource_inventory()
        validate_tracked_symlinks()
        validate_codeowners()
        validate_claim_consistency(facts)
    except PublicSurfaceError as error:
        errors.append(str(error))
        facts = None
    try:
        errors.extend(validate_product_case(build_outputs))
        errors.extend(validate_forbidden_content(build_outputs))
        if facts is not None:
            errors.extend(validate_url_claims(facts, build_outputs))
    except PublicSurfaceError as error:
        errors.append(str(error))
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--build-output",
        action="append",
        default=[],
        type=Path,
        help="additional generated textual artifact to scan (repeatable)",
    )
    parser.add_argument(
        "--require-launch-topology",
        action="store_true",
        help="require a facts-only HEAD whose sourceRevision is its launch-content parent",
    )
    args = parser.parse_args()
    errors = validate(
        args.build_output,
        require_launch_topology=args.require_launch_topology,
    )
    if errors:
        for error in errors:
            print(f"public-surface: {error}", file=sys.stderr)
        return 1
    facts = load_facts()
    evidence = ""
    if args.require_launch_topology:
        publication_revision, _, launch_tree = validate_release_topology(facts)
        evidence = f", publicationRevision={publication_revision}, launchTree={launch_tree}"
    print(
        "public-surface checks passed "
        f"(trackedPublicText={len(public_text_files())}, approvedAssets={len(facts['approvedAssets'])}, "
        f"facts=docs/public-facts.json, sourceRevision={facts['sourceRevision']}{evidence})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
