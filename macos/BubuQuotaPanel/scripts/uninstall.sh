#!/bin/zsh
set -euo pipefail

DOMAIN="gui/$(id -u)"
LABEL="io.github.mayday-materials.orange-bubu-quota-panel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_LABEL="io.github.mayday-materials.bubu-quota-panel"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_RESTORE_MARKER="$HOME/Library/Caches/io.github.mayday-materials.orange-bubu-quota-panel/restore-legacy-panel-on-uninstall"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/Applications/橙色卜卜额度面板.app"

if [[ -f "$LEGACY_RESTORE_MARKER" ]]; then
  /bin/launchctl enable "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  if [[ -f "$LEGACY_PLIST" ]]; then
    /bin/launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
    /bin/launchctl bootstrap "$DOMAIN" "$LEGACY_PLIST" 2>/dev/null || true
    /bin/launchctl kickstart -k "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  fi
  /bin/rm -f "$LEGACY_RESTORE_MARKER"
fi
echo "橙色卜卜额度面板已卸载；其他宠物项目未改动"
