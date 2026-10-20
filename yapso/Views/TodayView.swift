import SwiftUI
import SwiftData

enum TopicStore {
    static let all: [Topic] = (try? TopicLibrary.loadBundled()) ?? []
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Attempt.revealedAt, order: .reverse) private var attempts: [Attempt]
    @Environment(\.scenePhase) private var scenePhase
    @State private var micDenied = false
    /// Practice attempts stopped during research: hidden at once, deleted once their screen is gone.
    @State private var abandonedIDs: Set<UUID> = []
    /// The practice result the user has closed, so Today shows the daily result again.
    @AppStorage("dismissedPracticeID") private var dismissedPracticeID = ""

    var body: some View {
        let now = Date.now
        ZStack {
            if let active = activeAttempt(now: now) {
                SessionView(attempt: active, onAbandon: abandon)
                    .id(active.id)
                    .transition(.opacity)
                    // A talk in progress owns the screen.
                    .toolbarVisibility(.hidden, for: .tabBar)
            } else if let done = todaysResult(now: now) {
                ResultsView(attempt: done, history: attempts, streak: streak(now: now)) {
                    resultsFooter(for: done)
                }
                .id(done.id)
                .transition(.opacity)
                .task {
                    if AppConfig.autoPractice, done.kind == .daily, case .available = Practice.availability(attempts: attempts) {
                        try? await Task.sleep(for: .seconds(1.5))
                        await startPractice()
                    }
                }
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
        .background(Color.paper.ignoresSafeArea())
        .animation(.smooth(duration: 0.5), value: activeAttempt(now: now)?.id)
        .animation(.smooth(duration: 0.5), value: todaysResult(now: now)?.id)
        .task { Practice.dropAbandoned(attempts: attempts, in: context) }
        // Reschedules the week's reminders, skipping today once it's spun.
        .task(id: Attempt.dailyStarted(on: DayKey(now), in: attempts)) { await refreshReminder() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshReminder() } }
        }
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
            guard !abandonedIDs.contains(attempt.id) else { return false }
            switch attempt.timeline.phase(now: now) {
            case .finished, .forfeited: return false
            default: return true
            }
        }
    }

    private func refreshReminder() async {
        await DailyReminder.refresh(todayStarted: Attempt.dailyStarted(on: DayKey(.now), in: attempts))
    }

    /// The latest finished talk today: a just-finished practice until it's closed, otherwise the daily.
    private func todaysResult(now: Date) -> Attempt? {
        let today = DayKey(now).rawValue
        let finished = attempts.filter { $0.dayKey == today && $0.endedAt != nil }
        if let latest = finished.first, latest.kind == .practice, latest.id.uuidString != dismissedPracticeID {
            return latest
        }
        return finished.first { $0.kind == .daily }
    }

    @ViewBuilder
    private func resultsFooter(for attempt: Attempt) -> some View {
        let availability = Practice.availability(attempts: attempts)
        if attempt.kind == .practice {
            VStack(spacing: 10) {
                if case .available = availability {
                    Button("Practice another topic") { Task { await startPractice() } }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Back to today's talk") { dismissedPracticeID = attempt.id.uuidString }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                PracticeCard(availability: availability) { Task { await startPractice() } }
                Text("New topic tomorrow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startPractice() async {
        if await Practice.start(attempts: attempts, in: context) == nil, !Permissions.microphoneGranted {
            micDenied = true
        }
    }

    private func abandon(_ attempt: Attempt) {
        abandonedIDs.insert(attempt.id)
        Task {
            // After the session view's exit transition, so nothing reads the deleted attempt.
            try? await Task.sleep(for: .seconds(1))
            context.delete(attempt)
            try? context.save()
            abandonedIDs.remove(attempt.id)
        }
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
            TodayHeader(streak: streak)
            Spacer()
            Illustration(name: "IllustrationRolodex", height: 210)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            Eyebrow("Today")
                .padding(.bottom, 10)
            Text("Your topic is ready.")
                .font(.display)
            Text("10 minutes to research. 90 seconds to explain it. One go.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
            Button("Spin", action: onSpin)
                .buttonStyle(PrimaryButtonStyle(fill: .ember))
        }
        .padding(24)
    }
}

/// The streak with the Settings gear beside it, at the top of Today.
struct TodayHeader: View {
    let streak: Int
    @State private var showSettings = false

    var body: some View {
        HStack {
            StreakLabel(streak: streak)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

struct StreakLabel: View {
    let streak: Int

    var body: some View {
        Label {
            Text(streak == 1 ? "1 day" : "\(streak) days")
        } icon: {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .foregroundStyle(streak > 0 ? Color.ember : .secondary)
                .symbolEffect(.bounce, value: streak)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(streak > 0 ? .primary : .secondary)
    }
}
