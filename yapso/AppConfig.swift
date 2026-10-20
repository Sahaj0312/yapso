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

    static let spinDuration: TimeInterval = 3.2
}
