#!/bin/sh
# 构建 App（iOS 模拟器）。额外参数原样传给 xcodebuild。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f "i5E/Resources/content.db" ]; then
  echo "警告：i5E/Resources/content.db 不存在，App 启动后会提示内容库缺失。" >&2
  echo "      先跑 ./Scripts/stage-content.sh" >&2
fi

# DESTINATION=generic/platform=macOS ./Scripts/build.sh 可以构建 Mac 目标
DESTINATION=${DESTINATION:-generic/platform=iOS Simulator}
DERIVED=${DERIVED_DATA:-"$ROOT/build/DerivedData"}

echo "→ xcodebuild build ($DESTINATION)"
xcodebuild \
  -project i5E.xcodeproj \
  -scheme i5E \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build "$@" 2>&1 | tee "$ROOT/build/xcodebuild.log" | \
  grep -E "^(error|warning): |\*\* BUILD" || true

# grep 会把退出码吃掉，用日志判断结果
if grep -q "\*\* BUILD SUCCEEDED" "$ROOT/build/xcodebuild.log"; then
  echo "✓ 构建成功"
else
  echo "✗ 构建失败，完整日志：build/xcodebuild.log" >&2
  exit 1
fi
