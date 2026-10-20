import Foundation

nonisolated enum AppConfig {
    /// Launch with `-yapsoShortTimers` (Debug only) to make research 20s instead of 10 minutes.
    static var researchDuration: TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-yapsoShortTimers") { return 20 }
        #endif
        return SessionTimeline.defaultResearchDuration
    }

    /// Launch with `-yapsoAutoSpin` (Debug only) to spin automatically, for driving the flow without taps.
    static var autoSpin: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoAutoSpin")
        #else
        return false
        #endif
    }

    /// Launch with `-yapsoDemoAttempt <file in Recordings>` (Debug only) to create a finished attempt from
    /// an existing recording, for exercising transcription and results where the mic is unavailable.
    static var demoAttemptFile: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "yapsoDemoAttempt")
        #else
        return nil
        #endif
    }

    /// Launch with `-yapsoResetData` (Debug only) to delete all attempts on launch, for retesting the daily flow.
    static var resetData: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoResetData")
        #else
        return false
        #endif
    }

    /// The Worker that proxies Deepgram and OpenAI. Unset until it's deployed (build step 4).
    static let apiBaseURL: URL? = nil

    /// Launch with `-yapsoDeepgramKey <key>` (Debug only) to call Deepgram directly, before the Worker exists.
    /// Launch arguments aren't persisted, so the key never lands on disk.
    static var deepgramKey: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "yapsoDeepgramKey").flatMap { $0.isEmpty ? nil : $0 }
        #else
        return nil
        #endif
    }

    static let spinDuration: TimeInterval = 3.2
}
