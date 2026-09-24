import SwiftUI

/// 调试日志：实时事件列表，可分享 CSV 用于校准距离阈值。
struct DebugView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.log.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.time.formatted(date: .omitted, time: .standard))
                    Text(entry.category)
                    if let rssi = entry.rssi { Text("\(rssi) dBm") }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(entry.message).font(.callout)
            }
        }
        .listStyle(.plain)
        .navigationTitle("调试日志")
        .toolbar {
            ShareLink(item: model.log.fileURL)
            Button("清空", systemImage: "trash") { model.log.clear() }
        }
    }
}
