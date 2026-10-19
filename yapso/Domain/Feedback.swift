import Foundation

nonisolated enum FeedbackStatus: String, Codable, Sendable {
    case notRequested
    case pending
    case complete
    case failed
    /// Nothing was said; a hardcoded kind card is shown instead of AI feedback.
    case skippedEmpty
    /// Free user past their one free AI feedback; the hardcoded blurred preview is shown.
    case locked
}

nonisolated enum ContentCriterion: String, Codable, CaseIterable, Sendable {
    case clarity, structure, accuracy, ownership
}

nonisolated struct CriterionRating: Codable, Hashable, Sendable {
    var criterion: ContentCriterion
    /// 1–5
    var score: Int
    var reason: String
}

nonisolated struct FlaggedClaim: Codable, Hashable, Sendable {
    var quote: String
    var correction: String
}

/// The AI's structured content feedback for one attempt. Rendered as native UI, never as raw text.
nonisolated struct ContentFeedback: Codable, Hashable, Sendable {
    /// Optional opener reacting to how the user seemed to feel ("You said you suck. You don't…").
    var coachNote: String?
    var ratings: [CriterionRating]
    var flaggedClaims: [FlaggedClaim]
    /// At most 2 key ideas a good explanation would have included.
    var whatYouMissed: [String]
    var nextTimeTip: String
    /// Comparison with an earlier attempt on the same topic, for practice redos.
    var comparison: String?
}

nonisolated struct FocusArea: Codable, Hashable, Sendable {
    var label: String
    var evidence: String
}

nonisolated struct OnboardingAnswers: Codable, Hashable, Sendable {
    var situation: String?
    var struggles: [String] = []
    var goal: String?
}

/// What the coach remembers about the user. Sent with every analysis; daily analyses return a replacement.
nonisolated struct CoachMemory: Codable, Hashable, Sendable {
    var weaknesses: [FocusArea] = []
    var strengths: [String] = []
    var recentTips: [String] = []
    var onboarding: OnboardingAnswers?
}
