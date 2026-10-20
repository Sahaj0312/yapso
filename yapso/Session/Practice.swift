import Foundation
import SwiftData

/// Pro practice: more topics after the daily, through the same flow. Never touches the streak, Progress or coach memory.
enum Practice {
    /// The Worker also caps feedback per device per day, a little above this.
    static let dailyLimit = 5

    enum Availability: Equatable {
        case available(remaining: Int)
        /// Free users see the paywall instead.
        case needsPro
        /// Practice opens once today's daily talk is done.
        case afterDaily
        case limitReached
    }

    static func availability(attempts: [Attempt], now: Date = .now) -> Availability {
        let today = DayKey(now).rawValue
        guard AppConfig.hasPro else { return .needsPro }
        guard attempts.contains(where: { $0.kind == .daily && $0.dayKey == today && $0.endedAt != nil }) else { return .afterDaily }
        let used = attempts.filter { $0.kind == .practice && $0.dayKey == today }.count
        return used < dailyLimit ? .available(remaining: dailyLimit - used) : .limitReached
    }

    /// Starts a practice attempt: a fresh topic, or `redoing` an earlier talk's topic. Assumes `availability` allowed it.
    @discardableResult
    static func start(redoing earlier: Attempt? = nil, attempts: [Attempt], in context: ModelContext) async -> Attempt? {
        let micGranted = Permissions.microphoneGranted ? true : await Permissions.requestMicrophone()
        guard micGranted else { return nil }

        let topic: Topic
        if let earlier {
            topic = Topic(id: earlier.topicID, title: earlier.topicTitle, domain: earlier.topicDomain)
        } else {
            // Practice consumes topics too, so tomorrow's daily is never one already practiced.
            guard let fresh = TopicPicker.pick(from: TopicStore.all, excluding: Set(attempts.map(\.topicID))) else { return nil }
            topic = fresh
        }
        let attempt = Attempt(kind: .practice, topic: topic, revealedAt: .now.addingTimeInterval(AppConfig.spinDuration))
        attempt.redoOfAttemptID = earlier?.id
        context.insert(attempt)
        try? context.save()
        await ResearchNotifications.schedule(attemptID: attempt.id, topicTitle: topic.title, deadline: attempt.timeline.researchDeadline)
        return attempt
    }

    /// Practice never forfeits, so one abandoned before speaking would otherwise start recording whenever the app
    /// is next opened. Unspoken practice from earlier days is dropped instead.
    static func dropAbandoned(attempts: [Attempt], in context: ModelContext, now: Date = .now) {
        let today = DayKey(now)
        let stale = attempts.filter { attempt in
            attempt.kind == .practice && attempt.speakingStartedAt == nil
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
