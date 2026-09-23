# 版本与发版流程

## 版本号

遵循 [语义化版本](https://semver.org/lang/zh-CN/) `MAJOR.MINOR.PATCH`：

- 1.0 之前：每个里程碑完成提升 MINOR（M0 = 0.1.0，M1 = 0.2.0 …），修复提升 PATCH。
- 1.0 之后：不兼容的协议 / 数据变更提升 MAJOR。

| 位置 | 含义 |
|---|---|
| `Configs/Version.xcconfig` → `MARKETING_VERSION` | 对外版本号，Mac 与 iPhone 始终一致 |
| `Configs/Version.xcconfig` → `CURRENT_PROJECT_VERSION` | 构建号，单调递增，每次上传都要加 1 |
| `GuardKitInfo.protocolVersion` | 通信协议版本，与 App 版本独立 |
| git tag `vX.Y.Z` | 与 `MARKETING_VERSION` 一致 |

## 发版步骤

1. 确认 `main` 上 CI 全绿，并完成 [真机测试清单](testing.md) 中对应里程碑的项目。
2. 修改 `Configs/Version.xcconfig`：版本号、构建号 +1。
3. 把 `CHANGELOG.md` 的 `Unreleased` 改为 `[X.Y.Z] - YYYY-MM-DD`，并新建空的 `Unreleased`。
4. 提交：`chore(release): vX.Y.Z`，打标签 `git tag -a vX.Y.Z -m "vX.Y.Z"`，推送标签。
5. 在 GitHub 上基于标签创建 Release，正文复制 CHANGELOG 对应段落。

## 分发（M4 起）

| 平台 | 方式 |
|---|---|
| Mac | Developer ID Application 签名 → `notarytool` 公证 → staple → 打包 DMG 附到 GitHub Release |
| iPhone | Archive → TestFlight（个人使用可直接真机安装） |

签名需要的 Team ID 放在 `Configs/Local.xcconfig`（不提交）。公证凭据用 `xcrun notarytool store-credentials` 存到钥匙串，不写进脚本或仓库。
