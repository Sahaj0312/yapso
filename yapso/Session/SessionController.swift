import Foundation
import Observation
import SwiftData

/// Drives one attempt through reveal → research → 3‑2‑1 → speaking → finished.
///
/// Persistent state lives on the `Attempt` (timestamps); this only adds the transient bits
/// (the 3‑2‑1 countdown and the live recorder). Call `tick()` frequently while on screen.
@Observable
final class SessionController {
    enum Stage: Equatable {
        case revealing(landsAt: Date)
        case researching(deadline: Date)
        case countdown(Int)
        case speaking(cap: Date)
        case finished
        case forfeited
    }

    let attempt: Attempt
    let recorder = AudioRecorder()
    private(set) var stage: Stage
    private(set) var now: Date = .now
    private(set) var errorMessage: String?

    private var countdownTask: Task<Void, Never>?
    private var isAbandoned = false

    /// Must stay free of side effects: SwiftUI re-runs `SessionView.init` on every parent update and throws
    /// away the extra controllers, and a stray `tick()` from one of those would end a talk in progress.
    init(attempt: Attempt) {
        self.attempt = attempt
        self.stage = switch attempt.timeline.phase(now: .now) {
        case .revealing(let landsAt): .revealing(landsAt: landsAt)
        case .researching(let deadline): .researching(deadline: deadline)
        case .awaitingSpeech: .countdown(3)
        case .speaking(let cap): .speaking(cap: cap)
        case .finished: .finished
        case .forfeited: .forfeited
        }
        recorder.onFinish = { [weak self] in self?.finish(at: .now) }
    }

    func tick(now: Date = .now) {
        self.now = now
        guard countdownTask == nil, !isAbandoned else { return } // the countdown owns the stage while it runs

        switch attempt.timeline.phase(now: now) {
        case .revealing(let landsAt):
            stage = .revealing(landsAt: landsAt)
        case .researching(let deadline):
            stage = .researching(deadline: deadline)
        case .awaitingSpeech:
            // Time's up: speaking starts automatically. Held back only if the mic failed, until the user retries.
            if errorMessage == nil { beginCountdown() }
        case .speaking(let cap):
            if recorder.isRecording {
                stage = .speaking(cap: cap)
            } else {
                // The app was killed or the recorder died mid-talk: keep whatever was recorded.
                finish(at: min(now, cap))
            }
        case .finished:
            stage = .finished
        case .forfeited:
            stage = .forfeited
        }
    }

    /// "I'm ready" during research.
    func startEarly() {
        beginCountdown()
    }

    /// Practice only: tapping through the spin starts the research clock now.
    func skipReveal() {
        guard attempt.kind == .practice, case .revealing = stage else { return }
        attempt.revealedAt = .now
        save()
        ResearchNotifications.cancel(attemptID: attempt.id)
        let id = attempt.id, title = attempt.topicTitle, deadline = attempt.timeline.researchDeadline
        Task { await ResearchNotifications.schedule(attemptID: id, topicTitle: title, deadline: deadline) }
        tick()
    }

    /// Practice and scenarios only: gives up before speaking. Stops touching the attempt so the owner can delete it once
    /// this screen is gone (deleting it while it's still rendered would crash).
    func abandon() {
        guard attempt.kind == .practice || attempt.kind == .scenario, attempt.speakingStartedAt == nil else { return }
        isAbandoned = true
        countdownTask?.cancel()
        countdownTask = nil
        ResearchNotifications.cancel(attemptID: attempt.id)
    }

    /// "Done" while speaking.
    func stopSpeaking() {
        recorder.stop()
    }

    func retryAfterError() {
        errorMessage = nil
        tick()
    }

    /// Leaving the app ends a talk in progress (no restarts) and pauses a countdown until the user returns.
    func appDidEnterBackground() {
        if recorder.isRecording {
            recorder.stop()
        } else if countdownTask != nil {
            countdownTask?.cancel()
            countdownTask = nil
            tick()
        }
    }

    private func beginCountdown() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            for n in [3, 2, 1] {
                self?.stage = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            await self?.startRecording()
            self?.countdownTask = nil
        }
    }

    private func startRecording() async {
        let fileName = "\(attempt.id.uuidString).caf"
        do {
            try await recorder.start(url: Recordings.url(for: fileName), maxDuration: attempt.timeline.speakingCap)
        } catch {
            errorMessage = error.localizedDescription
            tick()
            return
        }
        let startedAt = Date.now
        attempt.audioFileName = fileName
        attempt.speakingStartedAt = startedAt
        save()
        ResearchNotifications.cancel(attemptID: attempt.id)
        stage = .speaking(cap: startedAt.addingTimeInterval(attempt.timeline.speakingCap))
    }

    private func finish(at end: Date) {
        guard attempt.endedAt == nil, let startedAt = attempt.speakingStartedAt else { return }
        attempt.endedAt = end
        attempt.secondsUsed = max(0, min(end.timeIntervalSince(startedAt), attempt.timeline.speakingCap))
        save()
        stage = .finished
    }

    private func save() {
        try? attempt.modelContext?.save()
    }
}
