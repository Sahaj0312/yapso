import Foundation

/// Consecutive local days with a completed daily attempt. Missing a day resets to 0; no freezes.
nonisolated enum Streak {
    /// Today not being done yet doesn't break the streak — it stays alive until midnight.
    static func current(completedDays: Set<DayKey>, today: DayKey, calendar: Calendar = .current) -> Int {
        var day = completedDays.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while completedDays.contains(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }

    static func best(completedDays: Set<DayKey>, calendar: Calendar = .current) -> Int {
        var best = 0
        for day in completedDays where !completedDays.contains(day.adding(days: -1, calendar: calendar)) {
            var length = 1
            var next = day.adding(days: 1, calendar: calendar)
            while completedDays.contains(next) {
                length += 1
                next = next.adding(days: 1, calendar: calendar)
            }
            best = max(best, length)
        }
        return best
    }
}
