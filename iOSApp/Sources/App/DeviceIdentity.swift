import Foundation
import GuardKit
import Security

/// 本机身份：deviceID 与安全芯片私钥。
/// 私钥访问控制设为「首次解锁后可用」，否则手机锁屏时后台无法签名。
struct DeviceIdentity {
    let deviceID: UUID
    let signer: any Signer

    private static let keyAccount = "device-signing-key"
    private static let idAccount = "device-id"

    static func loadOrCreate() throws -> DeviceIdentity {
        let deviceID = try loadOrCreateID()
        #if targetEnvironment(simulator)
            // 模拟器没有安全芯片，用软件私钥代替，仅用于界面调试。
            if let raw = try Keychain.read(keyAccount) {
                return DeviceIdentity(deviceID: deviceID, signer: try SoftwareSigner(rawRepresentation: raw))
            }
            let signer = SoftwareSigner()
            try Keychain.write(signer.rawRepresentation, account: keyAccount)
            return DeviceIdentity(deviceID: deviceID, signer: signer)
        #else
            if let data = try Keychain.read(keyAccount) {
                return DeviceIdentity(deviceID: deviceID, signer: try SecureEnclaveSigner(dataRepresentation: data))
            }
            var error: Unmanaged<CFError>?
            guard
                let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error)
            else { throw error!.takeRetainedValue() as Error }
            let signer = try SecureEnclaveSigner(accessControl: access)
            try Keychain.write(signer.dataRepresentation, account: keyAccount)
            return DeviceIdentity(deviceID: deviceID, signer: signer)
        #endif
    }

    private static func loadOrCreateID() throws -> UUID {
        if let data = try Keychain.read(idAccount), let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) {
            return id
        }
        let id = UUID()
        try Keychain.write(Data(id.uuidString.utf8), account: idAccount)
        return id
    }
}

/// 已配对的 Mac，iPhone 端持久化保存。
struct PairedMac: Codable, Equatable {
    var macID: UUID
    var name: String
    var publicKey: Data
    /// CoreBluetooth 分配的外设标识，用于快速重连；Mac 蓝牙地址轮换后可能失效，失效时改为扫描。
    var peripheralID: UUID?
    var pairedAt: Date
}
