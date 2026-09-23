import GuardKit
import SwiftUI

/// Mac 菜单栏 App 入口。M0 只有骨架，功能在 M1 之后逐步接入。
@main
struct NearGuardMacApp: App {
    var body: some Scene {
        MenuBarExtra("NearGuard", systemImage: "lock.shield") {
            StatusMenu()
        }
    }
}

struct StatusMenu: View {
    var body: some View {
        Text("尚未配对 iPhone")
        Divider()
        Text("版本 \(AppVersion.display) · 协议 v\(GuardKitInfo.protocolVersion)")
        Button("退出 NearGuard") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
