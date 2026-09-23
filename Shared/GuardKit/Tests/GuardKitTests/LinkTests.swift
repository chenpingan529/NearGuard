import Foundation
import Testing

@testable import GuardKit

@Suite("BLE 分段读写")
struct ATTTests {
    @Test func 乱序分段按偏移拼接() throws {
        let parts: [(offset: Int, value: Data)] = [(3, Data([4, 5])), (0, Data([1, 2, 3]))]
        #expect(try ATT.assemble(parts) == Data([1, 2, 3, 4, 5]))
    }

    @Test func 单段写入() throws {
        #expect(try ATT.assemble([(0, Data([9]))]) == Data([9]))
    }

    @Test func 有缺口被拒绝() {
        #expect(throws: GuardKitError.malformed) { try ATT.assemble([(0, Data([1])), (2, Data([3]))]) }
    }

    @Test func 不从零开始被拒绝() {
        #expect(throws: GuardKitError.malformed) { try ATT.assemble([(1, Data([1]))]) }
    }

    @Test func 重叠被拒绝() {
        #expect(throws: GuardKitError.malformed) { try ATT.assemble([(0, Data([1, 2])), (1, Data([3]))]) }
    }

    @Test func 空数据和超长被拒绝() {
        #expect(throws: GuardKitError.malformed) { try ATT.assemble([]) }
        #expect(throws: GuardKitError.malformed) { try ATT.assemble([(0, Data(count: 513))]) }
    }

    @Test func 长读取按偏移切片() {
        let value = Data([1, 2, 3])
        #expect(ATT.slice(value, offset: 0) == value)
        #expect(ATT.slice(value, offset: 2) == Data([3]))
        #expect(ATT.slice(value, offset: 3) == Data())
        #expect(ATT.slice(value, offset: 4) == nil)
        #expect(ATT.slice(value.dropFirst(), offset: 1) == Data([3]), "切片数据的下标不从 0 开始")
    }
}

@Suite("配对会话")
struct PairingSessionTests {
    let mac = SoftwareSigner()
    let phone = SoftwareSigner()
    let macID = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func 配对成功后二维码作废() throws {
        var session = PairingSession()
        let invite = session.start(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, now: now)
        #expect(session.isActive(now: now))
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: UUID(), deviceName: "iPhone", signer: phone, now: now)
        _ = try session.complete(request, now: now + 1)
        #expect(!session.isActive(now: now + 1))
        #expect(throws: GuardKitError.noActivePairing) { try session.complete(request, now: now + 2) }
    }

    @Test func 新码作废旧码() throws {
        var session = PairingSession()
        let old = session.start(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, now: now)
        _ = session.start(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, now: now + 10)
        let request = try Pairing.makeRequest(
            invite: old, deviceID: UUID(), deviceName: "iPhone", signer: phone, now: now)
        #expect(throws: GuardKitError.pairingProofMismatch) { try session.complete(request, now: now + 11) }
    }

    @Test func 失败不作废允许重试() throws {
        var session = PairingSession()
        let invite = session.start(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, now: now)
        var wrong = invite
        wrong.pairingCode = Data(count: 16)
        let bad = try Pairing.makeRequest(invite: wrong, deviceID: UUID(), deviceName: "x", signer: phone, now: now)
        #expect(throws: GuardKitError.pairingProofMismatch) { try session.complete(bad, now: now) }
        let good = try Pairing.makeRequest(invite: invite, deviceID: UUID(), deviceName: "x", signer: phone, now: now)
        _ = try session.complete(good, now: now)
    }

    @Test func 过期后不能配对() throws {
        var session = PairingSession()
        let invite = session.start(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, now: now, lifetime: 60)
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: UUID(), deviceName: "x", signer: phone, now: now)
        #expect(!session.isActive(now: now + 60))
        #expect(throws: GuardKitError.expired) { try session.complete(request, now: now + 60) }
    }

    @Test func 没有进行中的配对() throws {
        var session = PairingSession()
        let invite = PairingInvite(macID: macID, macName: "Mac", macPublicKey: mac.publicKey, expiresAt: now + 60)
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: UUID(), deviceName: "x", signer: phone, now: now)
        #expect(throws: GuardKitError.noActivePairing) { try session.complete(request, now: now) }
    }

    @Test func 超长设备名被截断且请求能放进一次写入() throws {
        let invite = PairingInvite(
            macID: macID, macName: String(repeating: "长", count: 64), macPublicKey: mac.publicKey, expiresAt: now + 60)
        let request = try Pairing.makeRequest(
            invite: invite, deviceID: UUID(), deviceName: String(repeating: "的", count: 100), signer: phone, now: now)
        #expect(try request.openUnverified(PairingRequest.self).deviceName.count == Pairing.maxDeviceNameLength)
        #expect(request.serialized().count <= ATT.maxAttributeLength)
    }
}

@Suite("测距会话（端到端）")
struct LinkSessionTests {
    let phoneKey = SoftwareSigner()
    let macID = UUID()
    let deviceID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func makePair() -> (MacLinkSession, PhoneReporter) {
        let device = PairedDevice(deviceID: deviceID, name: "iPhone", publicKey: phoneKey.publicKey, pairedAt: t0)
        return (
            MacLinkSession(macID: macID, devices: [device]),
            PhoneReporter(macID: macID, deviceID: deviceID, signer: phoneKey)
        )
    }

    /// 模拟一轮：Mac 发挑战 → iPhone 测信号并回报告 → Mac 验证。
    func round(_ mac: inout MacLinkSession, _ phone: inout PhoneReporter, rssi: Int, at t: Double) throws
        -> ProximityState?
    {
        let now = t0 + t
        let challenge = try phone.parseChallenge(try mac.nextChallenge(now: now))
        phone.record(rssi: rssi)
        return try mac.receiveReport(try phone.respond(to: challenge, now: now), now: now).change
    }

    @Test func 靠近后判定为近() throws {
        var (mac, phone) = makePair()
        var changes: [ProximityState] = []
        for i in 0..<5 {
            if let change = try round(&mac, &phone, rssi: -50, at: Double(i)) { changes.append(change) }
        }
        #expect(changes == [.near])
        #expect(mac.lastReport?.rssi == -50)
    }

    @Test func 报告只能用一次() throws {
        var (mac, phone) = makePair()
        let challenge = try phone.parseChallenge(try mac.nextChallenge(now: t0))
        phone.record(rssi: -50)
        let bytes = try phone.respond(to: challenge, now: t0)
        _ = try mac.receiveReport(bytes, now: t0)
        #expect(throws: GuardKitError.unknownChallenge) { try mac.receiveReport(bytes, now: t0 + 1) }
    }

    @Test func 未配对设备的报告被拒绝() throws {
        var (mac, _) = makePair()
        var stranger = PhoneReporter(macID: macID, deviceID: UUID(), signer: SoftwareSigner())
        let challenge = try stranger.parseChallenge(try mac.nextChallenge(now: t0))
        stranger.record(rssi: -40)
        #expect(throws: GuardKitError.unknownDevice) {
            try mac.receiveReport(try stranger.respond(to: challenge, now: t0), now: t0)
        }
    }

    @Test func 冒用已配对设备ID但私钥不对被拒绝() throws {
        var (mac, _) = makePair()
        var impostor = PhoneReporter(macID: macID, deviceID: deviceID, signer: SoftwareSigner())
        let challenge = try impostor.parseChallenge(try mac.nextChallenge(now: t0))
        impostor.record(rssi: -40)
        #expect(throws: GuardKitError.badSignature) {
            try mac.receiveReport(try impostor.respond(to: challenge, now: t0), now: t0)
        }
    }

    @Test func iPhone拒绝其他Mac的挑战() throws {
        var other = MacLinkSession(macID: UUID(), devices: [])
        let (_, phone) = makePair()
        #expect(throws: GuardKitError.wrongPeer) { try phone.parseChallenge(try other.nextChallenge(now: t0)) }
    }

    @Test func 没有有效信号时不报告() throws {
        var (mac, phone) = makePair()
        let challenge = try phone.parseChallenge(try mac.nextChallenge(now: t0))
        phone.record(rssi: 127)
        #expect(throws: GuardKitError.noSignal) { try phone.respond(to: challenge, now: t0) }
    }

    @Test func 断开与超时判定为不在() throws {
        var (mac, phone) = makePair()
        _ = try round(&mac, &phone, rssi: -80, at: 0)
        #expect(mac.proximity == .far)
        #expect(mac.linkLost() == .absent)

        var (mac2, phone2) = makePair()
        _ = try round(&mac2, &phone2, rssi: -80, at: 0)
        #expect(mac2.tick(now: t0 + 10) == .absent)
    }

    @Test func 解除全部配对后状态清空() throws {
        var (mac, phone) = makePair()
        _ = try round(&mac, &phone, rssi: -80, at: 0)
        mac.setDevices([])
        #expect(mac.proximity == .unknown)
        #expect(mac.lastReport == nil)
    }

    @Test func 挑战能放进一个通知包() throws {
        var (mac, _) = makePair()
        // iPhone 与 Mac 协商的 MTU 通常 ≥ 185，通知最大载荷 = MTU - 3。
        #expect(try mac.nextChallenge(now: t0).count <= 182)
    }

    @Test func 报告能放进一次写入() throws {
        var (mac, phone) = makePair()
        let challenge = try phone.parseChallenge(try mac.nextChallenge(now: t0))
        phone.record(rssi: -50)
        #expect(try phone.respond(to: challenge, now: t0).count <= ATT.maxAttributeLength)
    }
}
