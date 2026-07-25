#!/bin/zsh
set -euo pipefail

DOMAIN="gui/$(id -u)"
LABEL="io.github.mayday-materials.orange-bubu-quota-panel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/Applications/橙色卜卜额度面板.app"
echo "橙色卜卜额度面板已卸载；其他宠物项目未改动"
