import Foundation
import Testing

@testable import GuardKit

@Suite("信号平滑")
struct RSSIFilterTests {
    @Test func 第一个有效样本直接作为初值() {
        var filter = RSSIFilter()
        #expect(filter.add(-60) == -60)
    }

    @Test(arguments: [127, 0, -101, -5])
    func 无效样本被忽略(rssi: Int) {
        var filter = RSSIFilter()
        filter.add(-60)
        #expect(filter.add(rssi) == -60)
    }

    @Test func 单个尖刺被中位数压掉() {
        var filter = RSSIFilter()
        for _ in 0..<5 { filter.add(-60) }
        #expect(filter.add(-95) == -60)
    }

    @Test func 持续变化会逐渐跟上() {
        var filter = RSSIFilter()
        for _ in 0..<5 { filter.add(-60) }
        var value = -60.0
        for _ in 0..<20 { value = filter.add(-80) ?? value }
        #expect(abs(value - -80) < 1)
    }

    @Test func 重置后清空() {
        var filter = RSSIFilter()
        filter.add(-60)
        filter.reset()
        #expect(filter.value == nil)
    }
}

@Suite("距离判定")
struct ProximityClassifierTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 以 0.5 秒间隔连续输入同一个值，返回最后一次状态变化。
    func feed(_ classifier: inout ProximityClassifier, rssi: Double, from start: Double, seconds: Double)
        -> [ProximityState]
    {
        var changes: [ProximityState] = []
        var t = start
        while t <= start + seconds {
            if let change = classifier.observe(rssi: rssi, at: t0 + t) { changes.append(change) }
            t += 0.5
        }
        return changes
    }

    @Test func 首次收到弱信号立即判定为远() {
        var classifier = ProximityClassifier()
        #expect(classifier.observe(rssi: -80, at: t0) == .far)
    }

    @Test func 靠近需要持续驻留() {
        var classifier = ProximityClassifier()
        _ = classifier.observe(rssi: -80, at: t0)
        #expect(classifier.observe(rssi: -50, at: t0 + 1) == nil)
        #expect(classifier.observe(rssi: -50, at: t0 + 2) == nil)
        #expect(classifier.observe(rssi: -50, at: t0 + 2.5) == .near)
    }

    @Test func 短暂波动不会改变状态() {
        var classifier = ProximityClassifier()
        _ = feed(&classifier, rssi: -50, from: 0, seconds: 3)
        #expect(classifier.state == .near)
        // 离开 2 秒又回来，不到 farDwell（4 秒）
        #expect(feed(&classifier, rssi: -85, from: 3.5, seconds: 2).isEmpty)
        #expect(feed(&classifier, rssi: -50, from: 6, seconds: 1).isEmpty)
        #expect(classifier.state == .near)
    }

    @Test func 回差区保持当前状态() {
        var classifier = ProximityClassifier()
        _ = feed(&classifier, rssi: -50, from: 0, seconds: 3)
        #expect(feed(&classifier, rssi: -70, from: 3.5, seconds: 20).isEmpty)
        #expect(classifier.state == .near)

        var farClassifier = ProximityClassifier()
        _ = farClassifier.observe(rssi: -80, at: t0)
        #expect(feed(&farClassifier, rssi: -70, from: 1, seconds: 20).isEmpty)
        #expect(farClassifier.state == .far)
    }

    @Test func 持续离开后判定为远() {
        var classifier = ProximityClassifier()
        _ = feed(&classifier, rssi: -50, from: 0, seconds: 3)
        #expect(feed(&classifier, rssi: -85, from: 3.5, seconds: 5) == [.far])
    }

    @Test func 超时没有报告判定为不在() {
        var classifier = ProximityClassifier()
        _ = classifier.observe(rssi: -50, at: t0)
        #expect(classifier.tick(now: t0 + 9) == nil)
        #expect(classifier.tick(now: t0 + 10) == .absent)
        #expect(classifier.tick(now: t0 + 11) == nil)
    }

    @Test func 断开立即判定为不在() {
        var classifier = ProximityClassifier()
        _ = classifier.observe(rssi: -50, at: t0)
        #expect(classifier.markLost() == .absent)
        #expect(classifier.markLost() == nil)
    }

    @Test func 没有数据时不会判定为不在() {
        var classifier = ProximityClassifier()
        #expect(classifier.tick(now: t0 + 100) == nil)
    }
}
