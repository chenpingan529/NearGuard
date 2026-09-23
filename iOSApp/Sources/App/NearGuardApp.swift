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
}
