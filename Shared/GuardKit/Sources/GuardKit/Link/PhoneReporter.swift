import Foundation

/// iPhone 端的测距报告生成器：校验挑战来自已配对的 Mac，平滑信号强度，签名。
public struct PhoneReporter: Sendable {
    public let macID: UUID
    public let deviceID: UUID
    private let signer: any Signer
    private var filter: RSSIFilter

    public init(macID: UUID, deviceID: UUID, signer: any Signer, filterConfig: RSSIFilter.Config = .init()) {
        self.macID = macID
        self.deviceID = deviceID
        self.signer = signer
        filter = RSSIFilter(config: filterConfig)
    }

    /// 最近一次平滑后的信号强度。
    public var smoothedRSSI: Double? { filter.value }

    /// 解析 Mac 发来的挑战，确认是已配对的 Mac。
    public func parseChallenge(_ bytes: Data) throws -> Challenge {
        let challenge = try Wire.decode(Challenge.self, from: bytes)
        guard challenge.macID == macID else { throw GuardKitError.wrongPeer }
        return challenge
    }

    /// 记录一次原始信号强度（无效值会被忽略）。
    public mutating func record(rssi: Int) {
        filter.add(rssi)
    }

    /// 针对挑战生成签名报告，返回要写给 Mac 的字节。
    public func respond(to challenge: Challenge, now: Date) throws -> Data {
        guard challenge.macID == macID else { throw GuardKitError.wrongPeer }
        guard let rssi = filter.value else { throw GuardKitError.noSignal }
        let report = ProximityReport(
            macID: macID, deviceID: deviceID, nonce: challenge.nonce, rssi: Int(rssi.rounded()), issuedAt: now)
        return try SignedEnvelope.seal(report, with: signer).serialized()
    }

    /// 连接断开后调用，避免用旧的平滑值。
    public mutating func reset() {
        filter.reset()
    }
}
