# Probe 原型验证

请在**你自己的终端 App**（终端 / iTerm 等）里运行。权限会授予这个终端 App。

```bash
cd Probe
swift build
```

## 0. 检查状态 / 摄像头
- `.build/debug/Probe status`：查看权限
- `.build/debug/Probe snap`：抓拍一张，首次运行会弹出摄像头授权

## 1. 锁屏自动解锁
`.build/debug/Probe unlock-test --delay 5`

需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 勾选你的终端 App。
如果失败，再试 `--mode keycode`，要求密码只含 ASCII 字符。

## 2. 锁屏时检测操作并抓拍
`.build/debug/Probe watch`

启动后按 Ctrl+Cmd+Q 锁屏，然后依次：动鼠标、敲键盘、插 U 盘、合盖再打开、解锁。

结果写在 `output/probe.log`，照片保存在 `output/captures/`。
