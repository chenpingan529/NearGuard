import Foundation

/// Mac 端的测距会话：发挑战、验报告、判定距离。
/// BLE 外设代码只负责收发字节，所有判断都在这里。
public struct MacLinkSession: Sendable {
    public let macID: UUID
    public private(set) var devices: [PairedDevice]
    public private(set) var classifier: ProximityClassifier
    public private(set) var lastReport: ProximityReport?
    public private(set) var lastReportAt: Date?
    private var challenges: ChallengeBook

    public init(
        macID: UUID, devices: [PairedDevice], classifierConfig: ProximityClassifier.Config = .init()
    ) {
        self.macID = macID
        self.devices = devices
        classifier = ProximityClassifier(config: classifierConfig)
        challenges = ChallengeBook(macID: macID)
    }

    public var proximity: ProximityState { classifier.state }

    public mutating func setDevices(_ devices: [PairedDevice]) {
        self.devices = devices
        if devices.isEmpty {
            classifier = ProximityClassifier(config: classifier.config)
            lastReport = nil
            lastReportAt = nil
        }
    }

    /// 生成下一个挑战，返回要发给 iPhone 的字节。
    public mutating func nextChallenge(now: Date) throws -> Data {
        try Wire.encode(challenges.issue(now: now))
    }

    /// 处理 iPhone 写入的测距报告。返回报告本身，以及距离状态的变化（没有变化为 nil）。
    public mutating func receiveReport(_ bytes: Data, now: Date) throws -> (
        report: ProximityReport, change: ProximityState?
    ) {
        let envelope = try SignedEnvelope(serialized: bytes)
        // 先取出 deviceID 找到对应公钥，随后 verifyReport 会用这把公钥完整验签。
        let claimed = try envelope.openUnverified(ProximityReport.self)
        guard let device = devices.first(where: { $0.deviceID == claimed.deviceID }) else {
            throw GuardKitError.unknownDevice
        }
        let report = try device.verifyReport(envelope, macID: macID, challenges: &challenges, now: now)
        lastReport = report
        lastReportAt = now
        return (report, classifier.observe(rssi: Double(report.rssi), at: now))
    }

    /// 定时调用（建议每秒一次），检查报告是否超时。
    public mutating func tick(now: Date) -> ProximityState? {
        classifier.tick(now: now)
    }

    /// iPhone 取消订阅（通常意味着断开连接）。
    public mutating func linkLost() -> ProximityState? {
        classifier.markLost()
    }
}
