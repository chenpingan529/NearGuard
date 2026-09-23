import Foundation

/// GuardKit 的全局常量。
public enum GuardKitInfo {
    /// 线上协议版本。BLE 消息和二维码都带这个值，不兼容的改动必须加 1。
    public static let protocolVersion = 1
}

/// GuardKit 里所有可预期的失败。
public enum GuardKitError: Error, Equatable, Sendable {
    /// 数据格式不对，无法解析。
    case malformed
    /// 对端使用了不支持的协议或封包版本。
    case unsupportedVersion(Int)
    /// 签名校验失败。
    case badSignature
    /// 公钥或私钥数据无效。
    case invalidKey
    /// 消息类型和期望的不一致（防止把一种消息的签名挪到另一种消息上用）。
    case unexpectedKind
    /// 时间戳超出允许的时间窗口，或二维码已过期。
    case expired
    /// 同一个随机数被重复使用。
    case replayed
    /// 不是本机发出的挑战，或挑战已被用过、已过期。
    case unknownChallenge
    /// 配对证明和二维码里的配对码对不上。
    case pairingProofMismatch
    /// 本机没有可用的安全芯片。
    case secureEnclaveUnavailable
}

/// 生成指定长度的安全随机字节。
func randomBytes(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
}
