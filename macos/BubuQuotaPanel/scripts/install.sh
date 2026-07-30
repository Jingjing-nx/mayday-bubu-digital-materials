#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE_APP="$ROOT/build/橙色卜卜额度面板.app"
DEST_APP="$HOME/Applications/橙色卜卜额度面板.app"
LABEL="io.github.mayday-materials.orange-bubu-quota-panel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/橙色卜卜额度面板.log"
HEALTH="$HOME/Library/Caches/io.github.mayday-materials.orange-bubu-quota-panel/panel-health.json"
LEGACY_LABEL="io.github.mayday-materials.bubu-quota-panel"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_RESTORE_MARKER="${HEALTH:h}/restore-legacy-panel-on-uninstall"
STATE="${CODEX_HOME:-$HOME/.codex}/.codex-global-state.json"
DOMAIN="gui/$(id -u)"
VOCABULARY_SOURCE="$ROOT/../../shared/pet/bubu-orange/vocabulary-web3-3000.json"
VOCABULARY_ROOT="$HOME/Library/Application Support/$LABEL"
VOCABULARY_DEST="$VOCABULARY_ROOT/vocabulary.json"

legacy_panel_is_disabled() {
  /bin/launchctl print-disabled "$DOMAIN" 2>/dev/null \
    | /usr/bin/grep -Fq '"'"$LEGACY_LABEL"'" => true'
}

pause_legacy_panel() {
  if [[ ! -f "$LEGACY_PLIST" ]] \
    && ! /bin/launchctl print "$DOMAIN/$LEGACY_LABEL" >/dev/null 2>&1; then
    return
  fi

  if ! legacy_panel_is_disabled; then
    /usr/bin/touch "$LEGACY_RESTORE_MARKER"
  fi
  /bin/launchctl disable "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  /bin/launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
}

"$ROOT/scripts/build.sh" >/dev/null
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "${HEALTH:h}"
if [[ -f "$VOCABULARY_SOURCE" && ! -s "$VOCABULARY_DEST" ]]; then
  mkdir -p "$VOCABULARY_ROOT"
  /bin/cp "$VOCABULARY_SOURCE" "$VOCABULARY_DEST"
fi
rm -rf "$DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

/usr/bin/sed \
  -e "s|__EXECUTABLE__|$DEST_APP/Contents/MacOS/OrangeBubuQuotaPanel|g" \
  -e "s|__HEALTH_PATH__|$HEALTH|g" \
  -e "s|__STATE_PATH__|$STATE|g" \
  -e "s|__LOG_PATH__|$LOG|g" \
  "$ROOT/Resources/$LABEL.plist.in" > "$PLIST"

pause_legacy_panel
/bin/launchctl enable "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
for _ in {1..20}; do
  /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
  /bin/sleep 0.1
done
if ! /bin/launchctl bootstrap "$DOMAIN" "$PLIST"; then
  /bin/sleep 1
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST"
fi
/bin/launchctl kickstart -k "$DOMAIN/$LABEL"
echo "$DEST_APP"
