import Foundation

nonisolated struct TranscribedWord: Codable, Hashable, Sendable {
    /// As transcribed, including punctuation and leading space ("um,").
    var text: String
    var start: Double
    var end: Double

    var normalized: String {
        text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }
}

nonisolated struct Pause: Codable, Hashable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

/// Everything the transcript screen needs: timed words plus silences measured from the audio itself
/// (the transcriber folds silence into the next word's time range, so word gaps can't be trusted).
nonisolated struct TranscriptTimeline: Codable, Hashable, Sendable {
    var text: String
    var words: [TranscribedWord]
    var pauses: [Pause]
}

nonisolated struct DeliveryMetrics: Equatable, Sendable {
    var wordCount: Int
    var wordsPerMinute: Double
    var fillerCount: Int
    var longestPause: Double
    var secondsUsed: Double
}

nonisolated enum DeliveryAnalyzer {
    /// Pauses at least this long are marked in the transcript.
    static let notablePause: Double = 1.5
    /// Reaction time after recording starts that doesn't count as a pause.
    static let startGrace: Double = 1.0

    private static let singleWordFillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mm"]
    /// Words before "you know" that make it a real question, not a filler ("do you know why…").
    private static let youKnowQuestionLeads: Set<String> = ["do", "did", "don't", "didn't", "dont", "didnt", "if", "what", "would", "you'd", "could"]

    /// Word-index spans that are fillers. Multi-word fillers ("you know") are one span.
    static func fillerSpans(in words: [TranscribedWord]) -> [ClosedRange<Int>] {
        let norm = words.map(\.normalized)
        var spans: [ClosedRange<Int>] = []

        func endsClause(_ index: Int) -> Bool {
            guard index >= 0 else { return true }
            guard let last = words[index].text.trimmingCharacters(in: .whitespaces).last else { return false }
            return ",.?!;:".contains(last)
        }

        for i in norm.indices {
            switch norm[i] {
            case let w where singleWordFillers.contains(w):
                spans.append(i...i)
            case "like":
                // Filler "like" is set off by commas or starts a clause; "looks like a rock" is not.
                if endsClause(i) || endsClause(i - 1) { spans.append(i...i) }
            case "know" where i > 0 && norm[i - 1] == "you":
                let lead = i >= 2 ? norm[i - 2] : ""
                if !youKnowQuestionLeads.contains(lead) && !words[i].text.contains("?") { spans.append((i - 1)...i) }
            case "mean" where i > 0 && norm[i - 1] == "i":
                if endsClause(i) { spans.append((i - 1)...i) }
            default:
                break
            }
        }
        return spans
    }

    static func metrics(for timeline: TranscriptTimeline, secondsUsed: Double) -> DeliveryMetrics {
        let spans = fillerSpans(in: timeline.words)
        let fillerWordCount = spans.reduce(0) { $0 + $1.count }
        let contentWords = timeline.words.count - fillerWordCount
        let minutes = secondsUsed / 60
        return DeliveryMetrics(
            wordCount: contentWords,
            wordsPerMinute: minutes > 0 ? Double(contentWords) / minutes : 0,
            fillerCount: spans.count,
            longestPause: timeline.pauses.map(\.duration).max() ?? 0,
            secondsUsed: secondsUsed
        )
    }

    /// Silences from per-frame audio levels (dBFS). Trailing silence after the last speech isn't a pause,
    /// and the first `startGrace` seconds are reaction time.
    static func pauses(frameLevels: [Float], frameDuration: Double, minimumPause: Double = 0.3) -> [Pause] {
        guard !frameLevels.isEmpty else { return [] }
        let sorted = frameLevels.sorted()
        let speechLevel = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let threshold = max(-50, speechLevel - 22)
        guard let lastSpeech = frameLevels.lastIndex(where: { $0 >= threshold }) else { return [] }

        var pauses: [Pause] = []
        var runStart: Int?
        for i in 0...lastSpeech {
            let silent = frameLevels[i] < threshold
            if silent, runStart == nil { runStart = i }
            if !silent, let start = runStart {
                let begin = max(Double(start) * frameDuration, startGrace)
                let end = Double(i) * frameDuration
                if end - begin >= minimumPause { pauses.append(Pause(start: begin, end: end)) }
                runStart = nil
            }
        }
        return pauses
    }

    /// Mean of a metric over the `windowDays` days before `day`, once there are at least `minimumSamples`.
    static func baseline(_ samples: [(day: DayKey, value: Double)], before day: DayKey,
                         windowDays: Int = 7, minimumSamples: Int = 3, calendar: Calendar = .current) -> Double? {
        let earliest = day.adding(days: -windowDays, calendar: calendar)
        let window = samples.filter { $0.day >= earliest && $0.day < day }.map(\.value)
        guard window.count >= minimumSamples else { return nil }
        return window.reduce(0, +) / Double(window.count)
    }
}
