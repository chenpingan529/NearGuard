import Foundation

/// 警戒相关的用户设置。
public struct GuardConfig: Codable, Equatable, Sendable {
    /// 手机靠近时自动解锁。
    public var autoUnlockEnabled = true
    /// 手机离开时自动锁屏。
    public var autoLockEnabled = true
    /// 手机离开多久后进入警戒。
    public var awayArmDelay: TimeInterval = 30
    /// 锁屏后多久内的输入不算「有人操作」（按锁屏快捷键本身会产生输入）。
    public var lockGracePeriod: TimeInterval = 3
    /// 抓拍后的观察期：期间内在 Mac 上用 Touch ID 自证即可取消报警。
    public var observationWindow: TimeInterval = 20
    /// 一次报警发出后，多久内不再开始新的报警。
    public var incidentCooldown: TimeInterval = 60
    public var schedule = GuardSchedule()

    public init() {}
}

/// 为什么处于警戒状态。可以同时有多个原因。
public enum ArmReason: String, Codable, Sendable {
    /// 手机离开超过 `awayArmDelay`。
    case away
    /// 处于定时警戒时间段。
    case schedule
    /// 用户手动开启。
    case manual
}

/// 锁屏期间检测到的操作类型。
public enum ActivityKind: String, Codable, Sendable {
    case input
    case lidOpened
    case displayWake
    case systemWake
    case usbAttached
}

public enum CaptureReason: String, Codable, Sendable {
    /// 警戒中锁屏时有人操作。
    case activity
    /// 警戒中屏幕被解锁。
    case unlockedWhileArmed
    /// 手机发来远程锁定指令。
    case remoteLock
}

public enum DiscardReason: String, Codable, Sendable {
    /// Mac 上 Touch ID 自证。
    case ownerVerified
    /// 手机回到身边。
    case ownerNearby
    /// 手机上确认是本人。
    case remoteConfirmed
}

/// 输入状态机的事件。时间统一由 `handle(_:at:)` 传入。
public enum GuardEvent: Equatable, Sendable {
    case proximityChanged(ProximityState)
    case screenLocked
    case screenUnlocked
    case activity(ActivityKind)
    case ownerVerified
    case remote(RemoteCommand.Action)
    case setManualArm(Bool)
    /// 定时器（建议每秒一次），用于处理超时。
    case tick
}

/// 状态机要求外部执行的动作。
public enum GuardAction: Equatable, Sendable {
    case unlockScreen
    case lockScreen
    case capturePhoto(incidentID: UUID, reason: CaptureReason)
    /// 观察期结束仍未自证：上报到手机。
    case reportIncident(UUID)
    /// 判定为本人：删除照片，不报警。
    case discardIncident(UUID, DiscardReason)
    case armedChanged(Set<ArmReason>)
}

/// 一次可疑事件，从第一次抓拍开始，到上报或撤销结束。
public struct Incident: Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var deadline: Date
    public var trigger: CaptureReason
}

public struct GuardState: Equatable, Sendable {
    public var proximity: ProximityState = .unknown
    public var screenLocked: Bool
    public var lockedAt: Date?
    /// 手机从什么时候开始不在身边。
    public var awaySince: Date?
    public var armReasons: Set<ArmReason> = []
    /// 手机靠近时是否允许自动解锁。在手机在身边时手动锁屏会置为 false，
    /// 直到手机离开一次，避免「刚手动锁屏又被自动解开」。
    public var unlockEligible = true
    public var incident: Incident?
    public var lastReportAt: Date?

    public var isArmed: Bool { !armReasons.isEmpty }
}

/// 警戒状态机。纯逻辑：输入事件和时间，输出动作，不直接调用任何系统功能。
///
/// 规则摘要（详见 docs/architecture.md）：
/// 1. 手机靠近 → 解除离开警戒、撤销观察中的事件；满足条件时自动解锁。
/// 2. 手机从身边离开 → 自动锁屏；离开超过 `awayArmDelay` → 进入警戒。
/// 3. 警戒中锁屏时有操作（锁屏宽限期后）→ 抓拍并进入观察期。
/// 4. 警戒中屏幕被解锁 → 抓拍（观察中则补拍）。
/// 5. 观察期内 Touch ID 自证 → 撤销；观察期结束 → 上报。
public struct GuardPolicy: Sendable {
    public var config: GuardConfig
    public private(set) var state: GuardState
    private let calendar: Calendar
    private let makeID: @Sendable () -> UUID

    public init(
        config: GuardConfig,
        screenLocked: Bool,
        calendar: Calendar = .current,
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.config = config
        self.state = GuardState(screenLocked: screenLocked)
        self.calendar = calendar
        self.makeID = makeID
    }

    public mutating func handle(_ event: GuardEvent, at now: Date) -> [GuardAction] {
        let armedBefore = state.armReasons
        var actions: [GuardAction] = []
        updateArming(now: now)

        switch event {
        case .proximityChanged(let proximity):
            handleProximity(proximity, now: now, actions: &actions)

        case .screenLocked:
            state.screenLocked = true
            state.lockedAt = now
            if state.proximity == .near { state.unlockEligible = false }

        case .screenUnlocked:
            state.screenLocked = false
            state.lockedAt = nil
            if state.isArmed {
                if let incident = state.incident {
                    actions.append(.capturePhoto(incidentID: incident.id, reason: .unlockedWhileArmed))
                } else {
                    startIncident(.unlockedWhileArmed, now: now, actions: &actions)
                }
            }

        case .activity:
            guard state.isArmed, state.screenLocked, state.incident == nil else { break }
            if let lockedAt = state.lockedAt, now.timeIntervalSince(lockedAt) < config.lockGracePeriod { break }
            startIncident(.activity, now: now, actions: &actions)

        case .ownerVerified:
            discardIncident(.ownerVerified, actions: &actions)

        case .remote(.lockNow):
            if !state.screenLocked { actions.append(.lockScreen) }
            state.unlockEligible = false
            if let incident = state.incident {
                actions.append(.capturePhoto(incidentID: incident.id, reason: .remoteLock))
                actions.append(.reportIncident(incident.id))
                state.incident = nil
                state.lastReportAt = now
            } else {
                actions.append(.capturePhoto(incidentID: makeID(), reason: .remoteLock))
            }

        case .remote(.confirmItsMe(let incidentID)):
            if state.incident?.id == incidentID { discardIncident(.remoteConfirmed, actions: &actions) }

        case .setManualArm(let on):
            if on { state.armReasons.insert(.manual) } else { state.armReasons.remove(.manual) }

        case .tick:
            break
        }

        updateArming(now: now)
        if let incident = state.incident, now >= incident.deadline {
            actions.append(.reportIncident(incident.id))
            state.incident = nil
            state.lastReportAt = now
        }
        if state.armReasons != armedBefore {
            actions.append(.armedChanged(state.armReasons))
        }
        return actions
    }

    public func isInScheduledWindow(_ date: Date) -> Bool {
        config.schedule.contains(date, calendar: calendar)
    }

    private mutating func handleProximity(_ proximity: ProximityState, now: Date, actions: inout [GuardAction]) {
        let previous = state.proximity
        state.proximity = proximity
        switch proximity {
        case .near:
            state.awaySince = nil
            state.armReasons.remove(.away)
            // 手机回到身边：能自动解锁就说明已信任手机在场，观察中的事件没有必要再报。
            discardIncident(.ownerNearby, actions: &actions)
            if previous != .near, state.screenLocked, state.unlockEligible, config.autoUnlockEnabled,
                !state.armReasons.contains(.schedule), !state.armReasons.contains(.manual)
            {
                actions.append(.unlockScreen)
            }
        case .far, .absent:
            if state.awaySince == nil { state.awaySince = now }
            state.unlockEligible = true
            if previous == .near, !state.screenLocked, config.autoLockEnabled {
                actions.append(.lockScreen)
            }
        case .unknown:
            break
        }
    }

    private mutating func updateArming(now: Date) {
        if let awaySince = state.awaySince, now.timeIntervalSince(awaySince) >= config.awayArmDelay {
            state.armReasons.insert(.away)
        }
        if isInScheduledWindow(now) {
            state.armReasons.insert(.schedule)
        } else {
            state.armReasons.remove(.schedule)
        }
    }

    private mutating func startIncident(_ reason: CaptureReason, now: Date, actions: inout [GuardAction]) {
        if let lastReportAt = state.lastReportAt, now.timeIntervalSince(lastReportAt) < config.incidentCooldown {
            return
        }
        let incident = Incident(
            id: makeID(), startedAt: now, deadline: now.addingTimeInterval(config.observationWindow), trigger: reason
        )
        state.incident = incident
        actions.append(.capturePhoto(incidentID: incident.id, reason: reason))
    }

    private mutating func discardIncident(_ reason: DiscardReason, actions: inout [GuardAction]) {
        guard let incident = state.incident else { return }
        state.incident = nil
        actions.append(.discardIncident(incident.id, reason))
    }
}
