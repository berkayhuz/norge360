#!/usr/bin/env python3

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1] / "Norge360" / "Resources"
EXPECTED_LANGUAGES = {
    "en", "nb", "tr", "ar", "fa", "fr", "es", "de", "uk", "ru", "pl", "so", "ti", "am", "ur", "fa-AF"
}
STRING_LINE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
FORMAT = re.compile(r"%(?:\d+\$)?(?:@|d|lld)")


def parse_strings(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    errors: list[str] = []
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith(("/*", "//")):
            continue
        match = STRING_LINE.match(line)
        if not match:
            errors.append(f"{path}:{line_number}: invalid .strings syntax")
            continue
        key = match.group(1).replace(r'\"', '"').replace(r"\\", "\\")
        value = match.group(2).replace(r'\"', '"').replace(r"\\", "\\")
        if key in values:
            errors.append(f"{path}:{line_number}: duplicate key {key}")
        values[key] = value
    if errors:
        raise ValueError("\n".join(errors))
    return values


def source_keys(english: dict[str, str]) -> dict[str, str]:
    result = dict(english)
    for path in ROOT.glob("*.xcstrings"):
        data = json.loads(path.read_text())
        for key, entry in data.get("strings", {}).items():
            value = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
            if value is not None:
                result.setdefault(key, value)
    return result


def main() -> int:
    english = parse_strings(ROOT / "en.lproj" / "Localizable.strings")
    source = source_keys(english)
    available = {path.parent.name.removesuffix(".lproj") for path in ROOT.glob("*.lproj/Localizable.strings")}
    errors = []
    errors.extend(sorted(f"missing language bundle: {language}" for language in EXPECTED_LANGUAGES - available))
    errors.extend(sorted(f"unexpected language bundle: {language}" for language in available - EXPECTED_LANGUAGES))

    for language in sorted(EXPECTED_LANGUAGES):
        path = ROOT / f"{language}.lproj" / "Localizable.strings"
        values = parse_strings(path)
        missing = set(source) - set(values)
        extra = set(values) - set(source)
        errors.extend(f"{path}: missing key {key}" for key in sorted(missing))
        errors.extend(f"{path}: unexpected key {key}" for key in sorted(extra))
        for key in sorted(set(source) & set(values)):
            source_formats = FORMAT.findall(source[key])
            localized_formats = FORMAT.findall(values[key])
            if source_formats != localized_formats:
                errors.append(
                    f"{path}: format placeholders differ for {key}: "
                    f"{source_formats!r} != {localized_formats!r}"
                )

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Localization check passed: {len(EXPECTED_LANGUAGES)} languages, {len(source)} keys.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
