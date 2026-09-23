# 架构决策记录（ADR）

记录影响较大的技术取舍：当时的背景、可选方案、最终决定和代价。已接受的记录不修改，被推翻时新写一篇并标注「取代 NNNN」。

| 编号 | 标题 | 状态 |
|---|---|---|
| [0001](0001-iphone-as-central.md) | iPhone 做 BLE 中心设备，Mac 做外设 | 已接受（待 M1 真机确认） |
| [0002](0002-no-sandbox-on-mac.md) | Mac App 不使用沙盒，Developer ID 分发 | 已接受 |
| [0003](0003-unlock-by-simulated-input.md) | 通过模拟键盘输入密码解锁 | 已接受 |
| [0004](0004-guardkit-pure-logic.md) | 核心逻辑放进纯 Swift 包 GuardKit | 已接受 |
