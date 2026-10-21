#!/bin/sh
# 把构建号设为 git 提交数，避免手动忘记改。
# 版本号（MARKETING_VERSION）仍是手改：测试期 0.1.x，正式版从 1.0 起。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -d .git ]; then
  echo "不在 git 仓库里，无法用提交数生成构建号" >&2
  exit 1
fi

COUNT=$(git rev-list --count HEAD)
echo "→ 构建号设为 ${COUNT}（当前提交数）"
agvtool new-version -all "$COUNT" >/dev/null
echo "✓ 完成。版本号 $(agvtool what-marketing-version -terse1 2>/dev/null || echo '?')，构建号 ${COUNT}"
