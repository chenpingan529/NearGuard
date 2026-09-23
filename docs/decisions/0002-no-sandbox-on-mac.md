# 0002 Mac App 不使用沙盒，Developer ID 分发

- 状态：已接受
- 日期：2026-09-23

## 背景

自动解锁需要在锁屏界面模拟键盘输入（需要辅助功能权限），检测锁屏时的操作需要读取 IOKit 状态、监听 USB 插拔。

## 决定

Mac App 不开启 App Sandbox，开启 Hardened Runtime，用 Developer ID Application 证书签名并公证，通过 GitHub Release 分发，不上架 Mac App Store。

## 代价

- 无法上架 Mac App Store。
- 需要自己处理更新（M4 考虑 Sparkle 或手动检查 GitHub Release）。
