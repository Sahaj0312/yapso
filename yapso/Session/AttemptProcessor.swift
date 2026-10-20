import Foundation
import SwiftData

/// Turns a finished recording into a transcript and delivery metrics, on-device. Idempotent and safe to
/// call again after a crash; attempts whose audio lives on another device are left alone.
enum AttemptProcessor {
    private static var inFlight: Set<UUID> = []

    static func transcribeIfNeeded(_ attempt: Attempt) async throws {
        guard !attempt.isTranscribed, attempt.endedAt != nil, !inFlight.contains(attempt.id),
              let fileName = attempt.audioFileName else { return }
        let url = Recordings.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        inFlight.insert(attempt.id)
        defer { inFlight.remove(attempt.id) }

        async let transcription = Transcriber.transcribe(fileURL: url)
        async let levels = Task.detached { try AudioLevels.frameLevels(fileURL: url) }.value
        let (text, words) = try await transcription
        let pauses = DeliveryAnalyzer.pauses(frameLevels: try await levels, frameDuration: AudioLevels.frameDuration)

        let timeline = TranscriptTimeline(text: text, words: words, pauses: pauses)
        let metrics = DeliveryAnalyzer.metrics(for: timeline, secondsUsed: attempt.secondsUsed)
        attempt.transcript = text
        attempt.transcriptTimeline = timeline
        attempt.wordCount = metrics.wordCount
        attempt.wordsPerMinute = metrics.wordsPerMinute
        attempt.fillerCount = metrics.fillerCount
        attempt.longestPauseSeconds = metrics.longestPause
        attempt.isTranscribed = true
        if words.isEmpty { attempt.feedbackStatus = .skippedEmpty }
        try? attempt.modelContext?.save()
    }
}
