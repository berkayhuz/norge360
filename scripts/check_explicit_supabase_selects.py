#!/usr/bin/env python3
"""Reject implicit Supabase projections in first-party client code."""

from pathlib import Path
import re
import sys


ROOTS = (Path("Norge360"), Path("workers/moderation/src"))
IMPLICIT_SELECT = re.compile(r"\.select\(\s*\)")


def main() -> int:
    violations: list[str] = []
    for root in ROOTS:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix not in {".swift", ".ts"}:
                continue
            text = path.read_text(encoding="utf-8")
            for match in IMPLICIT_SELECT.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                violations.append(f"{path}:{line}: use an explicit Supabase select projection")

    if violations:
        print("Implicit Supabase projections found:")
        print("\n".join(violations))
        return 1

    print("Explicit Supabase select contract check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
