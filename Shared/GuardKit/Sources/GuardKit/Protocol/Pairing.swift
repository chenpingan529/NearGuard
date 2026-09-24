import Foundation

/// 已配对的 iPhone，Mac 端持久化保存。
public struct PairedDevice: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var name: String
    public var publicKey: Data
    public var pairedAt: Date

    public init(deviceID: UUID, name: String, publicKey: Data, pairedAt: Date) {
        self.deviceID = deviceID
        self.name = name
        self.publicKey = publicKey
        self.pairedAt = pairedAt
    }

    /// 校验 BLE 测距报告：签名、目标 Mac、设备、挑战随机数（一次性）。
    public func verifyReport(
        _ envelope: SignedEnvelope, macID: UUID, challenges: inout ChallengeBook, now: Date
    ) throws -> ProximityReport {
        let report = try envelope.open(ProximityReport.self, publicKey: publicKey)
        guard report.macID == macID, report.deviceID == deviceID else { throw GuardKitError.malformed }
        try challenges.consume(report.nonce, now: now)
        return report
    }

    /// 校验 CloudKit 远程指令：签名、目标 Mac、设备、时间窗口和随机数（防重放）。
    public func verifyCommand(
        _ envelope: SignedEnvelope, macID: UUID, replay: inout ReplayGuard, now: Date
    ) throws -> RemoteCommand {
        let command = try envelope.open(RemoteCommand.self, publicKey: publicKey)
        guard command.macID == macID, command.deviceID == deviceID else { throw GuardKitError.malformed }
        try replay.check(nonce: command.nonce, issuedAt: command.issuedAt, now: now)
        return command
    }
}

/// 配对流程两端的逻辑。
public enum Pairing {
    /// 配对请求时间戳允许的最大偏差。
    public static let maxClockSkew: TimeInterval = 120
    /// 设备名最长字符数，保证配对请求能放进一次 BLE 写入（512 字节）。
    public static let maxDeviceNameLength = 32

    /// iPhone 端：扫码后生成配对请求。
    public static func makeRequest(
        invite: PairingInvite, deviceID: UUID, deviceName: String, signer: some Signer, now: Date
    ) throws -> SignedEnvelope {
        let proof = PairingProof.make(
            pairingCode: invite.pairingCode, phonePublicKey: signer.publicKey,
            macID: invite.macID, deviceID: deviceID
        )
        let request = PairingRequest(
            macID: invite.macID, deviceID: deviceID, deviceName: String(deviceName.prefix(maxDeviceNameLength)),
            phonePublicKey: signer.publicKey, proof: proof, issuedAt: now
        )
        return try SignedEnvelope.seal(request, with: signer)
    }

    /// Mac 端：校验配对请求。依次检查：二维码有效期、目标 Mac、请求自签名、配对证明、时间戳。
    public static func verifyRequest(
        _ envelope: SignedEnvelope, invite: PairingInvite, now: Date
    ) throws -> PairedDevice {
        guard now < invite.expiresAt else { throw GuardKitError.expired }
        let unverified = try envelope.openUnverified(PairingRequest.self)
        let request = try envelope.open(PairingRequest.self, publicKey: unverified.phonePublicKey)
        guard request.macID == invite.macID else { throw GuardKitError.malformed }
        guard
            PairingProof.isValid(
                request.proof, pairingCode: invite.pairingCode, phonePublicKey: request.phonePublicKey,
                macID: request.macID, deviceID: request.deviceID
            )
        else { throw GuardKitError.pairingProofMismatch }
        guard abs(now.timeIntervalSince(request.issuedAt)) <= maxClockSkew else { throw GuardKitError.expired }
        return PairedDevice(
            deviceID: request.deviceID, name: request.deviceName,
            publicKey: request.phonePublicKey, pairedAt: now
        )
    }

    /// Mac 端：生成配对成功回执。
    public static func makeAccept(device: PairedDevice, macID: UUID, signer: some Signer, now: Date) throws
        -> SignedEnvelope
    {
        try SignedEnvelope.seal(PairingAccept(macID: macID, deviceID: device.deviceID, issuedAt: now), with: signer)
    }

    /// iPhone 端：用二维码里的 Mac 公钥校验回执。
    public static func verifyAccept(_ envelope: SignedEnvelope, invite: PairingInvite, deviceID: UUID) throws {
        let accept = try envelope.open(PairingAccept.self, publicKey: invite.macPublicKey)
        guard accept.macID == invite.macID, accept.deviceID == deviceID else { throw GuardKitError.malformed }
    }
}
