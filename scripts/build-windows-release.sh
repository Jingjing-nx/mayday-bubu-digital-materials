#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="14"
CODEX_ONLY_RELEASE="false"
if [[ "${1:-}" == "--codex-only" ]]; then
  CODEX_ONLY_RELEASE="true"
fi

STAGE_ROOT="$ROOT/build/release"
FULL_STAGE="$STAGE_ROOT/卜卜-Windows"
CODEX_ONLY_STAGE="$STAGE_ROOT/卜卜-Windows-仅Codex额度"
FULL_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-$VERSION.zip"
CODEX_ONLY_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-Codex-Only-$VERSION.zip"
ATLAS_NAME="spritesheet-win-$VERSION.webp"

command -v jq >/dev/null || {
  print -u2 "缺少 jq，无法生成 Windows 发布包。"
  exit 1
}

stage_package() {
  local stage="$1"
  local codex_only="$2"
  local pet_dir="$stage/pet/bubu-office"
  local temporary_json

  /bin/rm -rf "$stage"
  mkdir -p "$stage"

  /usr/bin/ditto "$ROOT/shared/pet" "$stage/pet"
  /usr/bin/ditto "$ROOT/shared/preview" "$stage/preview"
  /usr/bin/ditto "$ROOT/windows/BubuQuotaPanel" "$stage/windows"
  /usr/bin/ditto "$ROOT/windows/package" "$stage"
  /bin/cp "$ROOT/windows/README.md" "$stage/README.md"
  /bin/cp "$ROOT/windows/VERSION.txt" "$stage/VERSION.txt"
  /bin/cp "$ROOT/LICENSE" "$ROOT/ASSET-NOTICE.md" "$ROOT/PRIVACY.md" "$stage/"
  if [[ "$codex_only" == "true" ]]; then
    /bin/cp "$ROOT/windows/CODEX-ONLY.txt" "$stage/CODEX-ONLY.txt"
  fi

  /bin/mv "$pet_dir/spritesheet.webp" "$pet_dir/$ATLAS_NAME"
  temporary_json="$pet_dir/pet.json.tmp"
  jq --arg atlas "$ATLAS_NAME" '.spritesheetPath = $atlas' \
    "$pet_dir/pet.json" > "$temporary_json"
  /bin/mv "$temporary_json" "$pet_dir/pet.json"

  if [[ -f "$pet_dir/validation.json" ]]; then
    temporary_json="$pet_dir/validation.json.tmp"
    jq --arg atlas "$ATLAS_NAME" '.file = $atlas' \
      "$pet_dir/validation.json" > "$temporary_json"
    /bin/mv "$temporary_json" "$pet_dir/validation.json"
  fi

  (
    cd "$stage"
    export LC_ALL=C
    find . -type f ! -name CHECKSUMS-SHA256.txt -print | sort |
      while IFS= read -r file; do /usr/bin/shasum -a 256 "$file"; done > CHECKSUMS-SHA256.txt
  )
}

/bin/rm -f "$CODEX_ONLY_OUT"
if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /bin/rm -f "$FULL_OUT"
  stage_package "$FULL_STAGE" false
fi
stage_package "$CODEX_ONLY_STAGE" true

if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$FULL_STAGE" "$FULL_OUT"
  print "$FULL_OUT"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CODEX_ONLY_STAGE" "$CODEX_ONLY_OUT"
print "$CODEX_ONLY_OUT"
