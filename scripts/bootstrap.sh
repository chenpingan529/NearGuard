#!/usr/bin/env bash
# 初始化开发环境并生成 Xcode 工程。可重复执行。
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }

if [[ ! -f Configs/Local.xcconfig ]]; then
    cp Configs/Local.xcconfig.example Configs/Local.xcconfig
    echo "已创建 Configs/Local.xcconfig，请填入你的 DEVELOPMENT_TEAM 后再真机运行。"
fi

xcodegen generate --quiet
echo "✅ 已生成 NearGuard.xcodeproj"
