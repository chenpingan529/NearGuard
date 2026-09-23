import Foundation

/// 定时警戒：在设定的时间段内始终处于警戒状态，并禁用自动解锁。
public struct GuardSchedule: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        /// 生效的星期，1 = 周日 … 7 = 周六（与 `Calendar` 一致）。指的是时间段开始的那一天。
        public var weekdays: Set<Int>
        /// 开始时间，从 0 点起的分钟数。
        public var start: Int
        /// 结束时间，从 0 点起的分钟数。小于等于 `start` 表示跨夜到第二天。
        public var end: Int

        public init(weekdays: Set<Int>, start: Int, end: Int) {
            self.weekdays = weekdays
            self.start = start
            self.end = end
        }

        func contains(weekday: Int, previousWeekday: Int, minute: Int) -> Bool {
            if start < end {
                return weekdays.contains(weekday) && minute >= start && minute < end
            }
            // 跨夜：开始当天的 start 之后，或者前一天开始、今天 end 之前。
            return (weekdays.contains(weekday) && minute >= start)
                || (weekdays.contains(previousWeekday) && minute < end)
        }
    }

    public var isEnabled: Bool
    public var windows: [Window]

    public init(isEnabled: Bool = false, windows: [Window] = []) {
        self.isEnabled = isEnabled
        self.windows = windows
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isEnabled else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        return windows.contains {
            $0.contains(weekday: weekday, previousWeekday: previousWeekday, minute: hour * 60 + minute)
        }
    }
}
