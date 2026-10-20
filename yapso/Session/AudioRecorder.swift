import AVFoundation
import Observation
import os

private let log = Logger(subsystem: "com.sahaj03.yapso", category: "recorder")

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
        // Activating the session can block for a moment; do it off the main thread.
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }.value

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
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: maxDuration) else {
            log.error("record(forDuration:) refused to start")
            throw RecorderError.couldNotStart
        }
        log.info("recording started: \(url.lastPathComponent, privacy: .public)")

        self.recorder = recorder
        isRecording = true
        levels = Array(repeating: 0, count: Self.levelCount)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            // Only a new interruption (call, Siri) ends the talk; "interruption ended" notices are ignored.
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
            log.info("audio session interrupted")
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
        log.info("recording finished after \(recorder.currentTime, privacy: .public)s, successfully: \(flag, privacy: .public)")
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        log.error("encode error: \(String(describing: error), privacy: .public)")
        Task { @MainActor in self.finish() }
    }

    nonisolated enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Couldn't start recording. Check microphone access in Settings." }
    }
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

    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Deletes recordings older than 30 days. Transcripts, metrics and feedback are kept.
    static func purgeExpired(now: Date = .now) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            guard let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  now.timeIntervalSince(created) > retention else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
