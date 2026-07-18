#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE_APP="$ROOT/build/卜卜额度面板.app"
DEST_APP="$HOME/Applications/卜卜额度面板.app"
LABEL="io.github.mayday-materials.bubu-quota-panel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/卜卜额度面板.log"
DOMAIN="gui/$(id -u)"

"$ROOT/scripts/build.sh" >/dev/null
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
rm -rf "$DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

/usr/bin/sed \
  -e "s|__EXECUTABLE__|$DEST_APP/Contents/MacOS/BubuQuotaPanel|g" \
  -e "s|__LOG_PATH__|$LOG|g" \
  "$ROOT/Resources/$LABEL.plist.in" > "$PLIST"

for EXISTING_PLIST in "$HOME/Library/LaunchAgents"/*.plist(N); do
  if /usr/bin/grep -q '卜卜额度面板.app/Contents/MacOS/BubuQuotaPanel' "$EXISTING_PLIST" 2>/dev/null; then
    /bin/launchctl bootout "$DOMAIN" "$EXISTING_PLIST" 2>/dev/null || true
    /bin/rm -f "$EXISTING_PLIST"
  fi
done
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
