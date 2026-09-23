import Foundation

/// 签名消息的类型标签。签名覆盖这个标签，一种消息的签名不能冒充另一种。
public enum MessageKind: String, Codable, Sendable {
    case pairingRequest
    case pairingAccept
    case proximityReport
    case remoteCommand
}

/// 需要签名传输的消息。
public protocol SignedMessage: Codable, Sendable {
    static var kind: MessageKind { get }
}

/// Mac 上显示的配对二维码内容。
public struct PairingInvite: Codable, Equatable, Sendable {
    public static let urlScheme = "nearguard"

    public var protocolVersion: Int
    public var macID: UUID
    public var macName: String
    /// Mac 的签名公钥（X9.63）。
    public var macPublicKey: Data
    /// 一次性配对码，16 字节随机数，只出现在二维码里。
    public var pairingCode: Data
    public var expiresAt: Date

    public init(macID: UUID, macName: String, macPublicKey: Data, expiresAt: Date, pairingCode: Data? = nil) {
        protocolVersion = GuardKitInfo.protocolVersion
        self.macID = macID
        self.macName = macName
        self.macPublicKey = macPublicKey
        self.pairingCode = pairingCode ?? randomBytes(16)
        self.expiresAt = expiresAt
    }

    /// 编码成二维码里的链接：`nearguard://pair?d=<base64url(JSON)>`。
    public func url() throws -> URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "d", value: try Wire.encode(self).base64URLEncodedString())]
        guard let url = components.url else { throw GuardKitError.malformed }
        return url
    }

    /// 解析二维码链接，并检查版本和有效期。
    public init(url: URL, now: Date) throws {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Self.urlScheme, components.host == "pair",
            let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value,
            let data = Data(base64URLEncoded: encoded)
        else { throw GuardKitError.malformed }
        self = try Wire.decode(PairingInvite.self, from: data)
        guard protocolVersion == GuardKitInfo.protocolVersion else {
            throw GuardKitError.unsupportedVersion(protocolVersion)
        }
        guard now < expiresAt else { throw GuardKitError.expired }
    }
}

/// iPhone → Mac：配对请求，用 iPhone 自己的新私钥签名。
public struct PairingRequest: SignedMessage, Equatable {
    public static let kind = MessageKind.pairingRequest

    public var macID: UUID
    public var deviceID: UUID
    public var deviceName: String
    public var phonePublicKey: Data
    /// `PairingProof.make(...)` 的结果。
    public var proof: Data
    public var issuedAt: Date

    public init(macID: UUID, deviceID: UUID, deviceName: String, phonePublicKey: Data, proof: Data, issuedAt: Date) {
        self.macID = macID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.phonePublicKey = phonePublicKey
        self.proof = proof
        self.issuedAt = issuedAt
    }
}

/// Mac → iPhone：配对成功，用 Mac 私钥签名。iPhone 用二维码里的 Mac 公钥验证。
public struct PairingAccept: SignedMessage, Equatable {
    public static let kind = MessageKind.pairingAccept

    public var macID: UUID
    public var deviceID: UUID
    public var issuedAt: Date

    public init(macID: UUID, deviceID: UUID, issuedAt: Date) {
        self.macID = macID
        self.deviceID = deviceID
        self.issuedAt = issuedAt
    }
}

/// Mac → iPhone：测距挑战，明文，不需要签名。
/// 带上 `macID`，附近有多台 Mac 时 iPhone 能先确认连的是不是自己配对的那台。
public struct Challenge: Codable, Equatable, Sendable {
    public var macID: UUID
    public var nonce: Data
    public var issuedAt: Date

    public init(macID: UUID, nonce: Data, issuedAt: Date) {
        self.macID = macID
        self.nonce = nonce
        self.issuedAt = issuedAt
    }
}

/// iPhone → Mac：测距报告。iPhone 测到的 Mac 信号强度，带上 Mac 的挑战随机数后签名。
public struct ProximityReport: SignedMessage, Equatable {
    public static let kind = MessageKind.proximityReport

    public var macID: UUID
    public var deviceID: UUID
    public var nonce: Data
    /// 平滑后的信号强度（dBm）。
    public var rssi: Int
    public var issuedAt: Date

    public init(macID: UUID, deviceID: UUID, nonce: Data, rssi: Int, issuedAt: Date) {
        self.macID = macID
        self.deviceID = deviceID
        self.nonce = nonce
        self.rssi = rssi
        self.issuedAt = issuedAt
    }
}

/// iPhone → Mac（经 CloudKit）：远程指令。
public struct RemoteCommand: SignedMessage, Equatable {
    public static let kind = MessageKind.remoteCommand

    public enum Action: Codable, Equatable, Sendable {
        /// 立即锁屏并抓拍。
        case lockNow
        /// 确认某次报警是本人操作。
        case confirmItsMe(incidentID: UUID)
    }

    public var macID: UUID
    public var deviceID: UUID
    public var action: Action
    public var nonce: Data
    public var issuedAt: Date

    public init(macID: UUID, deviceID: UUID, action: Action, issuedAt: Date, nonce: Data? = nil) {
        self.macID = macID
        self.deviceID = deviceID
        self.action = action
        self.nonce = nonce ?? randomBytes(16)
        self.issuedAt = issuedAt
    }
}
