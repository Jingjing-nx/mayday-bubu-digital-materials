#!/usr/bin/env bash
set -euo pipefail

SKIN="${1:-}"
VERSION="${2:-}"
if [[ "$SKIN" != "blue" && "$SKIN" != "orange" && "$SKIN" != "orange-vocabulary" && "$SKIN" != "orange-ultimate" ]]; then
  echo "用法：$0 <blue|orange|orange-vocabulary|orange-ultimate> <纯数字 Release 版本>" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+$ ]]; then
  echo "用法：$0 <blue|orange|orange-vocabulary|orange-ultimate> <纯数字 Release 版本>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
START='<!-- DOWNLOAD_TABLE:START -->'
END='<!-- DOWNLOAD_TABLE:END -->'
REPOSITORY='Jingjing-nx/mayday-bubu-digital-materials'
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT

current_version() {
  local asset_prefix="$1"
  { grep -oE "releases/download/[0-9]+/${asset_prefix}" "$README" || true; } \
    | head -n 1 \
    | sed -E 's#releases/download/([0-9]+)/.*#\1#'
}

BLUE_VERSION="$(current_version 'Mayday-Bubu-macOS-Universal-[0-9]+\.zip')"
ORANGE_VERSION="$(current_version 'Orange-Bubu-macOS-Universal-[0-9]+\.zip')"
ORANGE_VOCABULARY_VERSION="$(current_version 'Orange-Bubu-Web3-Vocabulary-macOS-Universal-[0-9]+\.zip')"
ORANGE_ULTIMATE_VERSION="$(current_version 'Orange-Bubu-Ultimate-macOS-Universal-[0-9]+\.zip')"
[[ "$BLUE_VERSION" =~ ^[0-9]+$ ]] || {
  echo "README 中找不到蓝色卜卜当前版本。" >&2
  exit 1
}
[[ "$ORANGE_VERSION" =~ ^[0-9]+$ ]] || {
  echo "README 中找不到橙色卜卜当前版本。" >&2
  exit 1
}
[[ "$ORANGE_VOCABULARY_VERSION" =~ ^[0-9]+$ ]] || ORANGE_VOCABULARY_VERSION="$ORANGE_VERSION"
[[ "$ORANGE_ULTIMATE_VERSION" =~ ^[0-9]+$ ]] || ORANGE_ULTIMATE_VERSION="$ORANGE_VOCABULARY_VERSION"

if [[ "$SKIN" == "blue" ]]; then
  BLUE_VERSION="$VERSION"
elif [[ "$SKIN" == "orange" ]]; then
  ORANGE_VERSION="$VERSION"
elif [[ "$SKIN" == "orange-vocabulary" ]]; then
  ORANGE_VOCABULARY_VERSION="$VERSION"
else
  ORANGE_ULTIMATE_VERSION="$VERSION"
fi

BLUE_URL="https://github.com/$REPOSITORY/releases/download/$BLUE_VERSION"
ORANGE_URL="https://github.com/$REPOSITORY/releases/download/$ORANGE_VERSION"
ORANGE_VOCABULARY_URL="https://github.com/$REPOSITORY/releases/download/$ORANGE_VOCABULARY_VERSION"
ORANGE_ULTIMATE_URL="https://github.com/$REPOSITORY/releases/download/$ORANGE_ULTIMATE_VERSION"
# Orange Bubu's released packages keep the visual singing action but do not
# bundle the optional singing audio. Do not relabel them on README regeneration.
ORANGE_RELEASED_SINGING_LABEL="不唱歌版"
ORANGE_PENDING_SINGING_LABEL="唱歌版"

BLOCK="$START
<table>
  <thead>
    <tr>
      <th>宠物</th>
      <th>示意图</th>
      <th>版本</th>
      <th>唱歌功能</th>
      <th>macOS</th>
      <th>Windows</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td rowspan=\"4\"><strong>蓝色卜卜</strong></td>
      <td rowspan=\"4\" align=\"center\"><img src=\"shared/preview/blue-bubu-static.png\" alt=\"蓝色卜卜看板与宠物示意图\" width=\"280\"></td>
      <td rowspan=\"2\">Web3 版</td>
      <td>唱歌版</td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-macOS-Universal-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-Windows-10-11-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td>不唱歌版</td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-macOS-Universal-No-Singing-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-Windows-10-11-No-Singing-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td rowspan=\"2\">普通版</td>
      <td>唱歌版</td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-macOS-Universal-Codex-Only-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-Windows-10-11-Codex-Only-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td>不唱歌版</td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-macOS-Universal-Codex-Only-No-Singing-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
      <td><a href=\"$BLUE_URL/Mayday-Bubu-Windows-10-11-Codex-Only-No-Singing-$BLUE_VERSION.zip\">版本 $BLUE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td rowspan=\"6\"><strong>橙色卜卜</strong></td>
      <td rowspan=\"6\" align=\"center\"><img src=\"shared/preview/orange-bubu-static.png\" alt=\"橙色卜卜完整效果示意图\" width=\"280\"></td>
      <td rowspan=\"2\">Web3 版</td>
      <td>$ORANGE_RELEASED_SINGING_LABEL</td>
      <td><a href=\"$ORANGE_URL/Orange-Bubu-macOS-Universal-$ORANGE_VERSION.zip\">版本 $ORANGE_VERSION 下载</a></td>
      <td><a href=\"$ORANGE_URL/Orange-Bubu-Windows-10-11-$ORANGE_VERSION.zip\">版本 $ORANGE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td>$ORANGE_PENDING_SINGING_LABEL</td>
      <td>制作中</td>
      <td>制作中</td>
    </tr>
    <tr>
      <td rowspan=\"2\">普通版</td>
      <td>$ORANGE_RELEASED_SINGING_LABEL</td>
      <td><a href=\"$ORANGE_URL/Orange-Bubu-macOS-Universal-Codex-Only-$ORANGE_VERSION.zip\">版本 $ORANGE_VERSION 下载</a></td>
      <td><a href=\"$ORANGE_URL/Orange-Bubu-Windows-10-11-Codex-Only-$ORANGE_VERSION.zip\">版本 $ORANGE_VERSION 下载</a></td>
    </tr>
    <tr>
      <td>$ORANGE_PENDING_SINGING_LABEL</td>
      <td>制作中</td>
      <td>制作中</td>
    </tr>
    <tr>
      <td>背 Web3 单词版</td>
      <td>不唱歌版</td>
      <td><a href=\"$ORANGE_VOCABULARY_URL/Orange-Bubu-Web3-Vocabulary-macOS-Universal-$ORANGE_VOCABULARY_VERSION.zip\">版本 $ORANGE_VOCABULARY_VERSION 下载</a></td>
      <td><a href=\"$ORANGE_VOCABULARY_URL/Orange-Bubu-Web3-Vocabulary-Windows-10-11-$ORANGE_VOCABULARY_VERSION.zip\">版本 $ORANGE_VOCABULARY_VERSION 下载</a></td>
    </tr>
    <tr>
      <td><strong>会唱歌、也会背单词<br>终极版</strong></td>
      <td>唱歌 + 背单词</td>
      <td><a href=\"$ORANGE_ULTIMATE_URL/Orange-Bubu-Ultimate-macOS-Universal-$ORANGE_ULTIMATE_VERSION.zip\">版本 $ORANGE_ULTIMATE_VERSION 下载</a></td>
      <td><a href=\"$ORANGE_ULTIMATE_URL/Orange-Bubu-Ultimate-Windows-10-11-$ORANGE_ULTIMATE_VERSION.zip\">版本 $ORANGE_ULTIMATE_VERSION 下载</a></td>
    </tr>
  </tbody>
</table>

- **Web3 版**：包含 Codex 额度、任务进度与 BTC 行情。
- **普通版**：保留 Codex 额度和任务进度，不显示、也不请求 BTC 行情。
- **唱歌版**：向左拖动时保留唱歌画面动作，并播放 27.5 秒音乐。
- **不唱歌版**：只删除唱歌 MP3 音效；唱歌画面动作、持续时间和其他功能完全相同。
- **背 Web3 单词版**：保留完整 Web3 面板；鼠标悬停电脑即可学习内置 3000 词，并在本机记录复习进度。当前为 **$ORANGE_VOCABULARY_VERSION** 版。
- **会唱歌、也会背单词终极版**：同时提供本地 27.5 秒音乐与 Web3 3000 词学习卡，保留完整 BTC 面板。当前为 **$ORANGE_ULTIMATE_VERSION** 版。
- 蓝色卜卜当前正式版为 **$BLUE_VERSION**；橙色卜卜基础版为 **$ORANGE_VERSION**，两套项目和安装目录彼此隔离。
$END"

DOWNLOAD_BLOCK="$BLOCK" awk '
  $0 == "<!-- DOWNLOAD_TABLE:START -->" {
    print ENVIRON["DOWNLOAD_BLOCK"]
    skipping = 1
    next
  }
  $0 == "<!-- DOWNLOAD_TABLE:END -->" {
    skipping = 0
    next
  }
  !skipping { print }
' "$README" > "$TEMP_FILE"

if ! grep -Fq "$START" "$README" || ! grep -Fq "$END" "$README"; then
  echo "README 下载表格标记不存在，停止更新。" >&2
  exit 1
fi

mv "$TEMP_FILE" "$README"
trap - EXIT
echo "README 已更新 ${SKIN} Release ${VERSION}；另一宠物的版本号保持不变。"
