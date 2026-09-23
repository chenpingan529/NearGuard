import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

/// 读取 / 改变系统锁屏、空闲、合盖等状态。
enum SystemState {
    /// 当前会话是否处于锁屏状态。
    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// 距离上一次键盘 / 鼠标 / 触控板输入的秒数（不需要任何权限）。
    static func hidIdleSeconds() -> Double? {
        guard let value = registryProperty(service: "IOHIDSystem", key: "HIDIdleTime") else { return nil }
        if let number = value as? NSNumber {
            return number.doubleValue / 1_000_000_000
        }
        if let data = value as? Data, data.count >= 8 {
            let ns = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return Double(ns) / 1_000_000_000
        }
        return nil
    }

    /// 屏幕盖是否合上；台式机或读取失败时返回 nil。
    static func isClamshellClosed() -> Bool? {
        registryProperty(service: "IOPMrootDomain", key: "AppleClamshellState") as? Bool
    }

    /// 立即锁屏。优先用 login.framework 的私有 API，失败则让显示器休眠（依赖「立即要求密码」设置）。
    @discardableResult
    static func lockScreen() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFn = @convention(c) () -> Int32
            let lock = unsafeBitCast(sym, to: LockFn.self)
            if lock() == 0 { return true }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 模拟用户活动来点亮屏幕。
    static func wakeDisplay() {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionDeclareUserActivity("MacIphoneProbe wake" as CFString, kIOPMUserActiveLocal, &assertionID)
        if result == kIOReturnSuccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { IOPMAssertionRelease(assertionID) }
        }
    }

    private static func registryProperty(service name: String, key: String) -> Any? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
