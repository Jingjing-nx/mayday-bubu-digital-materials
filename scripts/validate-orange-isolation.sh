#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TARGET="${1:-$ROOT}"

fail() {
  print -u2 "orange-project-isolation: FAIL: $1"
  exit 1
}

[[ -f "$ROOT/ORANGE-BUBU-PROJECT.txt" ]] || fail "project marker missing"

if [[ -d "$TARGET/pet" ]]; then
  [[ -f "$TARGET/pet/bubu-orange/pet.json" ]] || fail "orange pet missing"
  [[ -f "$TARGET/pet/bubu-orange/spritesheet.webp" \
     || -n "$(find "$TARGET/pet/bubu-orange" -maxdepth 1 -name 'spritesheet-win-*.webp' -print -quit)" ]] \
    || fail "orange atlas missing"
  [[ ! -e "$TARGET/pet/bubu-office" ]] || fail "blue pet directory present"
fi

if rg -n --hidden \
  --glob '!CHECKSUMS-SHA256.txt' \
  --glob '!ORANGE-BUBU-PROJECT.txt' \
  'bubu-office|custom:bubu-office|io\.github\.mayday-materials\.bubu-quota-panel|Mayday-Bubu-' \
  "$TARGET" >/dev/null; then
  fail "blue/generic project identifier leaked into target"
fi

print "orange-project-isolation: PASS target=$TARGET pet=bubu-orange-only"
