import Foundation
import Security

/// 钥匙串里的通用密码项读写。两端 App 共用。
/// macOS 上使用登录钥匙串（不沙盒的 App 没有数据保护钥匙串的访问组），
/// iOS 上使用「首次解锁后可用、仅限本机」，保证手机锁屏时后台也能读取。
enum Keychain {
    static let service = "com.nearguard"

    enum Failure: Error {
        case status(OSStatus)
    }

    static func read(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.status(status) }
        return result as? Data
    }

    static func write(_ data: Data, account: String) throws {
        let query = baseQuery(account)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            #if os(iOS)
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
