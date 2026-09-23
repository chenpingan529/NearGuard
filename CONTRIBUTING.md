# 开发规范

## 1. 环境

| 工具 | 版本 |
|---|---|
| Xcode | 26.x（Swift 6.2+） |
| XcodeGen | `brew install xcodegen` |
| swift-format | 随 Xcode 提供（`xcrun swift-format`） |

```bash
scripts/bootstrap.sh   # 生成工程；首次会创建 Configs/Local.xcconfig
scripts/test.sh        # 提交前必须通过
scripts/format.sh      # 自动格式化
```

`NearGuard.xcodeproj` 由 `project.yml` 生成，**不提交、不手改**。新增 target、权限说明、构建设置都改 `project.yml`。

## 2. 分层与代码归属

| 层 | 位置 | 规则 |
|---|---|---|
| 核心逻辑 | `Shared/GuardKit` | 纯 Swift，不引用 UIKit / AppKit / CoreBluetooth / AVFoundation / CloudKit。时间、随机 ID 通过参数注入。**所有判断逻辑都放这里**，必须有单元测试 |
| 系统适配 | `MacApp/Sources`、`iOSApp/Sources` | 只负责把系统事件转成 GuardKit 的输入，把 GuardKit 的输出转成系统调用。保持薄 |
| 界面 | 同上，`UI/` 子目录 | SwiftUI；不写业务判断 |
| 原型 | `Probe/` | 只用于排查问题，不被正式代码依赖 |

判断标准：如果一段代码里出现了 `if`，而它不是在处理系统 API 的返回值，它大概率应该放进 GuardKit。

## 3. Swift 编码约定

- Swift 6 语言模式，严格并发检查（`SWIFT_STRICT_CONCURRENCY = complete`），不得有警告。
- 格式以 `.swift-format` 为准（行宽 120、4 空格缩进），CI 使用 `--strict`，警告即失败。
- 优先使用值类型（`struct` / `enum`）；状态机类代码采用「输入事件 → 输出动作」的纯函数风格。
- 错误统一使用 `GuardKitError`，不用字符串错误。
- 注释用中文，解释**为什么**而不是**做了什么**；公开 API 写 `///` 文档注释。
- 禁止在代码、日志、测试数据中出现真实密码、Team ID 以外的账号信息、真实照片。
- 安全相关代码（签名、验签、防重放、密码存取）修改必须附带对应的反例测试（伪造、篡改、重放）。

## 4. 测试

- 单元测试使用 Swift Testing（`import Testing`），测试名用中文描述行为，例如 `func 过期挑战被拒绝()`。
- GuardKit 新增或修改的逻辑必须有测试；修 bug 先写能复现的失败测试。
- 需要真机的功能（BLE、锁屏、摄像头、推送）按 [docs/testing.md](docs/testing.md) 的清单手工验证，并在 PR 中写明设备与系统版本。

## 5. Git 流程

- 主分支 `main` 始终可构建、测试全绿。
- 功能开发在分支上进行：`feat/<简述>`、`fix/<简述>`、`docs/<简述>`，通过 PR 合并（squash merge）。
- 提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：

  ```
  <type>(<scope>): <中文简述>

  可选的正文：为什么这样改、有哪些取舍。
  ```

  `type`：`feat` `fix` `refactor` `test` `docs` `build` `ci` `chore` `perf`
  `scope`：`guardkit` `mac` `ios` `probe` `protocol` `cloud` 等

  示例：`feat(guardkit): 警戒状态机支持定时警戒跨夜时间段`

- 协议或 CloudKit 结构的不兼容改动，提交信息加 `BREAKING CHANGE:`，同时提升 `GuardKitInfo.protocolVersion` 并更新 [docs/protocol.md](docs/protocol.md)。

## 6. 文档

- 行为变化同步更新 `docs/` 下对应文档；重要的技术取舍写一篇架构决策记录（`docs/decisions/NNNN-标题.md`）。
- 每个 PR 在 `CHANGELOG.md` 的 `Unreleased` 下记录用户可感知的变化。

## 7. PR 检查清单

见 [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md)。
