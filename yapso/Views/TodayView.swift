import SwiftUI
import SwiftData

enum TopicStore {
    static let all: [Topic] = (try? TopicLibrary.loadBundled()) ?? []
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Attempt.revealedAt, order: .reverse) private var attempts: [Attempt]
    @State private var micDenied = false

    var body: some View {
        let now = Date.now
        ZStack {
            if let active = activeAttempt(now: now) {
                SessionView(attempt: active)
                    .id(active.id)
                    .transition(.opacity)
            } else if let done = todaysDailyAttempt(now: now) {
                ResultsView(attempt: done, history: attempts, streak: streak(now: now))
                    .transition(.opacity)
            } else {
                ReadyView(streak: streak(now: now)) { Task { await spin() } }
                    .transition(.opacity)
                    .task {
                        if let demoFile = AppConfig.demoAttemptFile { insertDemoAttempt(fileName: demoFile) }
                        if AppConfig.autoSpin {
                            try? await Task.sleep(for: .seconds(1.5))
                            await spin()
                        }
                    }
            }
        }
        .animation(.smooth(duration: 0.5), value: activeAttempt(now: now)?.id)
        .alert("Yapso needs your microphone", isPresented: $micDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your topic stays hidden until recording works, so you never lose a day to a permission prompt.")
        }
    }

    private func activeAttempt(now: Date) -> Attempt? {
        attempts.first { attempt in
            switch attempt.timeline.phase(now: now) {
            case .finished, .forfeited: false
            default: true
            }
        }
    }

    private func todaysDailyAttempt(now: Date) -> Attempt? {
        let today = DayKey(now).rawValue
        return attempts.first { $0.kind == .daily && $0.dayKey == today && $0.endedAt != nil }
    }

    private func streak(now: Date) -> Int {
        let days = Set(attempts.filter { $0.kind == .daily && $0.endedAt != nil }.compactMap(\.day))
        return Streak.current(completedDays: days, today: DayKey(now))
    }

    private func insertDemoAttempt(fileName: String) {
        guard let topic = TopicStore.all.first(where: { $0.id == "the-rosetta-stone" }) ?? TopicStore.all.first else { return }
        let attempt = Attempt(kind: .daily, topic: topic, revealedAt: .now.addingTimeInterval(-700))
        attempt.speakingStartedAt = .now.addingTimeInterval(-90)
        attempt.endedAt = .now.addingTimeInterval(-74)
        attempt.secondsUsed = 16
        attempt.audioFileName = fileName
        // The Simulator can't run on-device transcription; a `<file>.json` TranscriptTimeline stands in for it.
        let timelineURL = Recordings.url(for: fileName).deletingPathExtension().appendingPathExtension("json")
        if let data = try? Data(contentsOf: timelineURL),
           let timeline = try? JSONDecoder().decode(TranscriptTimeline.self, from: data) {
            let metrics = DeliveryAnalyzer.metrics(for: timeline, secondsUsed: attempt.secondsUsed)
            attempt.transcript = timeline.text
            attempt.transcriptTimeline = timeline
            attempt.wordCount = metrics.wordCount
            attempt.wordsPerMinute = metrics.wordsPerMinute
            attempt.fillerCount = metrics.fillerCount
            attempt.longestPauseSeconds = metrics.longestPause
            attempt.isTranscribed = true
        }
        context.insert(attempt)
        try? context.save()
    }

    private func spin() async {
        // Permissions come before the reveal, so nobody burns a day on a prompt.
        let micGranted = Permissions.microphoneGranted ? true : await Permissions.requestMicrophone()
        guard micGranted else { micDenied = true; return }
        await Permissions.requestNotificationsIfUndetermined()

        let used = Set(attempts.map(\.topicID))
        guard let topic = TopicPicker.pick(from: TopicStore.all, excluding: used) else { return }
        let attempt = Attempt(kind: .daily, topic: topic, revealedAt: .now.addingTimeInterval(AppConfig.spinDuration))
        context.insert(attempt)
        try? context.save()
        await ResearchNotifications.schedule(attemptID: attempt.id, topicTitle: topic.title, deadline: attempt.timeline.researchDeadline)
    }
}

private struct ReadyView: View {
    let streak: Int
    let onSpin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StreakLabel(streak: streak)
            Spacer()
            Eyebrow("Today")
                .padding(.bottom, 10)
            Text("Your topic is ready.")
                .font(.largeTitle.weight(.bold))
            Text("10 minutes to research. 90 seconds to explain it. One go.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
            Button("Spin", action: onSpin)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
}

struct StreakLabel: View {
    let streak: Int

    var body: some View {
        Label(streak == 1 ? "1 day" : "\(streak) days", systemImage: "flame")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(streak > 0 ? .primary : .secondary)
    }
}
