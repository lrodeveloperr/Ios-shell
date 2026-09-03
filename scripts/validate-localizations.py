#!/usr/bin/env python3
"""Reject selectable locales without complete matching string catalogs."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "Shell/App/ShellConfiguration.swift"
RESOURCES = ROOT / "Shell/Resources"

configured = re.findall(r'\.init\(id: "([^"]+)", displayName:', CONFIG.read_text())
locales = [locale for locale in configured if locale != "system"]

def catalog_keys(path: Path) -> list[str]:
    return re.findall(r'^\s*"((?:\\.|[^"])*)"\s*=', path.read_text(), re.MULTILINE)

english_path = RESOURCES / "en.lproj/Localizable.strings"
if not english_path.is_file():
    sys.exit("LOCALIZATION FAILED: missing English source catalog")
english_list = catalog_keys(english_path)
if len(english_list) != len(set(english_list)):
    sys.exit("LOCALIZATION FAILED: duplicate keys in English source catalog")
english = set(english_list)

for locale in locales:
    path = RESOURCES / f"{locale}.lproj/Localizable.strings"
    if not path.is_file():
        sys.exit(f"LOCALIZATION FAILED: selectable locale {locale} has no matching catalog")
    current_list = catalog_keys(path)
    if len(current_list) != len(set(current_list)):
        sys.exit(f"LOCALIZATION FAILED: duplicate keys in {locale} catalog")
    current = set(current_list)
    missing = sorted(english - current)
    extra = sorted(current - english)
    if missing or extra:
        sys.exit(f"LOCALIZATION FAILED: {locale} key mismatch; missing={missing[:8]} extra={extra[:8]}")

print(f"Localization validation passed ({len(locales)} selectable locale catalogs, {len(english)} keys).")
