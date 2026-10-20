import AVFoundation
import SwiftData

/// Turns a finished recording into a transcript and delivery metrics. Idempotent and safe to call again after
/// a crash or a failed upload; attempts whose audio lives on another device are left alone.
///
/// Daily talks are transcribed by Deepgram only, so they fail with `APIError.offline` until there's a
/// connection. Practice talks fall back to the on-device model. Then the coach's feedback is requested.
enum AttemptProcessor {
    private static var inFlight: Set<UUID> = []
    private static var feedbackInFlight: Set<UUID> = []

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
        let (text, words, source) = try await transcribe(url, kind: attempt.kind, keyterms: attempt.kind == .calibration ? [] : [attempt.topicTitle])
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

    /// Requests the coach's content feedback once a talk with words is transcribed. Daily talks also replace the
    /// coach's memory. Free users get one real feedback; later ones are marked locked.
    static func requestFeedbackIfNeeded(_ attempt: Attempt, history: [Attempt]) async throws {
        // The calibration is free for everyone and never counts as the free tier's one feedback.
        let requestable: Set<FeedbackStatus> = AppConfig.hasPro || attempt.kind == .calibration
            ? [.notRequested, .pending, .failed, .locked] : [.notRequested, .pending, .failed]
        guard attempt.isTranscribed, requestable.contains(attempt.feedbackStatus), !feedbackInFlight.contains(attempt.id),
              let timeline = attempt.transcriptTimeline, !timeline.words.isEmpty,
              let context = attempt.modelContext else { return }

        if !AppConfig.hasPro, attempt.kind != .calibration,
           history.contains(where: { $0.id != attempt.id && $0.kind != .calibration && $0.feedbackStatus == .complete }) {
            attempt.feedbackStatus = .locked
            try? context.save()
            return
        }

        feedbackInFlight.insert(attempt.id)
        defer { feedbackInFlight.remove(attempt.id) }
        attempt.feedbackStatus = .pending
        try? context.save()

        let profile = CoachProfile.latest(in: context)
        let averages: FeedbackClient.Request.Averages? = attempt.baseline(in: history, \.wordsPerMinute).map { wpm in
            FeedbackClient.Request.Averages(
                wordsPerMinute: wpm,
                fillerCount: attempt.baseline(in: history) { Double($0.fillerCount) } ?? 0,
                longestPause: attempt.baseline(in: history, \.longestPauseSeconds) ?? 0,
                secondsUsed: attempt.baseline(in: history, \.secondsUsed) ?? 0
            )
        }
        let previous = attempt.redoOfAttemptID
            .flatMap { id in history.first { $0.id == id } }
            .map { earlier in
                FeedbackClient.Request.Previous(
                    transcript: earlier.transcript,
                    ratings: Dictionary(uniqueKeysWithValues: (earlier.contentFeedback?.ratings ?? []).map { ($0.criterion.rawValue, $0.score) })
                )
            }
        let request = FeedbackClient.Request(
            kind: attempt.kind,
            topic: .init(title: attempt.topicTitle, domain: attempt.topicDomain),
            transcript: timeline.text,
            metrics: .init(wordCount: attempt.wordCount, wordsPerMinute: attempt.wordsPerMinute, fillerCount: attempt.fillerCount,
                           longestPause: attempt.longestPauseSeconds, secondsUsed: attempt.secondsUsed),
            averages: averages,
            memory: profile?.memory ?? CoachMemory(),
            previous: previous
        )

        if attempt.kind == .calibration {
            try await calibrate(attempt, request: request, profile: profile, context: context)
            return
        }

        do {
            let (feedback, memory) = try await FeedbackClient.request(request)
            attempt.contentFeedback = feedback
            attempt.feedbackStatus = .complete
            // Only daily talks shape what the coach remembers; practice reads it but never writes.
            if attempt.kind == .daily, var memory {
                memory.onboarding = profile?.memory.onboarding
                memory.profile = profile?.memory.profile
                if let profile {
                    profile.memory = memory
                    profile.updatedAt = .now
                } else {
                    context.insert(CoachProfile(memory: memory))
                }
            }
            try? context.save()
        } catch {
            attempt.feedbackStatus = .failed
            try? context.save()
            throw error
        }
    }

    /// Turns the calibration talk into a speaking profile, which also seeds what the coach tracks.
    private static func calibrate(_ attempt: Attempt, request: FeedbackClient.Request, profile: CoachProfile?,
                                  context: ModelContext) async throws {
        do {
            let reply = try await FeedbackClient.calibrate(request)
            let minutes = attempt.secondsUsed / 60
            let speaking = SpeakingProfile(
                type: reply.type, summary: reply.summary, message: reply.message, strengths: reply.strengths, workOn: reply.workOn,
                firstTip: reply.firstTip,
                baselineWordsPerMinute: attempt.wordsPerMinute,
                baselineFillersPerMinute: minutes > 0 ? Double(attempt.fillerCount) / minutes : 0,
                baselineLongestPause: attempt.longestPauseSeconds
            )
            attempt.speakingProfile = speaking
            attempt.feedbackStatus = .complete

            var memory = profile?.memory ?? CoachMemory()
            memory.profile = speaking
            memory.weaknesses = reply.workOn
            memory.strengths = reply.strengths
            memory.recentTips = [reply.firstTip]
            if let profile {
                profile.memory = memory
                profile.updatedAt = .now
            } else {
                context.insert(CoachProfile(memory: memory))
            }
            try? context.save()
        } catch {
            attempt.feedbackStatus = .failed
            try? context.save()
            throw error
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
