#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="46"
CODEX_ONLY_RELEASE="false"
if [[ "${1:-}" == "--codex-only" ]]; then
  CODEX_ONLY_RELEASE="true"
fi

STAGE_ROOT="$ROOT/build/release"
FULL_STAGE="$STAGE_ROOT/卜卜-Windows"
FULL_NO_SINGING_STAGE="$STAGE_ROOT/卜卜-Windows-无唱歌音效"
CODEX_ONLY_STAGE="$STAGE_ROOT/卜卜-Windows-仅Codex额度"
CODEX_ONLY_NO_SINGING_STAGE="$STAGE_ROOT/卜卜-Windows-仅Codex额度-无唱歌音效"
FULL_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-$VERSION.zip"
FULL_NO_SINGING_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-No-Singing-$VERSION.zip"
CODEX_ONLY_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-Codex-Only-$VERSION.zip"
CODEX_ONLY_NO_SINGING_OUT="$ROOT/dist/Mayday-Bubu-Windows-10-11-Codex-Only-No-Singing-$VERSION.zip"
ATLAS_NAME="spritesheet-win-$VERSION.webp"

command -v jq >/dev/null || {
  print -u2 "缺少 jq，无法生成 Windows 发布包。"
  exit 1
}

stage_package() {
  local stage="$1"
  local codex_only="$2"
  local include_singing_audio="$3"
  local pet_dir
  local temporary_json

  /bin/rm -rf "$stage"
  mkdir -p "$stage"

  /usr/bin/ditto "$ROOT/shared/pet/bubu-office" "$stage/pet/bubu-office"
  mkdir -p "$stage/preview"
  for preview in \
    Codex额度面板.png 任务状态图标总览.png 卜卜动作总览.png \
    右拖电吉他.gif 左拖唱歌.gif 悬停喝咖啡.gif 默认办公.gif \
    blue-bubu-static.png; do
    /bin/cp "$ROOT/shared/preview/$preview" "$stage/preview/$preview"
  done
  /usr/bin/ditto "$ROOT/windows/BubuQuotaPanel" "$stage/windows"
  if [[ "$include_singing_audio" == "true" ]]; then
    /bin/cp "$ROOT/shared/audio/bubu-left-drag-song.mp3" \
      "$stage/windows/bubu-left-drag-song.mp3"
  else
    /bin/cp "$ROOT/NO-SINGING-AUDIO.txt" "$stage/NO-SINGING-AUDIO.txt"
  fi
  /usr/bin/ditto "$ROOT/windows/package" "$stage"
  /bin/cp "$ROOT/windows/README.md" "$stage/README.md"
  /bin/cp "$ROOT/windows/VERSION.txt" "$stage/VERSION.txt"
  /bin/cp "$ROOT/LICENSE" "$ROOT/ASSET-NOTICE.md" "$ROOT/PRIVACY.md" \
    "$ROOT/BLUE-EDITION.txt" "$stage/"
  if [[ "$codex_only" == "true" ]]; then
    /bin/cp "$ROOT/windows/CODEX-ONLY.txt" "$stage/CODEX-ONLY.txt"
  fi

  for pet_dir in "$stage"/pet/*(N/); do
    [[ -f "$pet_dir/spritesheet.webp" && -f "$pet_dir/pet.json" ]] || continue
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
  done

  (
    cd "$stage"
    export LC_ALL=C
    find . -type f ! -name CHECKSUMS-SHA256.txt -print | sort |
      while IFS= read -r file; do /usr/bin/shasum -a 256 "$file"; done > CHECKSUMS-SHA256.txt
  )
}

/bin/rm -f "$CODEX_ONLY_OUT" "$CODEX_ONLY_NO_SINGING_OUT"
if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /bin/rm -f "$FULL_OUT" "$FULL_NO_SINGING_OUT"
  stage_package "$FULL_STAGE" false true
  stage_package "$FULL_NO_SINGING_STAGE" false false
fi
stage_package "$CODEX_ONLY_STAGE" true true
stage_package "$CODEX_ONLY_NO_SINGING_STAGE" true false

if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$FULL_STAGE" "$FULL_OUT"
  /usr/bin/ditto -c -k --norsrc --keepParent "$FULL_NO_SINGING_STAGE" "$FULL_NO_SINGING_OUT"
  print "$FULL_OUT"
  print "$FULL_NO_SINGING_OUT"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CODEX_ONLY_STAGE" "$CODEX_ONLY_OUT"
/usr/bin/ditto -c -k --norsrc --keepParent "$CODEX_ONLY_NO_SINGING_STAGE" "$CODEX_ONLY_NO_SINGING_OUT"
print "$CODEX_ONLY_OUT"
print "$CODEX_ONLY_NO_SINGING_OUT"
