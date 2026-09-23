#!/usr/bin/env bash
# 按 .swift-format 规则就地格式化所有 Swift 代码。
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format format -i -r Shared MacApp iOSApp
