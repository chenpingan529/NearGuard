import Foundation

enum AppVersion {
    /// 例如 `0.1.0 (1)`，来自 Configs/Version.xcconfig。
    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
