#!/usr/bin/env bash
# 本地与 CI 共用的检查：格式 → 单元测试 → 两端构建。
# 用法：scripts/test.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶︎ 格式检查"
xcrun swift-format lint --strict -r Shared MacApp iOSApp

echo "▶︎ GuardKit 单元测试"
swift test --package-path Shared/GuardKit

if [[ "${1:-}" == "--skip-build" ]]; then exit 0; fi

command -v xcodegen >/dev/null && xcodegen generate --quiet
DERIVED=.build/DerivedData

echo "▶︎ 构建 macOS App"
xcodebuild -quiet -project NearGuard.xcodeproj -scheme NearGuardMac \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build

echo "▶︎ 构建 iOS App"
xcodebuild -quiet -project NearGuard.xcodeproj -scheme NearGuardiOS \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build

echo "✅ 全部通过"
