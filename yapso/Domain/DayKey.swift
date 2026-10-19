import Foundation

/// A local calendar day, stored as "yyyy-MM-dd". The unit for streaks and the one-daily-attempt rule.
nonisolated struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        self.rawValue = rawValue
    }

    /// Noon on this day, which is safe from DST edge cases when doing day arithmetic.
    func date(calendar: Calendar = .current) -> Date? {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        guard let base = date(calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return self }
        return DayKey(shifted, calendar: calendar)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }
}
