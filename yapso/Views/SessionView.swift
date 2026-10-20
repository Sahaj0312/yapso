import SwiftUI

/// Hosts one in-progress attempt and switches screens as it moves through its stages.
struct SessionView: View {
    @State private var controller: SessionController
    @Environment(\.scenePhase) private var scenePhase

    init(attempt: Attempt) {
        _controller = State(initialValue: SessionController(attempt: attempt))
    }

    var body: some View {
        let attempt = controller.attempt
        ZStack {
            switch controller.stage {
            case .revealing(let landsAt):
                RolodexView(target: attempt.topicTitle, domain: attempt.topicDomain, landsAt: landsAt, pool: TopicStore.all)
                    .transition(.opacity)
            case .researching(let deadline):
                ResearchView(
                    attempt: attempt,
                    remaining: deadline.timeIntervalSince(controller.now),
                    total: attempt.timeline.researchDuration,
                    onReady: controller.startEarly
                )
                .transition(.opacity.combined(with: .offset(y: 12)))
            case .countdown(let value):
                CountdownView(value: value)
                    .transition(.opacity)
            case .speaking(let cap):
                SpeakingView(
                    topicTitle: attempt.topicTitle,
                    remaining: cap.timeIntervalSince(controller.now),
                    levels: controller.recorder.levels,
                    onDone: controller.stopSpeaking
                )
                .transition(.opacity)
            case .finished, .forfeited:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.5), value: stageKey)
        .task {
            while !Task.isCancelled {
                controller.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.appDidEnterBackground() }
        }
        .alert("Microphone unavailable", isPresented: .constant(controller.errorMessage != nil)) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Try again") { controller.retryAfterError() }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    /// Identifies the screen, ignoring the payloads, so transitions run only when the screen changes.
    private var stageKey: String {
        switch controller.stage {
        case .revealing: "revealing"
        case .researching: "researching"
        case .countdown: "countdown"
        case .speaking: "speaking"
        case .finished: "finished"
        case .forfeited: "forfeited"
        }
    }
}
