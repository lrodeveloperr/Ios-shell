#!/usr/bin/env bash
set -euo pipefail

fail() { echo "COMMERCE BRANDING CHECK FAILED: $*" >&2; exit 1; }

commerce_files=()
while IFS= read -r path; do commerce_files+=("$path"); done < <(
  find Shell -type f -name '*.swift' \
    \( -iname '*paywall*' -o -iname '*purchase*' -o -iname '*subscription*' \
       -o -iname '*winback*' -o -iname '*restore*' -o -iname '*commerce*' \
       -o -iname '*upgrade*' -o -iname '*offer*' \) | sort
)

(( ${#commerce_files[@]} > 0 )) || fail "No commerce surfaces were found"

command -v python3 >/dev/null 2>&1 || fail "python3 is required; the check must never be skipped"

# SF Symbols are allowed. Named image assets and app-brand references are not.
# Python's regex engine supports the lookahead on every runner, unlike BSD grep.
python3 - "${commerce_files[@]}" <<'PY' || fail "A commerce surface references an app image, icon, logo, name, or brand asset"
import re, sys
pattern = re.compile(
    r'Image\s*\(\s*(?!systemName:)|UIImage\s*\(\s*named:|ImageResource\.'
    r'|ShellConfiguration\.appName|\.appIcon\b|Asset\.[A-Za-z0-9_]*(Logo|Icon|Brand)'
)
found = False
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as source:
        for number, line in enumerate(source, 1):
            if pattern.search(line):
                print(f"{path}:{number}:{line.rstrip()}")
                found = True
sys.exit(1 if found else 0)
PY

echo "Commerce surfaces contain no app logo/icon/brand asset references."
