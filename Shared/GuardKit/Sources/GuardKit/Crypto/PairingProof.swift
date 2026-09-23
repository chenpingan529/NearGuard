import CryptoKit
import Foundation

/// 配对证明：iPhone 用二维码里的一次性配对码对自己的公钥做 HMAC。
/// 配对码只通过二维码传递，不经过 BLE，所以旁边监听 BLE 的人无法冒充 iPhone 完成配对。
public enum PairingProof {
    public static func make(pairingCode: Data, phonePublicKey: Data, macID: UUID, deviceID: UUID) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(
            for: message(phonePublicKey: phonePublicKey, macID: macID, deviceID: deviceID),
            using: SymmetricKey(data: pairingCode)
        )
        return Data(mac)
    }

    /// 常量时间比较，避免时序侧信道。
    public static func isValid(
        _ proof: Data, pairingCode: Data, phonePublicKey: Data, macID: UUID, deviceID: UUID
    ) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: message(phonePublicKey: phonePublicKey, macID: macID, deviceID: deviceID),
            using: SymmetricKey(data: pairingCode)
        )
    }

    private static func message(phonePublicKey: Data, macID: UUID, deviceID: UUID) -> Data {
        var data = Data("nearguard-pairing-v1".utf8)
        data.append(phonePublicKey)
        data.append(macID.bytes)
        data.append(deviceID.bytes)
        return data
    }
}

extension UUID {
    var bytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}
