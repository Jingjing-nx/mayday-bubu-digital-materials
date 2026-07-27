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
  'bubu-office|custom:bubu-office|Mayday-Bubu-' \
  "$TARGET" >/dev/null; then
  fail "blue/generic project identifier leaked into target"
fi

# The two macOS lifecycle commands may name the legacy service solely to pause
# and later restore it. No other Orange Bubu file may depend on that identifier.
if rg -n --hidden \
  --glob '!CHECKSUMS-SHA256.txt' \
  --glob '!ORANGE-BUBU-PROJECT.txt' \
  --glob '!安装卜卜-macOS.command' \
  --glob '!卸载卜卜-macOS.command' \
  'io\.github\.mayday-materials\.bubu-quota-panel' \
  "$TARGET" >/dev/null; then
  fail "legacy panel identifier escaped the approved macOS handoff commands"
fi

MAC_INSTALLER="$TARGET/安装卜卜-macOS.command"
MAC_UNINSTALLER="$TARGET/卸载卜卜-macOS.command"
if [[ -f "$MAC_INSTALLER" || -f "$MAC_UNINSTALLER" ]]; then
  [[ -f "$MAC_INSTALLER" && -f "$MAC_UNINSTALLER" ]] \
    || fail "macOS panel handoff command pair is incomplete"
  /usr/bin/grep -Fq 'LEGACY_LABEL="io.github.mayday-materials.bubu-quota-panel"' "$MAC_INSTALLER" \
    || fail "macOS installer legacy handoff label missing"
  /usr/bin/grep -Fq 'launchctl disable "$DOMAIN/$LEGACY_LABEL"' "$MAC_INSTALLER" \
    || fail "macOS installer does not pause the legacy panel"
  /usr/bin/grep -Fq 'launchctl enable "$DOMAIN/$LEGACY_LABEL"' "$MAC_UNINSTALLER" \
    || fail "macOS uninstaller does not restore the legacy panel"
fi

print "orange-project-isolation: PASS target=$TARGET pet=bubu-orange-only"
