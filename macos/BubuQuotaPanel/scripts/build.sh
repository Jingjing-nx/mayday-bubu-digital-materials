#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PROJECT_ROOT="${ROOT:h:h}"
APP="$ROOT/build/橙色卜卜额度面板.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

# Fail closed if an approved pet, panel, lightstick, or airplane texture was
# replaced without deliberately updating the Orange Bubu geometry contract.
(
  cd "$PROJECT_ROOT"
  /usr/bin/shasum -a 256 -c \
    "shared/pet/bubu-orange/qa/runtime-assets.sha256" >/dev/null
)

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/quota-panel-background.png" "$RESOURCES/quota-panel-background.png"
cp "$ROOT/Resources/task-completed-icon.png" "$RESOURCES/task-completed-icon.png"
cp "$ROOT/Resources/task-running-icon.png" "$RESOURCES/task-running-icon.png"
cp "$ROOT/Resources/task-running-badge.gif" "$RESOURCES/task-running-badge.gif"
cp "$ROOT/Resources/task-waiting-icon.png" "$RESOURCES/task-waiting-icon.png"
cp "$ROOT/Resources/task-failed-icon.png" "$RESOURCES/task-failed-icon.png"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
mkdir -p "$RESOURCES/Lightstick"
for asset in lightstick-unlit.png lightstick-tube-emission.png lightstick-glow.png lightstick-specular.png lightstick-full-lit.png lightstick-tube-mask.png lightstick-layers.json; do
  cp "$ROOT/../../shared/pet/bubu-orange/accessories/lightstick/runtime/layers/$asset" \
    "$RESOURCES/Lightstick/$asset"
done
mkdir -p "$RESOURCES/Airplane"
cp "$ROOT/Resources/Airplane/quota-airplane-material.png" \
  "$RESOURCES/Airplane/quota-airplane-material.png"
cp "$ROOT/Resources/Airplane/quota-airplane-material.json" \
  "$RESOURCES/Airplane/quota-airplane-material.json"
cp "$ROOT/Resources/Airplane/quota-airplane-flight-material.png" \
  "$RESOURCES/Airplane/quota-airplane-flight-material.png"
cp "$ROOT/Resources/Airplane/quota-airplane-flight-material.json" \
  "$RESOURCES/Airplane/quota-airplane-flight-material.json"

for ARCH in arm64 x86_64; do
  /usr/bin/swiftc \
    -swift-version 5 \
    -O \
    -target "$ARCH-apple-macos12.3" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework CoreGraphics \
    "$ROOT/Sources/BubuQuotaPanel/main.swift" \
    -o "$TMP_DIR/OrangeBubuQuotaPanel-$ARCH"
done

/usr/bin/lipo -create \
  "$TMP_DIR/OrangeBubuQuotaPanel-arm64" \
  "$TMP_DIR/OrangeBubuQuotaPanel-x86_64" \
  -output "$MACOS/OrangeBubuQuotaPanel"

"$MACOS/OrangeBubuQuotaPanel" --self-test-runtime-geometry >/dev/null
"$MACOS/OrangeBubuQuotaPanel" --self-test-quota-lightstick >/dev/null

/usr/bin/codesign --force --deep --sign - "$APP"
echo "$APP"
