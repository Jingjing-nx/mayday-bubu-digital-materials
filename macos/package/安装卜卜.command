#!/bin/zsh
emulate -L zsh
setopt ERR_EXIT PIPE_FAIL NO_UNSET

ROOT="${0:A:h}"
PET_ID="bubu-office"
PET_SOURCE="$ROOT/pet/$PET_ID"
PET_DEST="${CODEX_HOME:-$HOME/.codex}/pets/$PET_ID"
APP_SOURCE="$ROOT/quota-panel/卜卜额度面板.app"
APP_DEST="$HOME/Applications/卜卜额度面板.app"
APP_BINARY="$APP_DEST/Contents/MacOS/BubuQuotaPanel"
LABEL="io.github.mayday-materials.bubu-quota-panel"
PLIST_SOURCE="$ROOT/quota-panel/$LABEL.plist.in"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/卜卜额度面板.log"
HEALTH_DIR="$HOME/Library/Caches/io.github.mayday-materials.bubu-quota-panel"
HEALTH_PATH="$HEALTH_DIR/panel-health.json"
CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
DOMAIN="gui/$(id -u)"
PANEL_VERSION="1.0.5"
EXPECTED_ATLAS_SHA256="df3c6f95784ae109f12df57c438afaa88c3e4a786145066c3d93fbf32000b3a0"

pause_before_exit() {
  if [[ -t 0 ]]; then
    echo ""
    read -k 1 "?按任意键关闭…"
    echo ""
  fi
}

fail() {
  echo ""
  echo "安装失败：$1"
  if [[ -s "$LOG_PATH" ]]; then
    echo ""
    echo "面板日志最后 12 行："
    /usr/bin/tail -n 12 "$LOG_PATH" 2>/dev/null || true
  fi
  pause_before_exit
  exit 1
}

panel_service_has_pid() {
  /bin/launchctl print "$DOMAIN/$LABEL" 2>/dev/null \
    | /usr/bin/grep -Eq '^[[:space:]]*pid = [0-9]+'
}

panel_health_is_current() {
  [[ -s "$HEALTH_PATH" ]] \
    && /usr/bin/grep -q '"version":"'"$PANEL_VERSION"'"' "$HEALTH_PATH" 2>/dev/null
}

wait_for_panel_health() {
  local attempt
  for attempt in {1..80}; do
    if panel_service_has_pid && panel_health_is_current; then
      return 0
    fi
    /bin/sleep 0.1
  done
  return 1
}

select_bubu_in_codex() {
  mkdir -p "${CONFIG:h}"
  [[ -f "$CONFIG" ]] || /usr/bin/touch "$CONFIG"
  /bin/cp -p "$CONFIG" "$CONFIG.bubu-backup-$(date +%Y%m%d-%H%M%S)"

  local tmp_config
  tmp_config="$(/usr/bin/mktemp "$CONFIG.tmp.XXXXXX")"
  /usr/bin/awk '
    BEGIN {
      section = ""
      desktop_seen = 0
      desktop_has_value = 0
      value = "selected-avatar-id = \"custom:bubu-office\""
    }
    function add_desktop_value() {
      if (!desktop_has_value) {
        print value
        desktop_has_value = 1
      }
    }
    /^[[:space:]]*\[[^]]+\]/ {
      if (section == "desktop") add_desktop_value()
      if ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*($|#)/) {
        section = "desktop"
        desktop_seen = 1
        desktop_has_value = 0
      } else {
        section = "other"
      }
      print
      next
    }
    {
      if (section == "" && $0 ~ /^[[:space:]]*selected-avatar-id[[:space:]]*=/) next
      if (section == "desktop" && $0 ~ /^[[:space:]]*selected-avatar-id[[:space:]]*=/) {
        if (!desktop_has_value) print value
        desktop_has_value = 1
        next
      }
      print
    }
    END {
      if (section == "desktop") add_desktop_value()
      if (!desktop_seen) {
        print ""
        print "[desktop]"
        print value
      }
    }
  ' "$CONFIG" > "$tmp_config"
  /bin/mv "$tmp_config" "$CONFIG"
}

echo "正在安装卜卜（macOS Universal 开源版 $PANEL_VERSION）…"

MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
MACOS_REMAINDER="${MACOS_VERSION#*.}"
MACOS_MINOR="${MACOS_REMAINDER%%.*}"
if (( MACOS_MAJOR < 12 || (MACOS_MAJOR == 12 && MACOS_MINOR < 3) )); then
  fail "需要 macOS 12.3 或更高版本，当前版本为 $MACOS_VERSION。"
fi
[[ -f "$PET_SOURCE/pet.json" && -f "$PET_SOURCE/spritesheet.webp" ]] \
  || fail "宠物文件不完整，请重新解压整个分享包。"
[[ -d "$APP_SOURCE" && -f "$PLIST_SOURCE" ]] \
  || fail "额度面板文件不完整，请重新解压整个分享包。"

ACTUAL_ATLAS_SHA256="$(/usr/bin/shasum -a 256 "$PET_SOURCE/spritesheet.webp" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL_ATLAS_SHA256" == "$EXPECTED_ATLAS_SHA256" ]] \
  || fail "宠物图集校验失败，请重新下载分享包。"

ARCH="$(/usr/bin/uname -m)"
[[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] \
  || fail "不支持当前 Mac 架构：$ARCH。"
/usr/bin/lipo "$APP_SOURCE/Contents/MacOS/BubuQuotaPanel" -verify_arch "$ARCH" \
  || fail "额度面板不包含 $ARCH 架构。"
/usr/bin/codesign --verify --deep --strict "$APP_SOURCE" \
  || fail "额度面板签名校验失败，请重新下载分享包。"

mkdir -p "${PET_DEST:h}" "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$HEALTH_DIR"

if [[ -e "$PET_DEST" ]]; then
  PET_BACKUP="$PET_DEST.backup-$(date +%Y%m%d-%H%M%S)"
  /bin/mv "$PET_DEST" "$PET_BACKUP"
  echo "已有同名宠物已备份到：$PET_BACKUP"
fi
/usr/bin/ditto "$PET_SOURCE" "$PET_DEST"

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

/bin/rm -rf "$APP_DEST"
/usr/bin/ditto "$APP_SOURCE" "$APP_DEST"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP_DEST" >/dev/null
/bin/rm -f "$HEALTH_PATH"

/bin/cp "$PLIST_SOURCE" "$PLIST_DEST"
/usr/bin/plutil -replace ProgramArguments.0 -string "$APP_BINARY" "$PLIST_DEST"
/usr/bin/plutil -replace EnvironmentVariables.BUBU_PANEL_HEALTH_FILE -string "$HEALTH_PATH" "$PLIST_DEST"
/usr/bin/plutil -replace StandardErrorPath -string "$LOG_PATH" "$PLIST_DEST"
/usr/bin/plutil -replace StandardOutPath -string "$LOG_PATH" "$PLIST_DEST"
/usr/bin/plutil -lint "$PLIST_DEST" >/dev/null

if ! /bin/launchctl bootstrap "$DOMAIN" "$PLIST_DEST"; then
  /bin/sleep 1
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST_DEST" \
    || fail "无法注册额度面板登录启动项。"
fi
/bin/launchctl kickstart -k "$DOMAIN/$LABEL" \
  || fail "额度面板启动请求失败。"

if ! wait_for_panel_health; then
  echo "首次启动未通过自检，正在自动重试…"
  /bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  /bin/sleep 0.5
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST_DEST" \
    || fail "额度面板重试注册失败。"
  /bin/launchctl kickstart -k "$DOMAIN/$LABEL" \
    || fail "额度面板重试启动失败。"
  wait_for_panel_health \
    || fail "额度面板进程没有保持运行。请把上面的日志发到群里。"
fi

select_bubu_in_codex

echo ""
echo "安装完成："
echo "  ✓ 卜卜宠物"
echo "  ✓ Codex 额度 + BTC/ETH 面板"
echo "  ✓ 自动选中卜卜"
echo "  ✓ 随登录自动启动"
echo ""
echo "请退出并重新打开 Codex。额度读取朋友自己的本机账号，不需要 API Key。"
pause_before_exit
