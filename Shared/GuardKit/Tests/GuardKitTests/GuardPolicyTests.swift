import Foundation
import Testing

@testable import GuardKit

/// 固定的 ID 序列，方便断言。
final class IDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = 0

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }
}

/// 状态机测试台：用相对秒数驱动时间。
struct Harness {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var policy: GuardPolicy

    init(config: GuardConfig = GuardConfig(), screenLocked: Bool = false, calendar: Calendar = .gmt) {
        let ids = IDSequence()
        policy = GuardPolicy(config: config, screenLocked: screenLocked, calendar: calendar, makeID: { ids.next() })
    }

    @discardableResult
    mutating func send(_ event: GuardEvent, at seconds: TimeInterval) -> [GuardAction] {
        policy.handle(event, at: Self.t0 + seconds)
    }

    var state: GuardState { policy.state }
}

extension Calendar {
    static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()
}

@Suite("警戒状态机：自动锁屏 / 解锁")
struct AutoLockUnlockTests {
    @Test func 手机离开时自动锁屏() {
        var h = Harness()
        h.send(.proximityChanged(.near), at: 0)
        #expect(h.send(.proximityChanged(.far), at: 10) == [.lockScreen])
    }

    @Test func 手机不在身边时解锁不会被反复锁上() {
        var h = Harness()
        h.send(.proximityChanged(.far), at: 0)
        #expect(h.send(.proximityChanged(.absent), at: 5).isEmpty)
    }

    @Test func 手机靠近时自动解锁() {
        var h = Harness(screenLocked: true)
        h.send(.proximityChanged(.far), at: 0)
        #expect(h.send(.proximityChanged(.near), at: 5) == [.unlockScreen])
    }

    @Test func 关闭自动锁屏和解锁() {
        var config = GuardConfig()
        config.autoLockEnabled = false
        config.autoUnlockEnabled = false
        var h = Harness(config: config)
        h.send(.proximityChanged(.near), at: 0)
        #expect(h.send(.proximityChanged(.far), at: 1).isEmpty)
        h.send(.screenLocked, at: 2)
        #expect(h.send(.proximityChanged(.near), at: 3).isEmpty)
    }

    @Test func 手机在身边时手动锁屏不会被立即解开() {
        var h = Harness()
        h.send(.proximityChanged(.near), at: 0)
        h.send(.screenLocked, at: 5)
        // 信号抖动导致 near → far → near，但只要离开过一次就重新允许
        #expect(h.state.unlockEligible == false)
        h.send(.proximityChanged(.far), at: 10)
        #expect(h.send(.proximityChanged(.near), at: 12) == [.unlockScreen])
    }

    @Test func 定时警戒期间不自动解锁() {
        var config = GuardConfig()
        config.schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: Set(1...7), start: 0, end: 0)])
        var h = Harness(config: config, screenLocked: true)
        h.send(.proximityChanged(.far), at: 0)
        #expect(!h.send(.proximityChanged(.near), at: 5).contains(.unlockScreen))
    }

    @Test func 手动警戒期间不自动解锁() {
        var h = Harness(screenLocked: true)
        h.send(.setManualArm(true), at: 0)
        #expect(!h.send(.proximityChanged(.near), at: 1).contains(.unlockScreen))
    }
}

@Suite("警戒状态机：进入 / 解除警戒")
struct ArmingTests {
    @Test func 手机离开满30秒进入警戒() {
        var h = Harness()
        h.send(.proximityChanged(.near), at: 0)
        h.send(.proximityChanged(.far), at: 10)
        #expect(h.send(.tick, at: 39).isEmpty)
        #expect(h.send(.tick, at: 40) == [.armedChanged([.away])])
    }

    @Test func 从远到不在不重置离开计时() {
        var h = Harness()
        h.send(.proximityChanged(.far), at: 0)
        h.send(.proximityChanged(.absent), at: 20)
        #expect(h.send(.tick, at: 30) == [.armedChanged([.away])])
    }

    @Test func 手机回来解除离开警戒() {
        var h = Harness(screenLocked: true)
        h.send(.proximityChanged(.absent), at: 0)
        h.send(.tick, at: 30)
        #expect(h.send(.proximityChanged(.near), at: 60) == [.unlockScreen, .armedChanged([])])
    }

    @Test func 手动警戒开关() {
        var h = Harness()
        #expect(h.send(.setManualArm(true), at: 0) == [.armedChanged([.manual])])
        #expect(h.send(.setManualArm(false), at: 1) == [.armedChanged([])])
    }

    @Test func 定时警戒按时间段生效() {
        var config = GuardConfig()
        // 1_800_000_000 = 2027-01-15 08:00 GMT（周五）。时间段 08:00-09:00。
        config.schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [6], start: 480, end: 540)])
        var h = Harness(config: config)
        #expect(h.send(.tick, at: 0) == [.armedChanged([.schedule])])
        #expect(h.send(.tick, at: 3599).isEmpty)
        #expect(h.send(.tick, at: 3600) == [.armedChanged([])])
    }
}

@Suite("警戒状态机：抓拍与报警")
struct IncidentTests {
    /// 手机已离开并进入警戒、屏幕已锁定的测试台。
    static func armedAndLocked() -> Harness {
        var h = Harness()
        h.send(.proximityChanged(.near), at: 0)
        h.send(.proximityChanged(.far), at: 1)
        h.send(.screenLocked, at: 1)
        h.send(.tick, at: 31)
        return h
    }

    @Test func 警戒中有人操作立即抓拍() {
        var h = Self.armedAndLocked()
        #expect(h.send(.activity(.input), at: 40) == [.capturePhoto(incidentID: IDSequence.id(1), reason: .activity)])
        #expect(h.state.incident?.deadline == Harness.t0 + 60)
    }

    @Test func 未警戒时操作不抓拍() {
        var h = Harness(screenLocked: true)
        #expect(h.send(.activity(.input), at: 10).isEmpty)
    }

    @Test func 锁屏宽限期内的输入被忽略() {
        var h = Harness()
        h.send(.setManualArm(true), at: 0)
        h.send(.screenLocked, at: 10)
        #expect(h.send(.activity(.input), at: 12.9).isEmpty)
        #expect(!h.send(.activity(.input), at: 13).isEmpty)
    }

    @Test func 观察期内同一事件只拍一张() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(h.send(.activity(.lidOpened), at: 45).isEmpty)
    }

    @Test func 观察期结束未自证则上报() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(h.send(.tick, at: 59).isEmpty)
        #expect(h.send(.tick, at: 60) == [.reportIncident(IDSequence.id(1))])
        #expect(h.state.incident == nil)
    }

    @Test func 观察期内TouchID自证则撤销() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(h.send(.ownerVerified, at: 50) == [.discardIncident(IDSequence.id(1), .ownerVerified)])
        #expect(h.send(.tick, at: 70).isEmpty)
    }

    @Test func 警戒中解锁会补拍() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(
            h.send(.screenUnlocked, at: 45) == [
                .capturePhoto(incidentID: IDSequence.id(1), reason: .unlockedWhileArmed)
            ])
    }

    @Test func 警戒中直接解锁开始新事件() {
        var h = Self.armedAndLocked()
        #expect(
            h.send(.screenUnlocked, at: 45) == [
                .capturePhoto(incidentID: IDSequence.id(1), reason: .unlockedWhileArmed)
            ])
        #expect(h.state.incident != nil)
    }

    @Test func 手机回来撤销观察中的事件并解锁() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(
            h.send(.proximityChanged(.near), at: 42) == [
                .discardIncident(IDSequence.id(1), .ownerNearby), .unlockScreen, .armedChanged([]),
            ])
    }

    @Test func 上报后冷却期内不再报警() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        h.send(.tick, at: 60)
        #expect(h.send(.activity(.input), at: 100).isEmpty)
        #expect(h.send(.activity(.input), at: 120) == [.capturePhoto(incidentID: IDSequence.id(2), reason: .activity)])
    }

    @Test func 手机确认是本人则撤销() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(h.send(.remote(.confirmItsMe(incidentID: UUID())), at: 45).isEmpty, "ID 不匹配时忽略")
        #expect(
            h.send(.remote(.confirmItsMe(incidentID: IDSequence.id(1))), at: 46) == [
                .discardIncident(IDSequence.id(1), .remoteConfirmed)
            ])
    }

    @Test func 远程锁定会锁屏并抓拍() {
        var h = Harness()
        #expect(
            h.send(.remote(.lockNow), at: 0) == [
                .lockScreen, .capturePhoto(incidentID: IDSequence.id(1), reason: .remoteLock),
            ])
        #expect(h.state.unlockEligible == false)
    }

    @Test func 远程锁定时有观察中事件则立即上报() {
        var h = Self.armedAndLocked()
        h.send(.activity(.input), at: 40)
        #expect(
            h.send(.remote(.lockNow), at: 41) == [
                .capturePhoto(incidentID: IDSequence.id(1), reason: .remoteLock), .reportIncident(IDSequence.id(1)),
            ])
    }
}

@Suite("定时警戒时间段")
struct GuardScheduleTests {
    /// 2027-01-15 是周五（weekday = 6）。
    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.gmt.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    @Test func 未启用时总是不在时间段内() {
        let schedule = GuardSchedule(isEnabled: false, windows: [.init(weekdays: Set(1...7), start: 0, end: 0)])
        #expect(!schedule.contains(date(day: 15, hour: 12), calendar: .gmt))
    }

    @Test func 当天时间段包含开始不包含结束() {
        let schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [6], start: 540, end: 1080)])
        #expect(!schedule.contains(date(day: 15, hour: 8, minute: 59), calendar: .gmt))
        #expect(schedule.contains(date(day: 15, hour: 9), calendar: .gmt))
        #expect(!schedule.contains(date(day: 15, hour: 18), calendar: .gmt))
        #expect(!schedule.contains(date(day: 16, hour: 12), calendar: .gmt), "周六不生效")
    }

    @Test func 跨夜时间段延续到第二天() {
        // 周五 22:00 到周六 07:00
        let schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [6], start: 1320, end: 420)])
        #expect(schedule.contains(date(day: 15, hour: 23), calendar: .gmt))
        #expect(schedule.contains(date(day: 16, hour: 6, minute: 59), calendar: .gmt))
        #expect(!schedule.contains(date(day: 16, hour: 7), calendar: .gmt))
        #expect(!schedule.contains(date(day: 15, hour: 3), calendar: .gmt), "周四没有设置，周五凌晨不生效")
    }

    @Test func 跨周日到周一() {
        // 周六（7）22:00 开始，跨到周日（1）
        let schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [7], start: 1320, end: 420)])
        #expect(schedule.contains(date(day: 17, hour: 2), calendar: .gmt))
        // 周日（1）22:00 开始，跨到周一（2）
        let sunday = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [1], start: 1320, end: 420)])
        #expect(sunday.contains(date(day: 18, hour: 2), calendar: .gmt))
    }

    @Test func 设置可以编码保存() throws {
        var config = GuardConfig()
        config.schedule = GuardSchedule(isEnabled: true, windows: [.init(weekdays: [2, 3], start: 60, end: 120)])
        let data = try Wire.encode(config)
        #expect(try Wire.decode(GuardConfig.self, from: data) == config)
    }
}
