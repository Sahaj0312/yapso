import Foundation
import SwiftData

enum ScenarioStore {
    static let all: [Scenario] = (try? ScenarioLibrary.loadBundled()) ?? []

    static func scenario(id: String) -> Scenario? {
        all.first { $0.id == id }
    }
}

/// Rehearsing real-life moments from the library under today's topic. Pro, with one free try; available any time,
/// never part of the streak, Progress or coach memory.
enum Scenarios {
    /// A day's rehearsals, redos included. The Worker's per-device limits sit a little above this.
    static let dailyLimit = 8

    enum Availability: Equatable {
        case available(remaining: Int)
        /// A free user who has had their one free try: show the paywall.
        case needsPro
        case limitReached
    }

    static func availability(attempts: [Attempt], now: Date = .now) -> Availability {
        let rehearsals = attempts.filter { $0.kind == .scenario }
        if !AppConfig.hasPro && !rehearsals.isEmpty { return .needsPro }
        let today = DayKey(now).rawValue
        let used = rehearsals.filter { $0.dayKey == today }.count
        return used < dailyLimit ? .available(remaining: dailyLimit - used) : .limitReached
    }

    /// The latest finished attempt at this scenario, which a new one is compared against.
    static func lastAttempt(at scenario: Scenario, in attempts: [Attempt]) -> Attempt? {
        attempts.filter { $0.kind == .scenario && $0.topicID == scenario.id && $0.endedAt != nil }
            .max { $0.revealedAt < $1.revealedAt }
    }

    /// Starts the 30-second prep for a scenario straight away. Assumes `availability` allowed it.
    @discardableResult
    static func start(_ scenario: Scenario, attempts: [Attempt], in context: ModelContext) async -> Attempt? {
        let micGranted = Permissions.microphoneGranted ? true : await Permissions.requestMicrophone()
        guard micGranted else { return nil }
        let topic = Topic(id: scenario.id, title: scenario.title, domain: scenario.category.title)
        let attempt = Attempt(kind: .scenario, topic: topic, revealedAt: .now)
        attempt.redoOfAttemptID = lastAttempt(at: scenario, in: attempts)?.id
        context.insert(attempt)
        try? context.save()
        return attempt
    }

    /// Rehearsals (and old practice topics) never forfeit, so one abandoned before speaking would start recording the
    /// next time the app opens. Unspoken ones from earlier days are dropped instead.
    static func dropAbandoned(attempts: [Attempt], in context: ModelContext, now: Date = .now) {
        let today = DayKey(now)
        let stale = attempts.filter { attempt in
            (attempt.kind == .practice || attempt.kind == .scenario) && attempt.speakingStartedAt == nil
                && DayKey(attempt.timeline.researchDeadline) < today
        }
        guard !stale.isEmpty else { return }
        for attempt in stale {
            ResearchNotifications.cancel(attemptID: attempt.id)
            context.delete(attempt)
        }
        try? context.save()
    }
}
