import Foundation
import GuardKit

/// 本机身份：macID 与签名私钥。私钥存登录钥匙串，首次启动时生成。
struct MacIdentity {
    let macID: UUID
    let signer: SoftwareSigner

    private static let keyAccount = "mac-signing-key"
    private static let idAccount = "mac-id"

    static func loadOrCreate() throws -> MacIdentity {
        if let raw = try Keychain.read(keyAccount),
            let idData = try Keychain.read(idAccount),
            let id = UUID(uuidString: String(decoding: idData, as: UTF8.self))
        {
            return MacIdentity(macID: id, signer: try SoftwareSigner(rawRepresentation: raw))
        }
        let identity = MacIdentity(macID: UUID(), signer: SoftwareSigner())
        try Keychain.write(identity.signer.rawRepresentation, account: keyAccount)
        try Keychain.write(Data(identity.macID.uuidString.utf8), account: idAccount)
        return identity
    }

    /// 电脑名称，显示在 iPhone 上。
    static var computerName: String {
        Host.current().localizedName ?? "Mac"
    }
}
