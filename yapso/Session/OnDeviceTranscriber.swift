import AVFoundation
import Speech

/// On-device transcription via SpeechAnalyzer: the offline fallback for practice talks. Less accurate than
/// `CloudTranscriber`, but needs no network or speech-recognition permission and keeps disfluencies ("um", "uh").
nonisolated enum OnDeviceTranscriber {
    static func locale() async -> Locale {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) ?? Locale(identifier: "en-US")
    }

    /// Downloads the speech model if it isn't installed yet. Called at launch so the first attempt doesn't wait.
    static func prepareModel() async {
        let locale = await locale()
        try? await ensureModel(for: SpeechTranscriber(locale: locale, preset: .transcription), locale: locale)
    }

    /// The app must reserve the locale before the system lets it use (or check) the model, even one already on the device.
    private static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    static func transcribe(fileURL: URL) async throws -> (text: String, words: [TranscribedWord]) {
        let locale = await locale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModel(for: transcriber, locale: locale)

        let file = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collected = Task { () -> (String, [TranscribedWord]) in
            var text = ""
            var words: [TranscribedWord] = []
            for try await result in transcriber.results {
                text += String(result.text.characters)
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let token = String(result.text[run.range].characters)
                    guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    words.append(TranscribedWord(text: token, start: range.start.seconds, end: range.end.seconds))
                }
            }
            return (text, words)
        }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let (text, words) = try await collected.value
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), words)
    }
}

/// Per-frame loudness of a recording, for measuring silences.
nonisolated enum AudioLevels {
    static let frameDuration: Double = 0.05

    static func frameLevels(fileURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameLength = AVAudioFrameCount(format.sampleRate * frameDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return [] }

        var levels: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameLength)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
            var sumOfSquares: Float = 0
            for i in 0..<Int(buffer.frameLength) { sumOfSquares += samples[i] * samples[i] }
            let rms = (sumOfSquares / Float(buffer.frameLength)).squareRoot()
            levels.append(20 * log10(max(rms, 1e-7)))
        }
        return levels
    }
}
