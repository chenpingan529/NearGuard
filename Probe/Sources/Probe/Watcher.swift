import AppKit
import IOKit
import IOKit.usb

/// 验证 2：检测「有人在操作 Mac」，处于警戒状态时抓拍。
/// 原型里的警戒状态 = 屏幕已锁定（加 --always 则任何时候都算警戒）。
final class Watcher {
    private let alwaysGuard: Bool
    private let camera = Camera(outputDir: outputDir.appendingPathComponent("captures"))
    private let captureCooldown: TimeInterval = 15
    private var lastCapture = Date.distantPast
    private var lastIdle: Double = .greatestFiniteMagnitude
    private var lastInputLog = Date.distantPast
    private var lastLocked = SystemState.isScreenLocked()
    private var lastClamshell = SystemState.isClamshellClosed()
    private var usbPort: IONotificationPortRef?
    private var usbIterator: io_iterator_t = 0
    private var timer: Timer?

    init(alwaysGuard: Bool) {
        self.alwaysGuard = alwaysGuard
    }

    func start() {
        Camera.requestAccess { granted in
            log(granted ? "摄像头权限：已授权" : "⚠️ 摄像头权限未授权，只记录事件不抓拍")
        }

        let distributed = DistributedNotificationCenter.default()
        for (name, label) in [
            ("com.apple.screenIsLocked", "屏幕已锁定"),
            ("com.apple.screenIsUnlocked", "屏幕已解锁"),
            ("com.apple.screensaver.didstart", "屏保启动"),
            ("com.apple.screensaver.didstop", "屏保停止"),
        ] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.handleLockNotification(name: name, label: label)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for (name, label) in [
            (NSWorkspace.didWakeNotification, "系统从睡眠唤醒"),
            (NSWorkspace.screensDidWakeNotification, "显示器被唤醒"),
            (NSWorkspace.screensDidSleepNotification, "显示器休眠"),
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.event(label, trigger: name != NSWorkspace.screensDidSleepNotification)
            }
        }

        startUSBMonitor()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }

        log("开始监听（警戒条件：\(alwaysGuard ? "始终" : "屏幕锁定时")）。当前锁屏：\(lastLocked)，合盖：\(lastClamshell.map { "\($0)" } ?? "未知")。按 Ctrl+C 结束。")
    }

    // MARK: - 事件来源

    private func handleLockNotification(name: String, label: String) {
        if name == "com.apple.screenIsUnlocked" {
            // 在警戒状态下被解锁，是最需要报警的情况
            let wasGuarded = alwaysGuard || lastLocked
            lastLocked = false
            event(label, trigger: wasGuarded, forceGuard: wasGuarded)
        } else {
            if name == "com.apple.screenIsLocked" { lastLocked = true }
            event(label, trigger: false)
        }
    }

    /// 轮询空闲时间和合盖状态。
    private func poll() {
        if let idle = SystemState.hidIdleSeconds() {
            // 空闲时间突然变小 = 刚刚有键盘 / 鼠标 / 触控板输入
            if idle < lastIdle - 0.4, idle < 1.0, Date().timeIntervalSince(lastInputLog) > 5 {
                lastInputLog = Date()
                event("检测到键盘/鼠标输入（HIDIdleTime=\(String(format: "%.2f", idle))s）", trigger: true)
            }
            lastIdle = idle
        }
        let clamshell = SystemState.isClamshellClosed()
        if clamshell != lastClamshell {
            lastClamshell = clamshell
            if let closed = clamshell {
                event(closed ? "屏幕盖合上" : "屏幕盖打开", trigger: !closed)
            }
        }
        let locked = SystemState.isScreenLocked()
        if locked != lastLocked {
            // 兜底：通知丢失时依然能跟踪锁屏状态
            log("（轮询发现锁屏状态变为 \(locked)）")
            lastLocked = locked
        }
    }

    private func startUSBMonitor() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        usbPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.drainUSB(iterator, report: true)
        }
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                                         callback, context, &usbIterator)
        // 必须先清空迭代器才会收到后续通知；已有设备不报
        drainUSB(usbIterator, report: false)
    }

    private func drainUSB(_ iterator: io_iterator_t, report: Bool) {
        while case let device = IOIteratorNext(iterator), device != 0 {
            if report {
                let name = IORegistryEntryCreateCFProperty(device, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String ?? "未知设备"
                event("插入 USB 设备：\(name)", trigger: true)
            }
            IOObjectRelease(device)
        }
    }

    // MARK: - 处理

    /// trigger：该事件是否算作「有人操作」。forceGuard：忽略当前锁屏状态直接视为警戒中。
    private func event(_ label: String, trigger: Bool, forceGuard: Bool = false) {
        let locked = SystemState.isScreenLocked()
        let guarded = forceGuard || alwaysGuard || locked
        log("事件：\(label)｜锁屏=\(locked)｜警戒=\(guarded)")
        guard trigger, guarded else { return }
        guard Date().timeIntervalSince(lastCapture) > captureCooldown, !camera.isBusy else {
            log("  ↳ 冷却中，跳过抓拍")
            return
        }
        lastCapture = Date()
        log("  ↳ 🚨 警戒中检测到操作，开始抓拍（锁屏=\(locked)）")
        camera.capture(tag: locked ? "locked" : "unlocked") { url in
            log(url.map { "  ↳ 📸 已保存：\($0.path)" } ?? "  ↳ ❌ 抓拍失败")
        }
    }
}
