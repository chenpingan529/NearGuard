# 更新日志

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.2.0] - 2026-09-24

M1：最简两端 App，BLE 配对与测距。

### 新增
- Mac 菜单栏 App：BLE 广播、显示配对二维码、接收签名测距报告，菜单栏显示距离状态；调试窗口可查看与导出日志
- iPhone App：扫码（或系统相机打开链接）配对、后台 BLE 连接与签名报告（状态恢复 + 断线自动重连）
- 两端调试日志写入 Application Support/NearGuard/events.csv，便于校准 RSSI 阈值
- iPhone 诊断日志：记录前后台切换、数据保护状态和报告失败原因；日志写入失败时暂存，稍后补写
- GuardKit：配对会话、Mac 测距会话、iPhone 报告生成、BLE 长读写分段（共 92 个单元测试）

## [0.1.0] - 2026-09-23

M0：工程骨架与核心逻辑。

### 新增
- GuardKit 共享包
  - 签名封包 `SignedEnvelope`（P-256，消息类型纳入签名）、软件私钥与安全芯片私钥
  - 扫码配对流程：二维码邀请、HMAC 配对证明、双向签名校验
  - 防重放：一次性挑战簿（BLE）、时间窗口 + 随机数（CloudKit 指令）
  - 信号平滑（中位数 + 指数平滑）与距离判定（回差 + 驻留时间 + 超时）
  - 警戒状态机：自动解锁 / 锁屏、离开 / 定时 / 手动警戒、锁屏宽限期、20 秒观察期、Touch ID 自证、远程指令
  - CloudKit 记录结构定义
  - 69 个单元测试
- Mac 菜单栏 App 与 iPhone App 骨架（XcodeGen 生成工程）
- 开发规范、架构 / 协议 / 测试 / 发版文档、架构决策记录、GitHub Actions CI

### 原型结论（`Probe/`）
- macOS 26.5 锁屏状态下模拟输入密码解锁可行
- 锁屏状态下可检测键鼠输入、合盖开盖、解锁，并可正常抓拍
- 锁屏快捷键本身会误触发检测 → 正式版加入 3 秒宽限期

[Unreleased]: https://github.com/chenpingan529/NearGuard/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/chenpingan529/NearGuard/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/chenpingan529/NearGuard/releases/tag/v0.1.0
