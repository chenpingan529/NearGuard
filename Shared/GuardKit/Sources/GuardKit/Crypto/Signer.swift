import CryptoKit
import Foundation

/// 能用 P-256 私钥签名的对象。公钥用 X9.63 格式（65 字节），签名用 raw 格式（64 字节）。
public protocol Signer: Sendable {
    var publicKey: Data { get }
    func sign(_ data: Data) throws -> Data
}

/// 软件私钥。Mac 端用它（私钥存在钥匙串里），测试也用它。
public struct SoftwareSigner: Signer {
    private let key: P256.Signing.PrivateKey

    public init() {
        key = P256.Signing.PrivateKey()
    }

    public init(rawRepresentation: Data) throws {
        do {
            key = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
        } catch {
            throw GuardKitError.invalidKey
        }
    }

    /// 用于存入钥匙串的私钥原始数据。
    public var rawRepresentation: Data { key.rawRepresentation }

    public var publicKey: Data { key.publicKey.x963Representation }

    public func sign(_ data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }
}

/// 安全芯片里的私钥。iPhone 端用它，私钥永远不出设备。
/// `dataRepresentation` 只是一个加密后的引用，只能在生成它的那台设备上使用。
public struct SecureEnclaveSigner: Signer, @unchecked Sendable {
    private let key: SecureEnclave.P256.Signing.PrivateKey

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// 新建一把私钥。`accessControl` 为空时使用「设备解锁后可用、仅限本机」。
    public init(accessControl: SecAccessControl? = nil) throws {
        guard Self.isAvailable else { throw GuardKitError.secureEnclaveUnavailable }
        if let accessControl {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
        } else {
            key = try SecureEnclave.P256.Signing.PrivateKey()
        }
    }

    public init(dataRepresentation: Data) throws {
        guard Self.isAvailable else { throw GuardKitError.secureEnclaveUnavailable }
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
        } catch {
            throw GuardKitError.invalidKey
        }
    }

    public var dataRepresentation: Data { key.dataRepresentation }

    public var publicKey: Data { key.publicKey.x963Representation }

    public func sign(_ data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }
}

/// 用公钥校验签名。
public enum SignatureVerifier {
    public static func isValid(signature: Data, for data: Data, publicKey: Data) -> Bool {
        guard
            let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
            let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return false }
        return key.isValidSignature(sig, for: data)
    }

    /// 公钥的短指纹（SHA-256 前 8 字节的十六进制），用于界面展示和日志，不用于安全判断。
    public static func fingerprint(of publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
