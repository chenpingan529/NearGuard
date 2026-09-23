import SwiftUI

/// Mac 菜单栏 App 入口。
@main
struct NearGuardMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
                .environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }

        Window("配对 iPhone", id: WindowID.pairing) {
            PairingView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("NearGuard 调试", id: WindowID.debug) {
            DebugView()
                .environment(model)
        }
        .defaultSize(width: 720, height: 480)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let pairing = "pairing"
    static let debug = "debug"
}

extension AppModel {
    var menuBarSymbol: String {
        guard !devices.isEmpty else { return "lock.shield" }
        switch proximity {
        case .near: return "iphone.radiowaves.left.and.right"
        case .far: return "iphone"
        case .absent, .unknown: return "iphone.slash"
        }
    }
}
