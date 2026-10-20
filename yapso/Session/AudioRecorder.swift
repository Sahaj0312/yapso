import AVFoundation
import Observation

/// Records the 90-second talk to a local file and publishes live levels for the waveform.
/// Stops itself at the cap, and on any audio-session interruption (calls, Siri) — interruptions are bad luck.
@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    /// Most recent normalized levels (0…1), oldest first.
    private(set) var levels: [Float] = Array(repeating: 0, count: AudioRecorder.levelCount)

    /// Called once when recording ends for any reason: cap reached, `stop()`, or interruption.
    var onFinish: (() -> Void)?

    static let levelCount = 48

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    func start(url: URL, maxDuration: TimeInterval) async throws {
        // Session activation and queue setup can block for a while; keep them off the main thread.
        let prepared = try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            // Linear PCM in CAF: stays readable even if the app dies mid-recording.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw RecorderError.couldNotStart }
            return PreparedRecorder(recorder: recorder)
        }.value

        let recorder = prepared.recorder
        recorder.delegate = self
        guard recorder.record(forDuration: maxDuration) else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        isRecording = true
        levels = Array(repeating: 0, count: Self.levelCount)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        startMetering()
    }

    func stop() {
        recorder?.stop() // triggers audioRecorderDidFinishRecording
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                // -50 dB and below reads as silence.
                let normalized = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
                self.levels.removeFirst()
                self.levels.append(normalized)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func finish() {
        guard isRecording else { return }
        isRecording = false
        meterTask?.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onFinish?()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.finish() }
    }

    nonisolated enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Couldn't start recording. Check microphone access in Settings." }
    }
}

/// Hands a freshly prepared recorder from the background setup task to the main actor.
nonisolated private struct PreparedRecorder: @unchecked Sendable {
    let recorder: AVAudioRecorder
}

nonisolated enum Recordings {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }
}
