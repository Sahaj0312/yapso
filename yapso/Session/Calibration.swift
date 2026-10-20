import Foundation
import SwiftData

/// The first thing after onboarding: 60 seconds on an easy personal question, turned into a speaking profile
/// that gives the coach a baseline. Free, required before the first spin, and never part of the streak.
enum Calibration {
    /// Zero-prep questions with a built-in shape, so nobody blanks. The first is the default.
    static let prompts = [
        "Walk me through your perfect Saturday, from the moment you wake up.",
        "Teach me how to make something you're good at making. A dish, a drink, anything.",
        "Tell me about a place you love, so I can picture being there.",
    ]

    /// Until a calibration talk with words in it exists. An empty one (nothing said) needs another go.
    static func isNeeded(attempts: [Attempt]) -> Bool {
        !attempts.contains { $0.kind == .calibration && $0.endedAt != nil && $0.feedbackStatus != .skippedEmpty }
    }

    /// Starts the talk straight away: no reveal and no research, just the 3-2-1 countdown.
    @discardableResult
    static func start(prompt: String, in context: ModelContext) async -> Attempt? {
        let micGranted = Permissions.microphoneGranted ? true : await Permissions.requestMicrophone()
        guard micGranted else { return nil }
        // Not a pool topic, so it never uses one up.
        let topic = Topic(id: "calibration", title: prompt, domain: "Calibration")
        let attempt = Attempt(kind: .calibration, topic: topic, revealedAt: .now)
        context.insert(attempt)
        try? context.save()
        return attempt
    }
}
