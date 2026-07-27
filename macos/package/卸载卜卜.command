#!/bin/zsh
emulate -L zsh
setopt ERR_EXIT PIPE_FAIL NO_UNSET

PETS_DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/pets"
APP_DEST="$HOME/Applications/橙色卜卜额度面板.app"
LABEL="io.github.mayday-materials.orange-bubu-quota-panel"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_LABEL="io.github.mayday-materials.bubu-quota-panel"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_RESTORE_MARKER="$HOME/Library/Caches/io.github.mayday-materials.orange-bubu-quota-panel/restore-legacy-panel-on-uninstall"
CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
DOMAIN="gui/$(id -u)"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/rm -f "$PLIST_DEST"
/bin/rm -rf "$APP_DEST" "$PETS_DEST_ROOT/bubu-orange"

if [[ -f "$LEGACY_RESTORE_MARKER" ]]; then
  /bin/launchctl enable "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  if [[ -f "$LEGACY_PLIST" ]]; then
    /bin/launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
    /bin/launchctl bootstrap "$DOMAIN" "$LEGACY_PLIST" 2>/dev/null || true
    /bin/launchctl kickstart -k "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  fi
  /bin/rm -f "$LEGACY_RESTORE_MARKER"
fi

if [[ -f "$CONFIG" ]]; then
  TMP_CONFIG="$(/usr/bin/mktemp "$CONFIG.tmp.XXXXXX")"
  /usr/bin/awk '
    BEGIN { section = "" }
    /^[[:space:]]*\[[^]]+\]/ {
      section = ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*($|#)/) ? "desktop" : "other"
      print
      next
    }
    section == "desktop" && /^[[:space:]]*selected-avatar-id[[:space:]]*=[[:space:]]*"custom:bubu-orange"/ { next }
    { print }
  ' "$CONFIG" > "$TMP_CONFIG"
  /bin/mv "$TMP_CONFIG" "$CONFIG"
fi

echo "橙色卜卜宠物和专属额度面板已卸载；其他宠物项目未改动。重新打开 Codex 后生效。"
if [[ -t 0 ]]; then
  echo ""
  read -k 1 "?按任意键关闭…"
  echo ""
fi
