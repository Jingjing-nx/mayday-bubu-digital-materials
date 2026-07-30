#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="29"
CODEX_ONLY_RELEASE="false"
WEB3_VOCABULARY_RELEASE="false"
if [[ "${1:-}" == "--codex-only" ]]; then
  CODEX_ONLY_RELEASE="true"
elif [[ "${1:-}" == "--web3-vocabulary" ]]; then
  WEB3_VOCABULARY_RELEASE="true"
elif [[ -n "${1:-}" ]]; then
  print -u2 "用法：$0 [--codex-only|--web3-vocabulary]"
  exit 1
fi

STAGE_ROOT="$ROOT/build/release"
FULL_STAGE="$STAGE_ROOT/橙色卜卜-Windows"
CODEX_ONLY_STAGE="$STAGE_ROOT/橙色卜卜-Windows-仅Codex额度"
WEB3_VOCABULARY_STAGE="$STAGE_ROOT/橙色卜卜-Windows-背Web3单词"
FULL_OUT="$ROOT/dist/Orange-Bubu-Windows-10-11-$VERSION.zip"
CODEX_ONLY_OUT="$ROOT/dist/Orange-Bubu-Windows-10-11-Codex-Only-$VERSION.zip"
WEB3_VOCABULARY_OUT="$ROOT/dist/Orange-Bubu-Web3-Vocabulary-Windows-10-11-30.zip"
ATLAS_NAME="spritesheet-win-$VERSION.webp"

command -v jq >/dev/null || {
  print -u2 "缺少 jq，无法生成 Windows 发布包。"
  exit 1
}

stage_package() {
  local stage="$1"
  local codex_only="$2"
  local web3_vocabulary="$3"
  local pet_dir
  local temporary_json

  /bin/rm -rf "$stage"
  mkdir -p "$stage/pet/bubu-orange" "$stage/preview"

  # Keep the install payload deterministic and free of historical QA paths.
  /bin/cp "$ROOT/shared/pet/bubu-orange/pet.json" "$stage/pet/bubu-orange/"
  /bin/cp "$ROOT/shared/pet/bubu-orange/spritesheet.webp" "$stage/pet/bubu-orange/"
  /bin/cp "$ROOT/shared/pet/bubu-orange/validation.json" "$stage/pet/bubu-orange/"
  /bin/cp "$ROOT/shared/pet/bubu-orange/vocabulary-web3-3000.json" "$stage/pet/bubu-orange/"
  /bin/cp "$ROOT/shared/pet/bubu-orange/qa/release-freeze-v29.json" "$stage/pet/bubu-orange/"
  local preview_name
  for preview_name in \
    "orange-bubu-static.png" \
    "橙色卜卜-左拖回到那一天-宠物动作.gif" \
    "橙色卜卜-右拖椅边主唱Live.gif"; do
    /bin/cp "$ROOT/shared/preview/$preview_name" "$stage/preview/"
  done
  /usr/bin/ditto "$ROOT/windows/BubuQuotaPanel" "$stage/windows"
  /usr/bin/ditto "$ROOT/windows/package" "$stage"
  /bin/cp "$ROOT/windows/README.md" "$stage/README.md"
  /bin/cp "$ROOT/windows/VERSION.txt" "$stage/VERSION.txt"
  /bin/cp "$ROOT/LICENSE" "$ROOT/ASSET-NOTICE.md" "$ROOT/PRIVACY.md" "$stage/"
  /bin/cp "$ROOT/ORANGE-BUBU-PROJECT.txt" "$stage/"
  if [[ "$codex_only" == "true" ]]; then
    /bin/cp "$ROOT/windows/CODEX-ONLY.txt" "$stage/CODEX-ONLY.txt"
  fi
  if [[ "$web3_vocabulary" == "true" ]]; then
    /bin/cp "$ROOT/windows/package/WEB3-VOCABULARY.txt" "$stage/WEB3-VOCABULARY.txt"
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

if [[ "$WEB3_VOCABULARY_RELEASE" == "true" ]]; then
  /bin/rm -f "$WEB3_VOCABULARY_OUT"
  stage_package "$WEB3_VOCABULARY_STAGE" false true
  /usr/bin/ditto -c -k --norsrc --keepParent "$WEB3_VOCABULARY_STAGE" "$WEB3_VOCABULARY_OUT"
  print "$WEB3_VOCABULARY_OUT"
  exit 0
fi

/bin/rm -f "$CODEX_ONLY_OUT"
if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /bin/rm -f "$FULL_OUT"
  stage_package "$FULL_STAGE" false false
fi
stage_package "$CODEX_ONLY_STAGE" true false

if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$FULL_STAGE" "$FULL_OUT"
  print "$FULL_OUT"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CODEX_ONLY_STAGE" "$CODEX_ONLY_OUT"
print "$CODEX_ONLY_OUT"
