#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="1.0.1"
STAGE_ROOT="$ROOT/build/release"
STAGE="$STAGE_ROOT/卜卜-macOS"
OUT="$ROOT/dist/Mayday-Bubu-macOS-Universal-v$VERSION.zip"
APP_PROJECT="$ROOT/macos/BubuQuotaPanel"
LABEL="io.github.mayday-materials.bubu-quota-panel"

"$APP_PROJECT/scripts/build.sh" >/dev/null
/bin/rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/pet" "$STAGE/quota-panel" "$STAGE/preview"

/usr/bin/ditto "$ROOT/shared/pet/bubu-office" "$STAGE/pet/bubu-office"
/usr/bin/ditto "$ROOT/shared/preview" "$STAGE/preview"
/usr/bin/ditto "$APP_PROJECT/build/卜卜额度面板.app" "$STAGE/quota-panel/卜卜额度面板.app"
/bin/cp "$APP_PROJECT/Resources/$LABEL.plist.in" "$STAGE/quota-panel/$LABEL.plist.in"
/bin/cp "$ROOT/macos/README.md" "$STAGE/README.md"
/bin/cp "$ROOT/macos/VERSION.txt" "$STAGE/VERSION.txt"
/bin/cp "$ROOT/LICENSE" "$ROOT/ASSET-NOTICE.md" "$ROOT/PRIVACY.md" "$STAGE/"
/bin/cp "$ROOT/macos/package/安装卜卜.command" "$STAGE/安装卜卜-macOS.command"
/bin/cp "$ROOT/macos/package/卸载卜卜.command" "$STAGE/卸载卜卜-macOS.command"
/bin/cp "$ROOT/macos/package/检查卜卜.command" "$STAGE/检查卜卜-macOS.command"
/bin/chmod +x "$STAGE"/*.command

(
  cd "$STAGE"
  LC_ALL=C find . -type f ! -name CHECKSUMS-SHA256.txt -print | LC_ALL=C sort |
    while IFS= read -r file; do /usr/bin/shasum -a 256 "$file"; done > CHECKSUMS-SHA256.txt
)

/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE" "$OUT"
echo "$OUT"
