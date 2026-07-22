#!/bin/zsh
emulate -L zsh
setopt ERR_EXIT PIPE_FAIL NO_UNSET

PETS_DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/pets"
APP_DEST="$HOME/Applications/卜卜额度面板.app"
LABEL="io.github.mayday-materials.bubu-quota-panel"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
DOMAIN="gui/$(id -u)"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/rm -f "$PLIST_DEST"
/bin/rm -rf "$APP_DEST" "$PETS_DEST_ROOT/bubu-office"

if [[ -f "$CONFIG" ]]; then
  TMP_CONFIG="$(/usr/bin/mktemp "$CONFIG.tmp.XXXXXX")"
  /usr/bin/awk '
    BEGIN { section = "" }
    /^[[:space:]]*\[[^]]+\]/ {
      section = ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*($|#)/) ? "desktop" : "other"
      print
      next
    }
    section == "desktop" && /^[[:space:]]*selected-avatar-id[[:space:]]*=[[:space:]]*"custom:bubu-office"/ { next }
    { print }
  ' "$CONFIG" > "$TMP_CONFIG"
  /bin/mv "$TMP_CONFIG" "$CONFIG"
fi

echo "卜卜宠物和额度面板已卸载。重新打开 Codex 后生效。"
if [[ -t 0 ]]; then
  echo ""
  read -k 1 "?按任意键关闭…"
  echo ""
fi
