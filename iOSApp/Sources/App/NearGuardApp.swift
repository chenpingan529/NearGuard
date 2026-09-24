import SwiftUI
import UIKit

/// iPhone App 入口。
@main
struct NearGuardApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(delegate.model)
                .onOpenURL { delegate.model.handle(url: $0) }
        }
    }
}

/// 系统因蓝牙事件在后台拉起 App 时不会创建界面，模型放在这里保证启动时就建立蓝牙连接。
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        model.log.log("app", "启动完成：\(Lifecycle.describe(application))")
        Lifecycle.observe(application, log: model.log)
        return true
    }
}

/// 诊断日志：记录前后台切换和数据保护状态，用于排查重启后后台拉起的行为（M1 真机验证）。
@MainActor
enum Lifecycle {
    static func describe(_ application: UIApplication) -> String {
        let state =
            switch application.applicationState {
            case .active: "前台"
            case .inactive: "非活跃"
            case .background: "后台"
            @unknown default: "未知"
            }
        let remaining = application.backgroundTimeRemaining
        let budget = remaining > 1e6 ? "不限" : String(format: "%.0fs", remaining)
        return "状态=\(state)，受保护数据=\(application.isProtectedDataAvailable ? "可用" : "不可用")，后台剩余=\(budget)"
    }

    private static var tokens: [NSObjectProtocol] = []

    static func observe(_ application: UIApplication, log: EventLog) {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "进入后台"),
            (UIApplication.willEnterForegroundNotification, "即将回到前台"),
            (UIApplication.didBecomeActiveNotification, "变为活跃"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "受保护数据可用（已解锁）"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "受保护数据即将不可用（锁屏）"),
            (UIApplication.willTerminateNotification, "即将终止"),
        ]
        tokens = events.map { name, label in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { log.log("app", "\(label)：\(describe(application))") }
            }
        }
    }
}
