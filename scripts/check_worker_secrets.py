#!/usr/bin/env python3
"""Fail closed when likely Worker secrets are present in the repository."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SECRET_NAMES = (
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "PUSH_WEBHOOK_SECRET",
    "APNS_KEY_ID",
    "APNS_TEAM_ID",
    "APNS_BUNDLE_ID",
    "APNS_PRIVATE_KEY",
    "CF_IMAGES_ACCOUNT_ID",
    "CF_IMAGES_API_TOKEN",
    "GOOGLE_VISION_API_KEY",
)

SKIP_DIRECTORIES = {".git", ".wrangler", "DerivedData", "build", "node_modules"}
SKIP_FILENAMES = {"worker-configuration.d.ts", "package-lock.json"}
EXAMPLE_FILENAMES = {".dev.vars.example", ".env.example"}
NON_SECRET_TYPE_VALUES = {"string", "undefined", "null"}

SECRET_FILE_PATTERN = re.compile(r"^(?:\.dev\.vars(?:\..*)?|\.env(?:\..*)?)$")
PRIVATE_KEY_PATTERN = re.compile(
    r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----\s*"
    r"[A-Za-z0-9+/=\r\n]{80,}\s*"
    r"-----END [A-Z0-9 ]*PRIVATE KEY-----"
)
SECRET_ASSIGNMENT_PATTERN = re.compile(
    r"\b(?:"
    + "|".join(re.escape(name) for name in SECRET_NAMES)
    + r")\b\s*(?:=|:)\s*(?:[\"']?)(?P<value>[^\s,\"'};]+)"
)


def is_example_file(path: Path) -> bool:
    return path.name in EXAMPLE_FILENAMES or path.name.endswith(".example")


def is_secret_file(path: Path) -> bool:
    return bool(SECRET_FILE_PATTERN.fullmatch(path.name)) and not is_example_file(path)


def is_local_generated_state(path: Path, root: Path) -> bool:
    try:
        relative_parts = path.relative_to(root).parts
    except ValueError:
        return False
    return len(relative_parts) >= 2 and relative_parts[0] == "supabase" and relative_parts[1] in {".temp", ".branches"}


def iter_repository_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRECTORIES for part in path.parts):
            continue
        if is_local_generated_state(path, root):
            continue
        if path.name in SKIP_FILENAMES or is_example_file(path):
            continue
        yield path


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root to scan",
    )
    args = parser.parse_args()
    root = args.root.resolve()

    findings: list[tuple[str, int | None, str]] = []
    checked_files = 0

    for path in root.rglob("*"):
        if path.is_file() and any(part in SKIP_DIRECTORIES for part in path.parts):
            continue
        if path.is_file() and is_secret_file(path) and not is_local_generated_state(path, root):
            findings.append((str(path.relative_to(root)), None, "secret-bearing local env file"))

    for path in iter_repository_files(root):
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        checked_files += 1

        private_key_match = PRIVATE_KEY_PATTERN.search(content)
        if private_key_match:
            findings.append(
                (
                    str(path.relative_to(root)),
                    line_number(content, private_key_match.start()),
                    "private key material",
                )
            )

        for match in SECRET_ASSIGNMENT_PATTERN.finditer(content):
            value = match.group("value").strip().lower()
            if (
                value in NON_SECRET_TYPE_VALUES
                or value in {"...", "example", "placeholder"}
                or value.startswith("your-")
                or value.startswith("<")
            ):
                continue
            findings.append(
                (
                    str(path.relative_to(root)),
                    line_number(content, match.start()),
                    "secret-like assignment",
                )
            )

    if findings:
        print(f"Secret scan failed with {len(findings)} finding(s):", file=sys.stderr)
        for path, line, reason in findings:
            location = f"{path}:{line}" if line is not None else path
            print(f"- {location}: {reason}", file=sys.stderr)
        return 1

    print(f"Secret scan passed ({checked_files} text files checked).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
