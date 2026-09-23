import Foundation

/// 签名封包。线上格式：
///
///     [1 字节 封包版本][2 字节 载荷长度，大端][载荷 JSON][64 字节 签名]
///
/// 载荷是 `{"k": 消息类型, "b": 消息体}` 的 JSON。签名覆盖整个载荷原始字节，
/// 校验时直接对收到的字节验签，不重新编码，所以不依赖 JSON 的规范化。
public struct SignedEnvelope: Equatable, Sendable {
    public static let formatVersion: UInt8 = 1
    static let signatureLength = 64

    public let payload: Data
    public let signature: Data

    public init(payload: Data, signature: Data) {
        self.payload = payload
        self.signature = signature
    }

    /// 编码并签名。
    public static func seal<M: SignedMessage>(_ message: M, with signer: some Signer) throws -> SignedEnvelope {
        let payload = try Wire.encode(Tagged(k: M.kind, b: message))
        guard payload.count <= 0xFFFF else { throw GuardKitError.malformed }
        return SignedEnvelope(payload: payload, signature: try signer.sign(payload))
    }

    /// 验签并解码。先验签，签名通过后才解析内容。
    public func open<M: SignedMessage>(_ type: M.Type, publicKey: Data) throws -> M {
        guard SignatureVerifier.isValid(signature: signature, for: payload, publicKey: publicKey) else {
            throw GuardKitError.badSignature
        }
        return try Self.decode(type, from: payload)
    }

    /// 只解码不验签。仅用于配对请求：此时还不知道对方公钥，公钥就在消息里，
    /// 必须随后用消息里的公钥验签并检查配对证明，见 `PairingRequest` 的处理流程。
    public func openUnverified<M: SignedMessage>(_ type: M.Type) throws -> M {
        try Self.decode(type, from: payload)
    }

    public func serialized() -> Data {
        var data = Data([Self.formatVersion, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
        data.append(payload)
        data.append(signature)
        return data
    }

    public init(serialized data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count > 3 else { throw GuardKitError.malformed }
        guard bytes[0] == Self.formatVersion else { throw GuardKitError.unsupportedVersion(Int(bytes[0])) }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard bytes.count == 3 + length + Self.signatureLength else { throw GuardKitError.malformed }
        payload = Data(bytes[3..<(3 + length)])
        signature = Data(bytes[(3 + length)...])
    }

    private static func decode<M: SignedMessage>(_ type: M.Type, from payload: Data) throws -> M {
        // 先只解析类型标签，类型不对时给出明确的错误。
        guard try Wire.decode(Header.self, from: payload).k == M.kind else { throw GuardKitError.unexpectedKind }
        return try Wire.decode(Tagged<M>.self, from: payload).b
    }
}

private struct Header: Decodable {
    var k: MessageKind
}

private struct Tagged<M: SignedMessage>: Codable {
    var k: MessageKind
    var b: M
}
