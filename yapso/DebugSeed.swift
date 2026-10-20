#if DEBUG
import Foundation
import SwiftData

/// Launch with `-yapsoSeedHistory` (Debug only) to fill History and Progress with two weeks of sample talks,
/// including one finished today.
enum DebugSeed {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-yapsoSeedHistory") }

    static func seedHistory(in context: ModelContext) {
        let topics = TopicStore.all
        guard topics.count >= 30,
              (try? context.fetchCount(FetchDescriptor<Attempt>())) == 0 else { return }

        let calendar = Calendar.current
        for daysAgo in (0...14).reversed() where daysAgo != 6 && daysAgo != 10 {
            // Today's talk finished a few minutes ago, so Today shows its result and practice.
            let day = daysAgo == 0 ? Date.now.addingTimeInterval(-900) : calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
            let progress = min(1, Double(14 - daysAgo) / 13)
            let attempt = Attempt(kind: .daily, topic: topics[daysAgo + 15], revealedAt: day)
            attempt.speakingStartedAt = day.addingTimeInterval(600)
            attempt.secondsUsed = 55 + 30 * progress
            attempt.endedAt = attempt.speakingStartedAt!.addingTimeInterval(attempt.secondsUsed)
            attempt.isTranscribed = true
            attempt.transcriptionSource = .cloud
            attempt.wordsPerMinute = 104 + 32 * progress + Double(daysAgo % 3) * 4
            attempt.wordCount = Int(attempt.wordsPerMinute * attempt.secondsUsed / 60)
            attempt.fillerCount = max(1, 9 - Int(6 * progress) + daysAgo % 2)
            attempt.longestPauseSeconds = 3.6 - 2 * progress + Double(daysAgo % 3) * 0.3
            attempt.transcript = "Sample talk about \(attempt.topicTitle)."
            attempt.transcriptTimeline = TranscriptTimeline(
                text: attempt.transcript,
                words: attempt.transcript.split(separator: " ").enumerated().map { index, word in
                    TranscribedWord(text: (index > 0 ? " " : "") + word, start: Double(index) * 0.4, end: Double(index) * 0.4 + 0.3)
                },
                pauses: []
            )
            let base = 2 + Int((2 * progress).rounded())
            attempt.contentFeedback = ContentFeedback(
                coachNote: nil,
                ratings: [
                    CriterionRating(criterion: .clarity, score: min(5, base + daysAgo % 2), reason: "Sample reason."),
                    CriterionRating(criterion: .structure, score: base, reason: "Sample reason."),
                    CriterionRating(criterion: .accuracy, score: min(5, base + 1), reason: "Sample reason."),
                    CriterionRating(criterion: .ownership, score: max(1, base - daysAgo % 2), reason: "Sample reason."),
                ],
                flaggedClaims: [],
                whatYouMissed: ["Sample missed idea."],
                nextTimeTip: "Open with one sentence a beginner would get.",
                comparison: nil
            )
            attempt.feedbackStatus = .complete
            context.insert(attempt)
        }

        // The calibration that came first. Its result shows on Today with `-yapsoCalibrationResult`.
        let profile = SpeakingProfile(
            type: .improviser,
            summary: "You pictured a relaxed Saturday from balcony coffee to the farmers market and a movie, shaping the answer as you went.",
            strengths: ["A clear arc from morning to night", "Specific, memorable details"],
            workOn: [
                FocusArea(label: "Fewer fillers", evidence: "Eleven ums and likes, mostly between activities."),
                FocusArea(label: "Land the point", evidence: "Ended on 'something like that' instead of why it's perfect."),
            ],
            firstTip: "Pick three beats before you start, then finish with one sentence that sums it up.",
            baselineWordsPerMinute: 124, baselineFillersPerMinute: 14.3, baselineLongestPause: 1.8
        )
        let calibration = Attempt(kind: .calibration, topic: Topic(id: "calibration", title: Calibration.prompts[0], domain: "Calibration"),
                                  revealedAt: calendar.date(byAdding: .day, value: -15, to: .now)!)
        calibration.speakingStartedAt = calibration.revealedAt
        calibration.secondsUsed = 46
        calibration.endedAt = calibration.revealedAt.addingTimeInterval(46)
        calibration.isTranscribed = true
        calibration.transcript = "Okay so my perfect Saturday, I'd wake up kind of late."
        calibration.wordCount = 95
        calibration.wordsPerMinute = 124
        calibration.fillerCount = 11
        calibration.longestPauseSeconds = 1.8
        calibration.speakingProfile = profile
        calibration.feedbackStatus = .complete
        context.insert(calibration)
        if !ProcessInfo.processInfo.arguments.contains("-yapsoCalibrationResult") {
            UserDefaults.standard.set(calibration.id.uuidString, forKey: "seenCalibrationID")
        }

        // A day that was revealed but never spoken.
        let forfeited = Attempt(kind: .daily, topic: topics[21], revealedAt: calendar.date(byAdding: .day, value: -6, to: .now)!)
        context.insert(forfeited)

        context.insert(CoachProfile(memory: CoachMemory(
            weaknesses: [
                FocusArea(label: "Trailing endings", evidence: "Ship of Theseus and Bloom filters both ended on 'yeah'."),
                FocusArea(label: "Unexplained jargon", evidence: "Said 'fat-tailed' in the Lindy talk without explaining it."),
            ],
            strengths: ["Opens with the core idea", "Uses concrete analogies"],
            recentTips: ["End on one sentence about why it matters, then stop."],
            profile: profile
        )))
        try? context.save()
        UserDefaults.standard.set(true, forKey: Preferences.hasOnboarded)
    }
}
#endif
