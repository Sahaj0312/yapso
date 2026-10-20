import Foundation
import SwiftData

/// One reveal → research → speak → feedback run, daily or practice.
///
/// CloudKit-compatible: every property is optional or defaulted, no unique constraints.
/// Audio is kept on-device (it's uploaded only to be transcribed); `audioFileName` points into the local recordings folder and may be missing on other devices.
@Model
final class Attempt {
    var id: UUID = UUID()
    var kindRaw: String = AttemptKind.daily.rawValue

    var topicID: String = ""
    var topicTitle: String = ""
    var topicDomain: String = ""

    /// Local day the topic was revealed ("yyyy-MM-dd"). The day a daily attempt counts for.
    var dayKey: String = ""
    var revealedAt: Date = Date()
    var speakingStartedAt: Date?
    var endedAt: Date?

    var transcript: String = ""
    /// JSON `TranscriptTimeline`: timed words and measured pauses.
    var transcriptTimelineData: Data?
    var isTranscribed: Bool = false
    var transcriptionSourceRaw: String?
    var audioFileName: String?

    // Delivery metrics, computed on-device.
    var wordCount: Int = 0
    var wordsPerMinute: Double = 0
    var fillerCount: Int = 0
    var longestPauseSeconds: Double = 0
    var secondsUsed: Double = 0

    var feedbackStatusRaw: String = FeedbackStatus.notRequested.rawValue
    var feedbackData: Data?

    /// For practice redos of a past topic: the attempt being redone.
    var redoOfAttemptID: UUID?

    init(kind: AttemptKind, topic: Topic, revealedAt: Date = .now, calendar: Calendar = .current) {
        self.kindRaw = kind.rawValue
        self.topicID = topic.id
        self.topicTitle = topic.title
        self.topicDomain = topic.domain
        self.revealedAt = revealedAt
        self.dayKey = DayKey(revealedAt, calendar: calendar).rawValue
    }

    var kind: AttemptKind {
        get { AttemptKind(rawValue: kindRaw) ?? .daily }
        set { kindRaw = newValue.rawValue }
    }

    var day: DayKey? { DayKey(rawValue: dayKey) }

    var feedbackStatus: FeedbackStatus {
        get { FeedbackStatus(rawValue: feedbackStatusRaw) ?? .notRequested }
        set { feedbackStatusRaw = newValue.rawValue }
    }

    var transcriptionSource: TranscriptionSource? {
        get { transcriptionSourceRaw.flatMap(TranscriptionSource.init) }
        set { transcriptionSourceRaw = newValue?.rawValue }
    }

    var contentFeedback: ContentFeedback? {
        get { feedbackData.flatMap { try? JSONDecoder().decode(ContentFeedback.self, from: $0) } }
        set { feedbackData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var transcriptTimeline: TranscriptTimeline? {
        get { transcriptTimelineData.flatMap { try? JSONDecoder().decode(TranscriptTimeline.self, from: $0) } }
        set { transcriptTimelineData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var timeline: SessionTimeline {
        SessionTimeline(kind: kind, revealedAt: revealedAt, speakingStartedAt: speakingStartedAt, endedAt: endedAt,
                        researchDuration: AppConfig.researchDuration)
    }
}

extension Attempt {
    /// This attempt's metric averaged over the 7 days before it, from other daily talks that said something.
    func baseline(in history: [Attempt], _ value: (Attempt) -> Double) -> Double? {
        guard let day else { return nil }
        let samples = history
            .filter { $0.kind == .daily && $0.isTranscribed && $0.wordCount > 0 && $0.id != id }
            .compactMap { attempt in attempt.day.map { (day: $0, value: value(attempt)) } }
        return DeliveryAnalyzer.baseline(samples, before: day)
    }
}
