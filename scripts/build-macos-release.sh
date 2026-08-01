#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="29"
ULTIMATE_VERSION="31"
CODEX_ONLY_RELEASE="false"
WEB3_VOCABULARY_RELEASE="false"
ULTIMATE_RELEASE="false"
if [[ "${1:-}" == "--codex-only" ]]; then
  CODEX_ONLY_RELEASE="true"
elif [[ "${1:-}" == "--web3-vocabulary" ]]; then
  WEB3_VOCABULARY_RELEASE="true"
elif [[ "${1:-}" == "--ultimate" ]]; then
  ULTIMATE_RELEASE="true"
elif [[ -n "${1:-}" ]]; then
  print -u2 "用法：$0 [--codex-only|--web3-vocabulary|--ultimate]"
  exit 1
fi
STAGE_ROOT="$ROOT/build/release"
FULL_STAGE="$STAGE_ROOT/橙色卜卜-macOS"
CODEX_ONLY_STAGE="$STAGE_ROOT/橙色卜卜-macOS-仅Codex额度"
WEB3_VOCABULARY_STAGE="$STAGE_ROOT/橙色卜卜-macOS-背Web3单词"
ULTIMATE_STAGE="$STAGE_ROOT/橙色卜卜-macOS-会唱歌也会背单词终极版"
FULL_OUT="$ROOT/dist/Orange-Bubu-macOS-Universal-$VERSION.zip"
CODEX_ONLY_OUT="$ROOT/dist/Orange-Bubu-macOS-Universal-Codex-Only-$VERSION.zip"
WEB3_VOCABULARY_OUT="$ROOT/dist/Orange-Bubu-Web3-Vocabulary-macOS-Universal-30.zip"
ULTIMATE_OUT="$ROOT/dist/Orange-Bubu-Ultimate-macOS-Universal-$ULTIMATE_VERSION.zip"
APP_PROJECT="$ROOT/macos/BubuQuotaPanel"
LABEL="io.github.mayday-materials.orange-bubu-quota-panel"

"$APP_PROJECT/scripts/build.sh" >/dev/null

stage_package() {
  local stage="$1"
  local codex_only="$2"
  local web3_vocabulary="$3"
  local ultimate="$4"

  /bin/rm -rf "$stage"
  mkdir -p "$stage/pet/bubu-orange" "$stage/quota-panel" "$stage/preview"

  # Ship the immutable runtime contract only. Historical QA, working files and
  # generation metadata stay in the source repository, never in user packages.
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
  /usr/bin/ditto "$APP_PROJECT/build/橙色卜卜额度面板.app" "$stage/quota-panel/橙色卜卜额度面板.app"
  /bin/cp "$APP_PROJECT/Resources/$LABEL.plist.in" "$stage/quota-panel/$LABEL.plist.in"
  /bin/cp "$ROOT/macos/README.md" "$stage/README.md"
  /bin/cp "$ROOT/macos/VERSION.txt" "$stage/VERSION.txt"
  /bin/cp "$ROOT/LICENSE" "$ROOT/ASSET-NOTICE.md" "$ROOT/PRIVACY.md" "$stage/"
  /bin/cp "$ROOT/ORANGE-BUBU-PROJECT.txt" "$stage/"
  /bin/cp "$ROOT/macos/package/安装卜卜.command" "$stage/安装卜卜-macOS.command"
  /bin/cp "$ROOT/macos/package/卸载卜卜.command" "$stage/卸载卜卜-macOS.command"
  /bin/cp "$ROOT/macos/package/检查卜卜.command" "$stage/检查卜卜-macOS.command"
  /bin/cp "$ROOT/macos/package/安装被拦截-打开隐私与安全.html" "$stage/安装被拦截-打开隐私与安全.html"
  /bin/cp "$ROOT/macos/package/如果仍无法打开-Apple官方步骤.webloc" "$stage/如果仍无法打开-Apple官方步骤.webloc"
  if [[ "$codex_only" == "true" ]]; then
    /bin/cp "$ROOT/macos/package/CODEX-ONLY.txt" "$stage/CODEX-ONLY.txt"
  fi
  if [[ "$web3_vocabulary" == "true" ]]; then
    /bin/cp "$ROOT/macos/package/WEB3-VOCABULARY.txt" "$stage/WEB3-VOCABULARY.txt"
  fi
  if [[ "$ultimate" == "true" ]]; then
    /bin/cp "$ROOT/macos/package/ULTIMATE.txt" "$stage/ULTIMATE.txt"
  fi
  /bin/chmod +x "$stage"/*.command

  (
    cd "$stage"
    export LC_ALL=C
    find . -type f ! -name CHECKSUMS-SHA256.txt -print | sort |
      while IFS= read -r file; do /usr/bin/shasum -a 256 "$file"; done > CHECKSUMS-SHA256.txt
  )
}

if [[ "$WEB3_VOCABULARY_RELEASE" == "true" ]]; then
  /bin/rm -f "$WEB3_VOCABULARY_OUT"
  stage_package "$WEB3_VOCABULARY_STAGE" false true false
  /usr/bin/ditto -c -k --norsrc --keepParent "$WEB3_VOCABULARY_STAGE" "$WEB3_VOCABULARY_OUT"
  printf '%s\n' "$WEB3_VOCABULARY_OUT"
  exit 0
fi

if [[ "$ULTIMATE_RELEASE" == "true" ]]; then
  /bin/rm -f "$ULTIMATE_OUT"
  stage_package "$ULTIMATE_STAGE" false true true
  /usr/bin/ditto -c -k --norsrc --keepParent "$ULTIMATE_STAGE" "$ULTIMATE_OUT"
  printf '%s\n' "$ULTIMATE_OUT"
  exit 0
fi

/bin/rm -f "$CODEX_ONLY_OUT"
if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /bin/rm -f "$FULL_OUT"
  stage_package "$FULL_STAGE" false false false
fi
stage_package "$CODEX_ONLY_STAGE" true false false

if [[ "$CODEX_ONLY_RELEASE" != "true" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$FULL_STAGE" "$FULL_OUT"
  printf '%s\n' "$FULL_OUT"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CODEX_ONLY_STAGE" "$CODEX_ONLY_OUT"
printf '%s\n' "$CODEX_ONLY_OUT"
