#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PATTERN='(/Users/[^/[:space:]]+|[A-Za-z]:\\Users\\[^\\[:space:]]+|com\.jing|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})'

typeset -i findings=0
while IFS= read -r -d '' file; do
  case "$file" in
    scripts/privacy-audit.sh|*.png|*.gif|*.webp|*.jpg) continue ;;
  esac
  if rg -n -i "$PATTERN" "$ROOT/$file"; then
    findings=1
  fi
done < <(git -C "$ROOT" ls-files -z)

if (( findings > 0 )); then
  echo "隐私审计失败：发现可能的个人路径、邮箱或凭据。" >&2
  exit 1
fi

for archive in "$ROOT"/dist/*.zip(N); do
  if /usr/bin/unzip -Z1 "$archive" | rg -i '(^|/)(\.env|panel\.log|panel-health\.json|.*-Check\.txt|__MACOSX)(/|$)'; then
    echo "隐私审计失败：压缩包包含日志、状态或环境文件：$archive" >&2
    exit 1
  fi
done

echo "隐私审计通过。"
