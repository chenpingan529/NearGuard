import Foundation

/// 验证 1：锁屏 → 等待 → 唤醒屏幕 → 模拟输入密码 → 检查是否解锁成功。
enum UnlockTest {
    static func run(delay: Double, mode: Keyboard.Mode) -> Int32 {
        guard Keyboard.isTrusted(prompt: true) else {
            log("❌ 没有「辅助功能」权限。请在 系统设置 → 隐私与安全性 → 辅助功能 中勾选当前终端 App，然后重新运行。")
            return 1
        }
        guard let raw = getpass("请输入 Mac 登录密码（只保存在内存中，不会写入磁盘）: ") else { return 1 }
        let password = String(cString: raw)
        guard !password.isEmpty else {
            log("❌ 密码为空")
            return 1
        }
        if mode == .keycode, password.contains(where: { !$0.isASCII }) {
            log("❌ keycode 模式只支持 ASCII 密码，请改用 --mode unicode")
            return 1
        }

        log("3 秒后锁屏，锁屏后 \(Int(delay)) 秒会尝试自动解锁（输入模式：\(mode.rawValue)）。期间请不要碰键盘和鼠标。")
        sleep(3)
        guard SystemState.lockScreen() else {
            log("❌ 锁屏失败")
            return 1
        }
        guard waitUntil(timeout: 5, { SystemState.isScreenLocked() }) else {
            log("❌ 调用了锁屏，但 5 秒内没有检测到锁屏状态")
            return 1
        }
        log("已锁屏")
        Thread.sleep(forTimeInterval: delay)

        log("唤醒屏幕")
        SystemState.wakeDisplay()
        Thread.sleep(forTimeInterval: 1.5)
        Keyboard.tapShift()
        Thread.sleep(forTimeInterval: 0.8)

        log("输入密码")
        guard Keyboard.type(password, mode: mode) else {
            log("❌ 密码里有 keycode 模式无法映射的字符")
            return 1
        }
        Thread.sleep(forTimeInterval: 0.2)
        Keyboard.pressReturn()

        if waitUntil(timeout: 10, { !SystemState.isScreenLocked() }) {
            log("✅ 解锁成功：锁屏状态下模拟输入可行（模式：\(mode.rawValue)）")
            return 0
        }
        log("❌ 10 秒内没有解锁：模拟输入被锁屏拦截了（模式：\(mode.rawValue)）。请手动解锁，然后把终端输出发给我。")
        return 2
    }

    private static func waitUntil(timeout: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
