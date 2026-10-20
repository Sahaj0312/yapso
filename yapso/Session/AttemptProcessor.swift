import AVFoundation
import SwiftData

/// Turns a finished recording into a transcript and delivery metrics. Idempotent and safe to call again after
/// a crash or a failed upload; attempts whose audio lives on another device are left alone.
///
/// Daily talks are transcribed by Deepgram only, so they fail with `TranscriptionError.offline` until there's a
/// connection. Practice talks fall back to the on-device model.
enum AttemptProcessor {
    private static var inFlight: Set<UUID> = []

    static func transcribeIfNeeded(_ attempt: Attempt) async throws {
        guard !attempt.isTranscribed, attempt.endedAt != nil, !inFlight.contains(attempt.id),
              let fileName = attempt.audioFileName else { return }
        var url = Recordings.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        inFlight.insert(attempt.id)
        defer { inFlight.remove(attempt.id) }

        // A (near-)empty file has nothing to transcribe, and SpeechAnalyzer never finishes on one.
        let audioSeconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        if audioSeconds < 0.3 {
            apply(TranscriptTimeline(text: "", words: [], pauses: []), source: nil, to: attempt)
            return
        }

        if url.pathExtension == "caf" {
            url = try await Task.detached { try AudioCompressor.compressToAAC(url) }.value
            attempt.audioFileName = url.lastPathComponent
            try? attempt.modelContext?.save()
            try? FileManager.default.removeItem(at: Recordings.url(for: fileName))
        }

        async let levels = Task.detached { [url] in try AudioLevels.frameLevels(fileURL: url) }.value
        let (text, words, source) = try await transcribe(url, kind: attempt.kind, keyterms: [attempt.topicTitle])
        let pauses = DeliveryAnalyzer.pauses(frameLevels: try await levels, frameDuration: AudioLevels.frameDuration)
        apply(TranscriptTimeline(text: text, words: words, pauses: pauses), source: source, to: attempt)
    }

    private static func transcribe(_ url: URL, kind: AttemptKind, keyterms: [String])
        async throws -> (String, [TranscribedWord], TranscriptionSource) {
        do {
            let (text, words) = try await CloudTranscriber.transcribe(fileURL: url, keyterms: keyterms)
            return (text, words, .cloud)
        } catch {
            guard kind == .practice else { throw error }
            let (text, words) = try await withTimeout(seconds: 60) { try await OnDeviceTranscriber.transcribe(fileURL: url) }
            return (text, words, .onDevice)
        }
    }

    private static func apply(_ timeline: TranscriptTimeline, source: TranscriptionSource?, to attempt: Attempt) {
        let metrics = DeliveryAnalyzer.metrics(for: timeline, secondsUsed: attempt.secondsUsed)
        attempt.transcript = timeline.text
        attempt.transcriptTimeline = timeline
        attempt.transcriptionSource = source
        attempt.wordCount = metrics.wordCount
        attempt.wordsPerMinute = metrics.wordsPerMinute
        attempt.fillerCount = metrics.fillerCount
        attempt.longestPauseSeconds = metrics.longestPause
        attempt.isTranscribed = true
        if timeline.words.isEmpty { attempt.feedbackStatus = .skippedEmpty }
        try? attempt.modelContext?.save()
    }
}
