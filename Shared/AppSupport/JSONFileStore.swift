import Foundation
import GuardKit

/// 把一个 Codable 值保存为 Application Support/NearGuard/ 下的 JSON 文件。
struct JSONFileStore<Value: Codable> {
    let url: URL

    init(filename: String) {
        url = AppPaths.directory.appendingPathComponent(filename)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Wire.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        try Wire.encode(value).write(to: url, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum AppPaths {
    /// Application Support/NearGuard，首次访问时创建。
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("NearGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
