import Foundation
import Testing

@testable import GuardKit

@Suite("配对流程")
struct PairingTests {
    let mac = SoftwareSigner()
    let phone = SoftwareSigner()
    let macID = UUID()
    let deviceID = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var invite: PairingInvite {
        PairingInvite(macID: macID, macName: "测试 Mac", macPublicKey: mac.publicKey, expiresAt: now + 300)
    }

    @Test func 二维码链接往返一致() throws {
        let invite = invite
        let url = try invite.url()
        #expect(url.scheme == "nearguard")
        #expect(url.absoluteString.count < 400, "二维码内容越短越容易扫")
        #expect(try PairingInvite(url: url, now: now) == invite)
    }

    @Test func 过期二维码被拒绝() throws {
        let url = try invite.url()
        #expect(throws: GuardKitError.expired) { try PairingInvite(url: url, now: now + 301) }
    }

    @Test func 非本应用链接被拒绝() {
        #expect(throws: GuardKitError.malformed) {
            try PairingInvite(url: URL(string: "https://example.com/pair?d=abc")!, now: now)
        }
    }

    @Test func 完整配对成功() throws {
        let invite = invite
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: deviceID, deviceName: "iPhone", signer: phone, now: now)
        let device = try Pairing.verifyRequest(request, invite: invite, now: now + 1)
        #expect(device.deviceID == deviceID)
        #expect(device.publicKey == phone.publicKey)

        let accept = try Pairing.makeAccept(device: device, macID: macID, signer: mac, now: now + 1)
        try Pairing.verifyAccept(accept, invite: invite, deviceID: deviceID)
    }

    @Test func 不知道配对码无法配对() throws {
        let invite = invite
        var forged = invite
        forged.pairingCode = Data(repeating: 0, count: 16)
        let request = try Pairing.makeRequest(
            invite: forged, deviceID: deviceID, deviceName: "攻击者", signer: SoftwareSigner(), now: now)
        #expect(throws: GuardKitError.pairingProofMismatch) {
            try Pairing.verifyRequest(request, invite: invite, now: now)
        }
    }

    @Test func 替换请求里的公钥会导致验签失败() throws {
        let invite = invite
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: deviceID, deviceName: "iPhone", signer: phone, now: now)
        // 中间人把载荷里的公钥换成自己的：原签名对不上。
        var message = try request.openUnverified(PairingRequest.self)
        message.phonePublicKey = SoftwareSigner().publicKey
        let resealed = try SignedEnvelope.seal(message, with: phone)
        #expect(throws: GuardKitError.badSignature) {
            try Pairing.verifyRequest(resealed, invite: invite, now: now)
        }
    }

    @Test func 伪造的配对回执被拒绝() throws {
        let fakeAccept = try SignedEnvelope.seal(
            PairingAccept(macID: macID, deviceID: deviceID, issuedAt: now), with: SoftwareSigner())
        #expect(throws: GuardKitError.badSignature) {
            try Pairing.verifyAccept(fakeAccept, invite: invite, deviceID: deviceID)
        }
    }

    @Test func 测距报告校验() throws {
        let device = PairedDevice(deviceID: deviceID, name: "iPhone", publicKey: phone.publicKey, pairedAt: now)
        var book = ChallengeBook(macID: macID)
        let challenge = book.issue(now: now)
        let report = ProximityReport(macID: macID, deviceID: deviceID, nonce: challenge.nonce, rssi: -50, issuedAt: now)
        let envelope = try SignedEnvelope.seal(report, with: phone)

        #expect(try device.verifyReport(envelope, macID: macID, challenges: &book, now: now + 1) == report)
        // 同一份报告重放
        #expect(throws: GuardKitError.unknownChallenge) {
            try device.verifyReport(envelope, macID: macID, challenges: &book, now: now + 2)
        }
    }

    @Test func 发给别的Mac的报告被拒绝() throws {
        let device = PairedDevice(deviceID: deviceID, name: "iPhone", publicKey: phone.publicKey, pairedAt: now)
        var book = ChallengeBook(macID: macID)
        let challenge = book.issue(now: now)
        let report = ProximityReport(
            macID: UUID(), deviceID: deviceID, nonce: challenge.nonce, rssi: -50, issuedAt: now)
        let envelope = try SignedEnvelope.seal(report, with: phone)
        #expect(throws: GuardKitError.malformed) {
            try device.verifyReport(envelope, macID: macID, challenges: &book, now: now)
        }
    }

    @Test func 远程指令校验与防重放() throws {
        let device = PairedDevice(deviceID: deviceID, name: "iPhone", publicKey: phone.publicKey, pairedAt: now)
        var replay = ReplayGuard()
        let command = RemoteCommand(
            macID: macID, deviceID: deviceID, action: .confirmItsMe(incidentID: UUID()), issuedAt: now)
        let envelope = try SignedEnvelope.seal(command, with: phone)

        #expect(try device.verifyCommand(envelope, macID: macID, replay: &replay, now: now + 5) == command)
        #expect(throws: GuardKitError.replayed) {
            try device.verifyCommand(envelope, macID: macID, replay: &replay, now: now + 6)
        }
    }

    @Test func 配对证明对每个字段都敏感() {
        let code = Data(repeating: 7, count: 16)
        let proof = PairingProof.make(
            pairingCode: code, phonePublicKey: phone.publicKey, macID: macID, deviceID: deviceID)
        #expect(
            PairingProof.isValid(
                proof, pairingCode: code, phonePublicKey: phone.publicKey, macID: macID, deviceID: deviceID))
        #expect(
            !PairingProof.isValid(
                proof, pairingCode: code, phonePublicKey: phone.publicKey, macID: UUID(), deviceID: deviceID))
        #expect(
            !PairingProof.isValid(
                proof, pairingCode: code, phonePublicKey: phone.publicKey, macID: macID, deviceID: UUID()))
        #expect(
            !PairingProof.isValid(
                proof, pairingCode: code, phonePublicKey: mac.publicKey, macID: macID, deviceID: deviceID))
    }
}
