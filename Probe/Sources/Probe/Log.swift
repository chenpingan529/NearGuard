import Foundation

/// 输出目录：Probe/output（日志 + 抓拍照片），与从哪个目录运行无关。
let outputDir: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Probe/Sources/Probe
    .deletingLastPathComponent()  // Probe/Sources
    .deletingLastPathComponent()  // Probe
    .appendingPathComponent("output")

private let logQueue = DispatchQueue(label: "probe.log")
private let logURL = outputDir.appendingPathComponent("probe.log")
private let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// 同时打印到终端和 output/probe.log（锁屏期间终端看不到，事后查日志）。
func log(_ message: String) {
    let line = "[\(logFormatter.string(from: Date()))] \(message)"
    logQueue.sync {
        print(line)
        fflush(stdout)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
