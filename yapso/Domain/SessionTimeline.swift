import Foundation

nonisolated enum AttemptKind: String, Codable, Sendable {
    case daily, practice
}

nonisolated enum SessionPhase: Equatable, Sendable {
    /// The rolodex is still spinning; the research clock starts when it lands.
    case revealing(landsAt: Date)
    /// The 10-minute research window is running.
    case researching(deadline: Date)
    /// Research time is up but recording hasn't started (the user was away). Show 3‑2‑1, then record.
    case awaitingSpeech
    /// Recording started; it can run until `cap` at the latest.
    case speaking(cap: Date)
    case finished
    /// A daily attempt that never reached speaking and whose window has fully passed.
    case forfeited
}

/// Derives where an attempt is in the reveal → research → speak flow purely from its timestamps,
/// so the state survives the app being killed or backgrounded.
nonisolated struct SessionTimeline: Sendable {
    static let defaultResearchDuration: TimeInterval = 10 * 60
    static let speakingCap: TimeInterval = 90

    var kind: AttemptKind
    /// When the rolodex lands and the research clock starts.
    var revealedAt: Date
    var speakingStartedAt: Date?
    var endedAt: Date?
    var researchDuration: TimeInterval = defaultResearchDuration

    var researchDeadline: Date { revealedAt.addingTimeInterval(researchDuration) }

    func phase(now: Date, calendar: Calendar = .current) -> SessionPhase {
        if endedAt != nil { return .finished }
        if let speakingStartedAt { return .speaking(cap: speakingStartedAt.addingTimeInterval(Self.speakingCap)) }
        if now < revealedAt { return .revealing(landsAt: revealedAt) }
        if now < researchDeadline { return .researching(deadline: researchDeadline) }
        // A late-night reveal still counts: only forfeit once the day the research ended in is over.
        if kind == .daily, DayKey(researchDeadline, calendar: calendar) < DayKey(now, calendar: calendar) {
            return .forfeited
        }
        return .awaitingSpeech
    }
}
