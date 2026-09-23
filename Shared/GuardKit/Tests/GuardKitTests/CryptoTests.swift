import Foundation
import Testing

@testable import GuardKit

@Suite("签名与封包")
struct SignedEnvelopeTests {
    let phone = SoftwareSigner()
    let macID = UUID()
    let deviceID = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func report(nonce: Data = Data(repeating: 1, count: 16)) -> ProximityReport {
        ProximityReport(macID: macID, deviceID: deviceID, nonce: nonce, rssi: -55, issuedAt: now)
    }

    @Test func 签名后能用公钥还原() throws {
        let envelope = try SignedEnvelope.seal(report(), with: phone)
        let opened = try envelope.open(ProximityReport.self, publicKey: phone.publicKey)
        #expect(opened == report())
    }

    @Test func 序列化往返一致() throws {
        let envelope = try SignedEnvelope.seal(report(), with: phone)
        let bytes = envelope.serialized()
        #expect(bytes.count < 512, "BLE 单次长写上限 512 字节")
        #expect(try SignedEnvelope(serialized: bytes) == envelope)
    }

    @Test func 换一把公钥验签失败() throws {
        let envelope = try SignedEnvelope.seal(report(), with: phone)
        #expect(throws: GuardKitError.badSignature) {
            try envelope.open(ProximityReport.self, publicKey: SoftwareSigner().publicKey)
        }
    }

    @Test func 篡改载荷验签失败() throws {
        let envelope = try SignedEnvelope.seal(report(), with: phone)
        var payload = envelope.payload
        payload[payload.startIndex + 10] ^= 0x01
        let tampered = SignedEnvelope(payload: payload, signature: envelope.signature)
        #expect(throws: GuardKitError.badSignature) {
            try tampered.open(ProximityReport.self, publicKey: phone.publicKey)
        }
    }

    @Test func 不能把一种消息的签名当另一种用() throws {
        let command = RemoteCommand(macID: macID, deviceID: deviceID, action: .lockNow, issuedAt: now)
        let envelope = try SignedEnvelope.seal(command, with: phone)
        #expect(throws: GuardKitError.unexpectedKind) {
            try envelope.open(ProximityReport.self, publicKey: phone.publicKey)
        }
    }

    @Test(arguments: [Data(), Data([1]), Data([2, 0, 0] + [UInt8](repeating: 0, count: 64))])
    func 畸形数据被拒绝(bytes: Data) {
        #expect(throws: GuardKitError.self) { try SignedEnvelope(serialized: bytes) }
    }

    @Test func 长度字段不匹配被拒绝() throws {
        var bytes = try SignedEnvelope.seal(report(), with: phone).serialized()
        bytes.removeLast()
        #expect(throws: GuardKitError.malformed) { try SignedEnvelope(serialized: bytes) }
    }

    @Test func 软件私钥可以导出再导入() throws {
        let restored = try SoftwareSigner(rawRepresentation: phone.rawRepresentation)
        #expect(restored.publicKey == phone.publicKey)
        #expect(throws: GuardKitError.invalidKey) { try SoftwareSigner(rawRepresentation: Data([1, 2, 3])) }
    }

    @Test func 指纹稳定且为16位十六进制() {
        let fingerprint = SignatureVerifier.fingerprint(of: phone.publicKey)
        #expect(fingerprint.count == 16)
        #expect(fingerprint == SignatureVerifier.fingerprint(of: phone.publicKey))
    }
}

@Suite("防重放")
struct ReplayProtectionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func 挑战只能核销一次() throws {
        var book = ChallengeBook()
        let challenge = book.issue(now: now)
        try book.consume(challenge.nonce, now: now.addingTimeInterval(1))
        #expect(throws: GuardKitError.unknownChallenge) {
            try book.consume(challenge.nonce, now: now.addingTimeInterval(2))
        }
    }

    @Test func 过期挑战被拒绝() {
        var book = ChallengeBook(lifetime: 10)
        let challenge = book.issue(now: now)
        #expect(throws: GuardKitError.unknownChallenge) {
            try book.consume(challenge.nonce, now: now.addingTimeInterval(10))
        }
    }

    @Test func 未签发的挑战被拒绝() {
        var book = ChallengeBook()
        #expect(throws: GuardKitError.unknownChallenge) { try book.consume(Data([9]), now: now) }
    }

    @Test func 挑战数量不超过容量() {
        var book = ChallengeBook(lifetime: 100, capacity: 3)
        for i in 0..<10 { _ = book.issue(now: now.addingTimeInterval(Double(i))) }
        #expect(book.outstandingCount == 3)
    }

    @Test func 时间窗口内重复随机数被拒绝() throws {
        var guardian = ReplayGuard(window: 120)
        let nonce = Data([1, 2, 3])
        try guardian.check(nonce: nonce, issuedAt: now, now: now)
        #expect(throws: GuardKitError.replayed) {
            try guardian.check(nonce: nonce, issuedAt: now, now: now.addingTimeInterval(30))
        }
    }

    @Test(arguments: [-121.0, 121.0])
    func 时间窗口外被拒绝(offset: TimeInterval) {
        var guardian = ReplayGuard(window: 120)
        #expect(throws: GuardKitError.expired) {
            try guardian.check(nonce: Data([1]), issuedAt: now.addingTimeInterval(offset), now: now)
        }
    }
}
