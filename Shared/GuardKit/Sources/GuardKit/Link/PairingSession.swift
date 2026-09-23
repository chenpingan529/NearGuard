import Foundation

/// Mac 端的配对会话：管理二维码的生命周期。
/// 同一时间只有一个有效二维码；生成新码会作废旧码；配对成功一次后立即作废。
public struct PairingSession: Sendable {
    public static let defaultLifetime: TimeInterval = 300

    public private(set) var invite: PairingInvite?

    public init() {}

    public func isActive(now: Date) -> Bool {
        guard let invite else { return false }
        return now < invite.expiresAt
    }

    /// 生成新的二维码邀请。
    public mutating func start(
        macID: UUID, macName: String, macPublicKey: Data, now: Date, lifetime: TimeInterval = defaultLifetime
    ) -> PairingInvite {
        let invite = PairingInvite(
            macID: macID, macName: macName, macPublicKey: macPublicKey, expiresAt: now.addingTimeInterval(lifetime))
        self.invite = invite
        return invite
    }

    /// 校验配对请求。成功后二维码作废，返回新配对的设备。失败不作废，允许重试。
    public mutating func complete(_ envelope: SignedEnvelope, now: Date) throws -> PairedDevice {
        guard let invite else { throw GuardKitError.noActivePairing }
        let device = try Pairing.verifyRequest(envelope, invite: invite, now: now)
        self.invite = nil
        return device
    }

    public mutating func cancel() {
        invite = nil
    }
}
