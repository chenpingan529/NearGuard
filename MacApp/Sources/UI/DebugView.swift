import GuardKit
import SwiftUI
import UniformTypeIdentifiers

/// 调试窗口：实时状态 + 事件日志，可导出 CSV 用于校准距离阈值。
struct DebugView: View {
    @Environment(AppModel.self) private var model
    @State private var exporting = false
    @State private var document: CSVDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                stat("距离", model.proximity.label)
                stat("信号", model.lastRSSI.map { "\($0) dBm" } ?? "-")
                stat("有效报告", "\(model.reportCount)")
                stat("拒绝", "\(model.rejectedCount)")
                stat("订阅", "\(model.subscriberCount)")
                stat("蓝牙", model.bluetoothState.label)
                Spacer()
                Button("导出 CSV") {
                    document = CSVDocument(url: model.log.fileURL)
                    exporting = true
                }
                Button("清空") { model.log.clear() }
            }
            Table(model.log.entries.reversed()) {
                TableColumn("时间") { Text($0.time.formatted(date: .omitted, time: .standard)) }
                    .width(80)
                TableColumn("类别", value: \.category).width(70)
                TableColumn("信号") { Text($0.rssi.map(String.init) ?? "") }.width(50)
                TableColumn("内容", value: \.message)
            }
        }
        .padding()
        .fileExporter(
            isPresented: $exporting, document: document, contentType: .commaSeparatedText,
            defaultFilename: "nearguard-mac-\(Date().formatted(.iso8601.year().month().day())).csv"
        ) { _ in }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
    }
}

/// 导出时直接复制日志文件。
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    let data: Data

    init(url: URL) {
        data = (try? Data(contentsOf: url)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
