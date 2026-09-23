# NearGuard

[![CI](https://github.com/chenpingan529/NearGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/chenpingan529/NearGuard/actions/workflows/ci.yml)
![平台](https://img.shields.io/badge/macOS-26%2B-blue) ![平台](https://img.shields.io/badge/iOS-26%2B-blue) ![协议](https://img.shields.io/badge/license-MIT-green)

**带着 iPhone 走近，Mac 自动解锁；走开，自动锁屏。你不在时有人动你的 Mac，手机马上收到带照片的提醒。**

NearGuard 由一个 Mac 菜单栏 App 和一个 iPhone App 组成。两者通过蓝牙判断距离，用 iPhone 安全芯片里的私钥签名来证明「真的是你的手机」，并通过 iCloud（CloudKit）传递报警和远程指令。不需要任何第三方服务器。

> ⚠️ 项目处于早期开发阶段（当前 **v0.1.0 / M0**），还不能日常使用。进度见 [路线图](docs/roadmap.md)。

## 功能

| 功能 | 说明 | 状态 |
|---|---|---|
| 靠近自动解锁 | 手机靠近且签名校验通过，自动输入登录密码解锁 | M2 |
| 离开自动锁屏 | 手机离开几秒后自动锁屏 | M2 |
| 离开警戒 | 手机离开超过 30 秒自动进入警戒 | M2 |
| 定时警戒 | 设定的时间段内始终警戒，并禁用自动解锁 | M2 |
| 抓拍报警 | 警戒中有人操作 Mac → 立即拍照 → 20 秒内未用 Touch ID 自证 → 推送到手机 | M2 / M3 |
| 远程处理 | 通知上直接选择 **[立即锁定]**（锁屏并再拍一张）或 **[是我本人]** | M3 |

## 工作原理

```
 iPhone（中心设备）                         Mac（外设，菜单栏 App）
 ┌──────────────────┐   BLE：挑战 / 签名测距报告   ┌─────────────────────────┐
 │ 安全芯片私钥      │ ◀────────────────────────▶ │ 验签 → 平滑 → 距离判定    │
 │ 测量信号强度      │                             │ 警戒状态机               │
 │ 通知：锁定 / 本人 │                             │ 解锁 / 锁屏 / 抓拍        │
 └────────┬─────────┘                             └───────────┬─────────────┘
          │            CloudKit 私有数据库（签名指令）           │
          └──────────────────── iCloud ─────────────────────────┘
```

- **不信任信号本身**：每次测距报告都带 Mac 发出的一次性随机数，并由 iPhone 安全芯片签名，录下蓝牙信号重放没有用。
- **核心逻辑可测试**：协议、加密、测距滤波、警戒状态机都在共享包 `GuardKit` 里，是不依赖系统的纯逻辑，有完整的单元测试。

详见 [架构说明](docs/architecture.md) 和 [通信协议](docs/protocol.md)。

## 系统要求

- Mac：macOS 26 或更高，带摄像头；需要授予辅助功能（模拟输入解锁）、摄像头、蓝牙权限
- iPhone：iOS 26 或更高（开发测试机型：iPhone 12 Pro）
- 同一个 Apple ID 登录 iCloud

## 开发

```bash
brew install xcodegen
scripts/bootstrap.sh          # 生成 NearGuard.xcodeproj，并创建 Configs/Local.xcconfig
open NearGuard.xcodeproj
scripts/test.sh               # 格式检查 + 单元测试 + 两端构建（与 CI 相同）
```

真机运行前，在 `Configs/Local.xcconfig` 中填入你的 `DEVELOPMENT_TEAM`。

开发规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 目录结构

```
├── Shared/GuardKit/      两端共用的 Swift Package（协议、加密、测距、警戒状态机）+ 单元测试
├── MacApp/               Mac 菜单栏 App
├── iOSApp/               iPhone App
├── Probe/                原型验证命令行工具（锁屏解锁、锁屏检测与抓拍）
├── Configs/              xcconfig：版本号、签名
├── docs/                 架构、协议、测试、发版、路线图、架构决策记录
├── scripts/              bootstrap / test / format
└── project.yml           XcodeGen 工程定义
```

## 文档

- [架构说明](docs/architecture.md)
- [通信协议](docs/protocol.md)
- [测试策略与真机测试清单](docs/testing.md)
- [版本与发版流程](docs/release.md)
- [路线图](docs/roadmap.md)
- [架构决策记录](docs/decisions/)
- [安全说明](SECURITY.md)
- [更新日志](CHANGELOG.md)

## 隐私

- 登录密码只保存在本机钥匙串中，仅 NearGuard 可读取。
- 抓拍照片只存在你自己的 iCloud 私有数据库里，开发者无法访问。
- 不包含任何统计、广告或第三方 SDK。

## 许可证

[MIT](LICENSE)
