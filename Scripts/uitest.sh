#!/bin/sh
# 跑 UI 冒烟测试。默认在 macOS 上跑；也可以
#   DESTINATION='platform=iOS Simulator,name=iPhone 17' ./Scripts/uitest.sh
#
# 注意：macOS 上必须允许本地 adhoc 签名（CODE_SIGNING_ALLOWED=YES），
# 否则测试 runner 会被系统直接 kill（"Test crashed with signal kill"）。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

DESTINATION=${DESTINATION:-platform=macOS}
DERIVED=${DERIVED_DATA:-"$ROOT/build/DDTest"}

if [ ! -f "i5E/Resources/content.db" ]; then
  echo "警告：i5E/Resources/content.db 不存在，App 启动会失败。" >&2
  echo "      先跑 ./Scripts/stage-content.sh" >&2
fi

echo "→ xcodebuild test ($DESTINATION)"
xcodebuild test \
  -project i5E.xcodeproj \
  -scheme i5E \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  "$@" 2>&1 | tee "$ROOT/build/uitest.log" | \
  grep -E "^Test Suite 'All tests'|^Test Case|error:|\*\* TEST" || true

if grep -q "\*\* TEST SUCCEEDED" "$ROOT/build/uitest.log"; then
  echo "✓ UI 测试通过"
else
  echo "✗ UI 测试失败，完整日志：build/uitest.log" >&2
  exit 1
fi
