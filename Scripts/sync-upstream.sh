#!/bin/sh
# 同步上游内容并重建。用法：./Scripts/sync-upstream.sh
#
# 做四件事：拉取上游 → 重建内容库 → 跑检查 → 构建两端。
# 不改仓库里的任何提交；确认无误后自己 commit。
#
# 只想重建、不拉取：SKIP_PULL=1 ./Scripts/sync-upstream.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM="$ROOT/DND5e_chm"

if [ ! -d "$UPSTREAM/.git" ]; then
  echo "找不到上游仓库：$UPSTREAM" >&2
  exit 1
fi

if [ "${SKIP_PULL:-0}" != "1" ]; then
  cd "$UPSTREAM"
  BEFORE=$(git rev-parse HEAD)
  echo "→ 拉取上游"
  git fetch --quiet origin
  if ! git merge --ff-only --quiet origin/HEAD 2>/dev/null; then
    echo "上游不是 fast-forward，需要手动处理（本地有改动或历史被改写）" >&2
    exit 1
  fi
  AFTER=$(git rev-parse HEAD)
  if [ "$BEFORE" = "$AFTER" ]; then
    echo "上游无更新，仍继续重建（内容可能因解析器改动而变化）"
  else
    echo "上游更新：$(echo "$BEFORE" | cut -c1-9) → $(echo "$AFTER" | cut -c1-9)"
    git --no-pager log --oneline "$BEFORE..$AFTER" | head -20
  fi
fi

cd "$ROOT"
echo
echo "→ 重建内容库"
python3 Tools/content/run.py build --jobs 7 --pack

echo
echo "→ 放入 App 资源目录"
./Scripts/stage-content.sh

echo
echo "→ 数据层测试"
./Scripts/test.sh

echo
echo "→ 格式检查"
./Scripts/lint.sh

echo
echo "→ 构建 iOS / macOS"
./Scripts/build.sh
DESTINATION=generic/platform=macOS ./Scripts/build.sh

echo
echo "改动："
git status --short | head -20
echo
echo "✓ 同步完成。检查上面的检查结果后提交。"
