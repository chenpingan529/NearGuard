import Foundation

/// 手机相对 Mac 的距离状态。
public enum ProximityState: String, Codable, Sendable {
    /// 刚启动，还没有数据。
    case unknown
    /// 在身边。
    case near
    /// 能连上，但离得比较远。
    case far
    /// 连接断开或长时间没有报告。
    case absent
}

/// 把平滑后的信号强度转成距离状态。
///
/// - 两个阈值之间是回差区：保持当前状态，避免在临界距离来回跳。
/// - 新状态要持续一段时间（驻留时间）才生效，偶发的信号波动不会触发锁屏或解锁。
/// - 超过 `absentTimeout` 没有报告，或连接断开，判定为 `absent`。
public struct ProximityClassifier: Sendable {
    public struct Config: Equatable, Sendable {
        /// 大于等于这个值算靠近（dBm）。
        public var nearThreshold = -62.0
        /// 小于等于这个值算离开（dBm）。
        public var farThreshold = -75.0
        /// 变成 near 需要持续的时间。
        public var nearDwell: TimeInterval = 1.5
        /// 从 near 变成 far 需要持续的时间。
        public var farDwell: TimeInterval = 4
        /// 多久没有报告算 absent。
        public var absentTimeout: TimeInterval = 10

        public init() {}
    }

    public let config: Config
    public private(set) var state: ProximityState = .unknown
    private var candidate: (state: ProximityState, since: Date)?
    private var lastSampleAt: Date?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// 输入一个平滑后的样本。状态发生变化时返回新状态。
    public mutating func observe(rssi: Double, at now: Date) -> ProximityState? {
        lastSampleAt = now
        let target = zone(for: rssi)
        guard target != state else {
            candidate = nil
            return nil
        }
        // 从「没数据 / 断开」恢复到 far 不需要等待：能收到信号本身就说明设备在范围内。
        if target == .far, state == .unknown || state == .absent {
            return transition(to: .far)
        }
        if let candidate, candidate.state == target {
            let dwell = target == .near ? config.nearDwell : config.farDwell
            if now.timeIntervalSince(candidate.since) >= dwell {
                return transition(to: target)
            }
        } else {
            candidate = (target, now)
        }
        return nil
    }

    /// 定时调用，检查是否超时没有报告。
    public mutating func tick(now: Date) -> ProximityState? {
        guard state != .absent, let lastSampleAt, now.timeIntervalSince(lastSampleAt) >= config.absentTimeout else {
            return nil
        }
        return transition(to: .absent)
    }

    /// 连接断开时调用，立即判定为 absent。
    public mutating func markLost() -> ProximityState? {
        guard state != .absent else { return nil }
        return transition(to: .absent)
    }

    private func zone(for rssi: Double) -> ProximityState {
        if rssi >= config.nearThreshold { return .near }
        if rssi <= config.farThreshold { return .far }
        // 回差区：已经 near 就保持 near，其余情况都算 far。
        return state == .near ? .near : .far
    }

    private mutating func transition(to newState: ProximityState) -> ProximityState {
        state = newState
        candidate = nil
        return newState
    }
}
