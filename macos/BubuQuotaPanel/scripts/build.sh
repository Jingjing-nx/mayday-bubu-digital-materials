#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/卜卜额度面板.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/quota-panel-background.png" "$RESOURCES/quota-panel-background.png"

for ARCH in arm64 x86_64; do
  /usr/bin/swiftc \
    -swift-version 5 \
    -O \
    -target "$ARCH-apple-macos13.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework CoreGraphics \
    "$ROOT/Sources/BubuQuotaPanel/main.swift" \
    -o "$TMP_DIR/BubuQuotaPanel-$ARCH"
done

/usr/bin/lipo -create \
  "$TMP_DIR/BubuQuotaPanel-arm64" \
  "$TMP_DIR/BubuQuotaPanel-x86_64" \
  -output "$MACOS/BubuQuotaPanel"

/usr/bin/codesign --force --deep --sign - "$APP"
echo "$APP"
