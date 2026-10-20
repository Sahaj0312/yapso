import AVFoundation
import Speech

nonisolated enum Permissions {
    static var microphoneGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static func requestSpeechRecognition() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}
