#!/bin/sh
# 格式与静态检查。两个工具都是可选安装：缺了就跳过，不算失败。
# 任何格式警告或 lint 违规都会让脚本以非 0 退出。
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# swift-format 不加 --strict 时即使有警告也返回 0，所以一律用它
STRICT="--strict"

STATUS=0
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

if xcrun --find swift-format >/dev/null 2>&1; then
  echo "→ swift-format lint${STRICT:+ --strict}"
  # 不能直接接管道：那样退出码来自 head，不是格式化器
  if xcrun swift-format lint ${STRICT} --recursive --configuration .swift-format \
      i5E Packages/ContentKit/Sources Packages/ContentKit/Tests >"$OUT" 2>&1; then
    echo "  ✓ 格式干净"
  else
    head -30 "$OUT"
    echo "  ✗ 有格式问题（可跑 xcrun swift-format format -i --recursive … 自动修）"
    STATUS=1
  fi
else
  echo "· 跳过 swift-format（未安装）"
fi

if command -v swiftlint >/dev/null 2>&1; then
  echo "→ swiftlint"
  # --no-cache：swiftlint 默认写 ~/Library/Caches，沙箱下会报权限错误
  if swiftlint lint --quiet --no-cache --config .swiftlint.yml >"$OUT" 2>&1; then
    echo "  ✓ 没有 lint 违规"
  else
    head -30 "$OUT"
    echo "  ✗ 有 lint 违规"
    STATUS=1
  fi
else
  echo "· 跳过 swiftlint（未安装）"
fi

exit "$STATUS"
