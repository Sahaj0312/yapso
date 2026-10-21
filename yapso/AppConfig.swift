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

    /// Launch with `-yapsoAutoScenario` (Debug only) to start the first scenario as soon as the home screen shows.
    static var autoScenario: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoAutoScenario")
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

    /// Launch with `-yapsoResetData` (Debug only) to delete all attempts and the coach profile on launch, for retesting the daily flow.
    static var resetData: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoResetData")
        #else
        return false
        #endif
    }

    /// The Worker that proxies Deepgram and OpenAI (source in `worker/`).
    static let apiBaseURL = URL(string: "https://yapso-api.sahaj0091.workers.dev")!

    /// Launch with `-yapsoDirectDeepgram` (Debug only) to skip the Worker and call Deepgram directly with
    /// `DEEPGRAM_DEV_KEY` from the gitignored `Config/Secrets.xcconfig`. Release builds never contain the key.
    static var directDeepgramKey: String? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-yapsoDirectDeepgram"),
              let key = (Bundle.main.object(forInfoDictionaryKey: "YapsoDeepgramDevKey") as? String)?
                .trimmingCharacters(in: .whitespaces), !key.isEmpty else { return nil }
        return key
        #else
        return nil
        #endif
    }

    /// Whether the user has Pro. Everyone does until RevenueCat is in (build step 8); launch with
    /// `-yapsoFree` (Debug only) to see the free tier's one-feedback limit.
    static var hasPro: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-yapsoFree")
        #else
        return true
        #endif
    }

    /// Identifies this install to the Worker's rate limits. Not tied to the user or iCloud.
    static var deviceID: String {
        let key = "yapsoDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// Launch with `-yapsoTab history|progress` (Debug only) to open on that tab.
    static var initialTab: AppTab {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "yapsoTab").flatMap(AppTab.init) ?? .today
        #else
        return .today
        #endif
    }

    /// Launch with `-yapsoOnboarding` (Debug only) to show onboarding even after it's been completed.
    static var forceOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoOnboarding")
        #else
        return false
        #endif
    }

    /// Launch with `-yapsoCalibrationNote` (Debug only) to open the calibration result on the note, not the reveal.
    static var calibrationNote: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-yapsoCalibrationNote")
        #else
        return false
        #endif
    }

    static let spinDuration: TimeInterval = 3.2
}
