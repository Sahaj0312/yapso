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

    static let spinDuration: TimeInterval = 3.2
}
