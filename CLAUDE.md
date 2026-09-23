# NearGuard 项目说明（给 Claude Code）

- 开发规范以 CONTRIBUTING.md 为准；架构见 docs/architecture.md，协议见 docs/protocol.md，进度见 docs/roadmap.md。
- 判断逻辑一律放 Shared/GuardKit 并写 Swift Testing 单元测试；App 层保持薄适配。
- 工程由 project.yml 生成（`scripts/bootstrap.sh`），不要手改 .xcodeproj。
- 提交前运行 `scripts/test.sh`（格式 + 单元测试 + 两端构建），提交信息用 Conventional Commits、中文描述。
- 真机相关功能按 docs/testing.md 清单请用户验证。测试机：iPhone 12 Pro（iOS 26+），Mac（macOS 26）。
- 新里程碑开工前先给实施计划并等用户确认。
