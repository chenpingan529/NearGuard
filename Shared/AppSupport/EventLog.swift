import Foundation
import Observation
import os

/// 调试日志：界面实时显示，同时追加写入文件（后台被系统唤醒时也能留下记录），可导出 CSV 用于校准。
@MainActor
@Observable
final class EventLog {
    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let time: Date
        let category: String
        let message: String
        /// 与测距相关的记录附带信号强度和距离状态，方便导出后分析。
        let rssi: Int?
        let state: String?
    }

    static let capacity = 2000

    private(set) var entries: [Entry] = []
    let fileURL: URL
    private let logger = Logger(subsystem: "com.nearguard", category: "event")

    init(filename: String = "events.csv") {
        fileURL = AppPaths.directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data((Self.csvHeader + "\n").utf8).write(to: fileURL)
        }
    }

    func log(_ category: String, _ message: String, rssi: Int? = nil, state: String? = nil) {
        let entry = Entry(time: Date(), category: category, message: message, rssi: rssi, state: state)
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        append(Self.csvLine(entry))
    }

    func clear() {
        entries.removeAll()
        try? Data((Self.csvHeader + "\n").utf8).write(to: fileURL)
    }

    static let csvHeader = "time,category,rssi,state,message"

    static func csvLine(_ entry: Entry) -> String {
        let time = entry.time.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        let message = "\"" + entry.message.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        return [time, entry.category, entry.rssi.map(String.init) ?? "", entry.state ?? "", message]
            .joined(separator: ",")
    }

    private func append(_ line: String) {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
