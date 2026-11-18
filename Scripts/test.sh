#!/bin/sh
# 跑数据层测试。需要一个构建好的内容库。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/Packages/ContentKit"

export CONTENT_DB=${CONTENT_DB:-"$ROOT/build/pack/content.db"}

if [ ! -f "$CONTENT_DB" ]; then
  echo "找不到内容库：$CONTENT_DB" >&2
  echo "先跑：python3 Tools/content/run.py build --pack" >&2
  echo "（没有内容库时，需要它的测试会被 skip，其余仍会跑）" >&2
fi

echo "→ swift test (CONTENT_DB=$CONTENT_DB)"
# --disable-sandbox：SwiftPM 评估包清单时会再套一层 sandbox-exec，
# 在受限环境里会被拒绝（"sandbox_apply: Operation not permitted"）。

# 先落盘再 tail，避免管道的退出码被 tail 吞掉（测试失败必须让脚本失败）。
LOG=$(mktemp "${TMPDIR:-/tmp}/i5e-test.XXXXXX")
trap 'rm -f "$LOG"' EXIT

if swift test --disable-sandbox "$@" >"$LOG" 2>&1; then
  STATUS=0
else
  STATUS=$?
fi

tail -25 "$LOG"
exit "$STATUS"
