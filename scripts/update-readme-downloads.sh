#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+$ ]]; then
  echo "用法：$0 <纯数字 Release 版本>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
START='<!-- DOWNLOAD_TABLE:START -->'
END='<!-- DOWNLOAD_TABLE:END -->'
REPOSITORY='Jingjing-nx/mayday-bubu-digital-materials'
BASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT

BLOCK="$START
<table>
  <thead>
    <tr>
      <th>宠物</th>
      <th>示意图</th>
      <th>版本</th>
      <th>macOS</th>
      <th>Windows</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td rowspan="2"><strong>蓝色卜卜</strong></td>
      <td rowspan="2" align="center"><img src="shared/preview/blue-bubu-static.png" alt="蓝色卜卜静态示意图" width="80"></td>
      <td>Web3 版</td>
      <td><a href="https://github.com/$REPOSITORY/releases/download/20/Mayday-Bubu-macOS-Universal-20.zip">版本 20 下载</a></td>
      <td><a href="https://github.com/$REPOSITORY/releases/download/20/Mayday-Bubu-Windows-10-11-20.zip">版本 20 下载</a></td>
    </tr>
    <tr>
      <td>普通版</td>
      <td><a href="https://github.com/$REPOSITORY/releases/download/20/Mayday-Bubu-macOS-Universal-Codex-Only-20.zip">版本 20 下载</a></td>
      <td><a href="https://github.com/$REPOSITORY/releases/download/20/Mayday-Bubu-Windows-10-11-Codex-Only-20.zip">版本 20 下载</a></td>
    </tr>
    <tr>
      <td rowspan=\"2\"><strong>橙色卜卜</strong></td>
      <td rowspan=\"2\" align=\"center\"><img src=\"shared/preview/orange-bubu-static.png\" alt=\"橙色卜卜静态示意图\" width=\"80\"></td>
      <td>Web3 版</td>
      <td><a href=\"$BASE_URL/Orange-Bubu-macOS-Universal-$VERSION.zip\">版本 $VERSION 下载</a></td>
      <td><a href=\"$BASE_URL/Orange-Bubu-Windows-10-11-$VERSION.zip\">版本 $VERSION 下载</a></td>
    </tr>
    <tr>
      <td>普通版</td>
      <td><a href=\"$BASE_URL/Orange-Bubu-macOS-Universal-Codex-Only-$VERSION.zip\">版本 $VERSION 下载</a></td>
      <td><a href=\"$BASE_URL/Orange-Bubu-Windows-10-11-Codex-Only-$VERSION.zip\">版本 $VERSION 下载</a></td>
    </tr>
  </tbody>
</table>

- **Web3 版**：包含 Codex 额度、任务进度与 BTC 行情。
- **普通版**：保留 Codex 额度和任务进度，不显示、也不请求 BTC 行情。
- 蓝色卜卜当前正式版为 **20**；橙色卜卜当前正式版为 **$VERSION**，两套项目和安装目录彼此隔离。
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
echo "README 下载链接已更新为 Release $VERSION"
