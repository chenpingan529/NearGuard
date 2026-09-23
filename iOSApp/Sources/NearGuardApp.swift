import GuardKit
import SwiftUI

/// iPhone App 入口。M0 只有骨架，功能在 M1 之后逐步接入。
@main
struct NearGuardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("尚未配对 Mac", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
                }
                Section("关于") {
                    LabeledContent("版本", value: AppVersion.display)
                    LabeledContent("协议", value: "v\(GuardKitInfo.protocolVersion)")
                    LabeledContent("安全芯片", value: SecureEnclaveSigner.isAvailable ? "可用" : "不可用")
                }
            }
            .navigationTitle("NearGuard")
        }
    }
}

#Preview {
    ContentView()
}
