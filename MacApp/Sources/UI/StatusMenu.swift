import GuardKit
import SwiftUI

/// 菜单栏下拉菜单。
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let error = model.startupError {
            Text("⚠️ \(error)")
        }
        if model.devices.isEmpty {
            Text("尚未配对 iPhone")
        } else {
            ForEach(model.devices, id: \.deviceID) { device in
                Text("\(device.name)：\(model.proximity.label)")
            }
            if let rssi = model.lastRSSI, let at = model.lastReportAt {
                Text("信号 \(rssi) dBm · \(at.formatted(.relative(presentation: .numeric)))")
            }
        }
        Text("蓝牙：\(model.bluetoothState.label)")

        Divider()
        Button("配对新 iPhone…") { show(WindowID.pairing) }
        if !model.devices.isEmpty {
            Menu("解除配对") {
                ForEach(model.devices, id: \.deviceID) { device in
                    Button(device.name) { model.unpair(device) }
                }
            }
        }
        Button("调试窗口…") { show(WindowID.debug) }

        Divider()
        Text("版本 \(AppVersion.display) · 协议 v\(GuardKitInfo.protocolVersion)")
        Button("退出 NearGuard") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate()
    }
}
