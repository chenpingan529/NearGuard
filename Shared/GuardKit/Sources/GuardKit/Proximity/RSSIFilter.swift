import Foundation

/// 信号强度平滑：先丢掉无效值，再对最近几个样本取中位数去掉尖刺，最后做指数平滑。
public struct RSSIFilter: Sendable {
    public struct Config: Equatable, Sendable {
        /// 中位数窗口大小。
        public var windowSize = 5
        /// 指数平滑系数，越大越跟手，越小越稳。
        public var alpha = 0.3
        /// 有效范围。CoreBluetooth 用 127 表示读不到，0 也是异常值。
        public var validRange: ClosedRange<Int> = -100 ... -20

        public init() {}
    }

    public let config: Config
    private var window: [Int] = []
    public private(set) var value: Double?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// 加入一个原始样本，返回平滑后的值。无效样本被忽略，返回当前值。
    @discardableResult
    public mutating func add(_ rssi: Int) -> Double? {
        guard config.validRange.contains(rssi) else { return value }
        window.append(rssi)
        if window.count > config.windowSize { window.removeFirst(window.count - config.windowSize) }
        let median = Double(window.sorted()[window.count / 2])
        if let current = value {
            value = current + config.alpha * (median - current)
        } else {
            value = median
        }
        return value
    }

    public mutating func reset() {
        window.removeAll()
        value = nil
    }
}
