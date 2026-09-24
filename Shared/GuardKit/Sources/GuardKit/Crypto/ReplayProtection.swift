import Foundation

/// Mac 端的挑战簿：给 iPhone 发一次性随机数，iPhone 签名后回传，每个随机数只能用一次。
/// 用于 BLE 上的测距报告，保证签名是「刚刚」产生的。
public struct ChallengeBook: Sendable {
    public let macID: UUID
    public let lifetime: TimeInterval
    public let capacity: Int
    private var outstanding: [Data: Date] = [:]

    public init(macID: UUID, lifetime: TimeInterval = 10, capacity: Int = 8) {
        self.macID = macID
        self.lifetime = lifetime
        self.capacity = capacity
    }

    public var outstandingCount: Int { outstanding.count }

    /// 生成新的挑战。超过容量时丢弃最早过期的那个，防止无限增长。
    public mutating func issue(now: Date) -> Challenge {
        prune(now: now)
        if outstanding.count >= capacity, let oldest = outstanding.min(by: { $0.value < $1.value }) {
            outstanding.removeValue(forKey: oldest.key)
        }
        let challenge = Challenge(macID: macID, nonce: randomBytes(16), issuedAt: now)
        outstanding[challenge.nonce] = now.addingTimeInterval(lifetime)
        return challenge
    }

    /// 核销挑战。成功后这个随机数立即作废。
    public mutating func consume(_ nonce: Data, now: Date) throws {
        prune(now: now)
        guard outstanding.removeValue(forKey: nonce) != nil else {
            throw GuardKitError.unknownChallenge
        }
    }

    private mutating func prune(now: Date) {
        outstanding = outstanding.filter { $0.value > now }
    }
}

/// 基于「时间戳 + 随机数」的防重放。
/// 用于 CloudKit 远程指令这类无法做挑战应答的场景：时间窗口外的拒绝，窗口内重复的拒绝。
public struct ReplayGuard: Sendable {
    public let window: TimeInterval
    private var seen: [Data: Date] = [:]

    public init(window: TimeInterval = 120) {
        self.window = window
    }

    public mutating func check(nonce: Data, issuedAt: Date, now: Date) throws {
        seen = seen.filter { now.timeIntervalSince($0.value) <= window }
        guard abs(now.timeIntervalSince(issuedAt)) <= window else { throw GuardKitError.expired }
        guard seen[nonce] == nil else { throw GuardKitError.replayed }
        seen[nonce] = issuedAt
    }
}
