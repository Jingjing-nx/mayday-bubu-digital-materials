#!/bin/zsh
emulate -L zsh
setopt PIPE_FAIL

PET_DIR="${CODEX_HOME:-$HOME/.codex}/pets/bubu-office"
APP="$HOME/Applications/卜卜额度面板.app"
BIN="$APP/Contents/MacOS/BubuQuotaPanel"
LABEL="io.github.mayday-materials.bubu-quota-panel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
FAILED=0

check() {
  if eval "$2"; then
    echo "✓ $1"
  else
    echo "✗ $1"
    FAILED=1
  fi
}

echo "卜卜安装检查"
echo "────────────"
check "宠物文件完整" '[[ -f "$PET_DIR/pet.json" && -f "$PET_DIR/spritesheet.webp" ]]'
check "额度面板已安装" '[[ -x "$BIN" ]]'
check "额度面板支持当前 Mac" '[[ -x "$BIN" ]] && /usr/bin/lipo "$BIN" -verify_arch "$(/usr/bin/uname -m)"'
check "额度面板签名正常" '[[ -d "$APP" ]] && /usr/bin/codesign --verify --deep --strict "$APP"'
check "登录启动项存在" '[[ -f "$PLIST" ]]'
check "额度面板正在运行" '/bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1'

if [[ -x "$BIN" ]]; then
  echo ""
  echo "Codex 额度读取："
  "$BIN" --print-quota || FAILED=1
  echo "BTC 价格读取："
  "$BIN" --print-btc || FAILED=1
  echo "ETH 价格读取："
  "$BIN" --print-eth || FAILED=1
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "全部检查通过。"
else
  echo "有项目未通过：请先确认 Codex 已安装并已登录，再重新运行“安装卜卜-macOS.command”。"
  echo "日志：$HOME/Library/Logs/卜卜额度面板.log"
fi

if [[ -t 0 ]]; then
  echo ""
  read -k 1 "?按任意键关闭…"
  echo ""
fi
exit "$FAILED"
