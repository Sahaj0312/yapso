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
    /// Topics are rated on clarity, structure, accuracy and ownership; scenarios swap the last two for
    /// relevance (did you answer what was asked) and presence (conviction vs hedging).
    case clarity, structure, accuracy, ownership, relevance, presence
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
    /// From the calibration talk. Kept by the app across daily memory replacements.
    var profile: SpeakingProfile?
}

/// The kind of speaker the calibration talk showed. A fixed set, so the name and blurb are always consistent.
nonisolated enum SpeakerType: String, Codable, CaseIterable, Sendable {
    case storyteller, sprinter, professor, minimalist, improviser, diplomat

    var name: String {
        switch self {
        case .storyteller: "The Storyteller"
        case .sprinter: "The Sprinter"
        case .professor: "The Professor"
        case .minimalist: "The Minimalist"
        case .improviser: "The Improviser"
        case .diplomat: "The Diplomat"
        }
    }

    var tagline: String {
        switch self {
        case .storyteller: "You paint pictures and pull people in."
        case .sprinter: "Quick, energetic and full of ideas."
        case .professor: "Thorough and organised. You cover the ground."
        case .minimalist: "Clear and to the point. No wasted words."
        case .improviser: "You think out loud and find it as you go."
        case .diplomat: "Careful, measured and considerate."
        }
    }

    /// Tarot-style numbering for the card.
    var numeral: String {
        switch self {
        case .storyteller: "I"
        case .sprinter: "II"
        case .professor: "III"
        case .minimalist: "IV"
        case .improviser: "V"
        case .diplomat: "VI"
        }
    }

    var watchOut: String {
        switch self {
        case .storyteller: "Stories can wander before the point lands."
        case .sprinter: "Listeners need a beat to catch up."
        case .professor: "Detail can bury the main idea."
        case .minimalist: "Sometimes too brief to bring people with you."
        case .improviser: "Fillers and restarts creep in while you search."
        case .diplomat: "Hedging can undersell what you know."
        }
    }
}

/// The result of the calibration talk: who you are as a speaker today, and your starting numbers.
nonisolated struct SpeakingProfile: Codable, Hashable, Sendable {
    var type: SpeakerType
    /// Two personal sentences about this talk.
    var summary: String
    /// What the coach noticed, written conversationally in a few short paragraphs. Missing on older profiles.
    var message: String?
    var strengths: [String]
    var workOn: [FocusArea]
    var firstTip: String
    var baselineWordsPerMinute: Double
    var baselineFillersPerMinute: Double
    var baselineLongestPause: Double
}
