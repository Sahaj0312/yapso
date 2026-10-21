import SwiftUI
import SwiftData

enum TopicStore {
    static let all: [Topic] = (try? TopicLibrary.loadBundled()) ?? []
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Attempt.revealedAt, order: .reverse) private var attempts: [Attempt]
    @Query(sort: \CoachProfile.updatedAt, order: .reverse) private var profiles: [CoachProfile]
    @Environment(\.scenePhase) private var scenePhase
    @State private var micDenied = false
    /// Rehearsals stopped during prep: hidden at once, deleted once their screen is gone.
    @State private var abandonedIDs: Set<UUID> = []
    /// The just-finished talk whose full result the user has closed, so Today goes back to the home screen.
    @AppStorage("dismissedResultID") private var dismissedResultID = ""
    /// The calibration whose result the user has moved on from.
    @AppStorage("seenCalibrationID") private var seenCalibrationID = ""

    var body: some View {
        let now = Date.now
        ZStack {
            if let active = activeAttempt(now: now) {
                SessionView(attempt: active, onAbandon: abandon)
                    .id(active.id)
                    .transition(.opacity)
                    // A talk in progress owns the screen.
                    .toolbarVisibility(.hidden, for: .tabBar)
            } else if let calibration = unseenCalibration {
                CalibrationResultView(attempt: calibration, history: attempts) {
                    seenCalibrationID = calibration.id.uuidString
                }
                .id(calibration.id)
                .transition(.opacity)
            } else if Calibration.isNeeded(attempts: attempts) {
                CalibrationIntroView { prompt in Task { await startCalibration(prompt) } }
                    .transition(.opacity)
            } else if let fresh = freshResult(now: now) {
                ResultsView(attempt: fresh, history: attempts, streak: fresh.kind == .daily ? streak(now: now) : nil) {
                    freshFooter(for: fresh)
                }
                .id(fresh.id)
                .transition(.opacity)
            } else {
                home(now: now)
                    .transition(.opacity)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .animation(.smooth(duration: 0.5), value: activeAttempt(now: now)?.id)
        .animation(.smooth(duration: 0.5), value: freshResult(now: now)?.id)
        .animation(.smooth(duration: 0.5), value: unseenCalibration?.id)
        .task { Scenarios.dropAbandoned(attempts: attempts, in: context) }
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

    /// Today's topic on top, then the scenario library.
    private func home(now: Date) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 20) {
                        TodayHeader(streak: streak(now: now))
                        DailyCard(attempt: todaysDaily(now: now), history: attempts) { Task { await spin() } }
                    }
                    ScenarioShelf(attempts: attempts, onboarding: profiles.first?.memory.onboarding) { scenario in
                        Task { await startScenario(scenario) }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .background(Color.paper.ignoresSafeArea())
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let attempt = attempts.first(where: { $0.id == id }) {
                    ResultsView(attempt: attempt, history: attempts, streak: nil) {
                        if attempt.kind == .scenario {
                            ScenarioRetryButton(attempt: attempt, attempts: attempts)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .task {
            if let demoFile = AppConfig.demoAttemptFile { insertDemoAttempt(fileName: demoFile) }
            if AppConfig.autoSpin, todaysDaily(now: .now) == nil {
                try? await Task.sleep(for: .seconds(1.5))
                await spin()
            }
            if AppConfig.autoScenario, let first = ScenarioStore.all.first {
                try? await Task.sleep(for: .seconds(1.5))
                await startScenario(first)
            }
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

    private func todaysDaily(now: Date) -> Attempt? {
        let today = DayKey(now).rawValue
        return attempts.first { $0.kind == .daily && $0.dayKey == today && $0.endedAt != nil }
    }

    /// The talk just finished today (daily or rehearsal), shown in full until the user closes it.
    private func freshResult(now: Date) -> Attempt? {
        let today = DayKey(now).rawValue
        guard let latest = attempts.first(where: { $0.kind != .calibration && $0.dayKey == today && $0.endedAt != nil }),
              latest.id.uuidString != dismissedResultID else { return nil }
        return latest
    }

    @ViewBuilder
    private func freshFooter(for attempt: Attempt) -> some View {
        VStack(spacing: 10) {
            if attempt.kind == .scenario {
                ScenarioRetryButton(attempt: attempt, attempts: attempts) { dismissedResultID = attempt.id.uuidString }
                Button("Done") { dismissedResultID = attempt.id.uuidString }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Done") { dismissedResultID = attempt.id.uuidString }
                    .buttonStyle(PrimaryButtonStyle())
                Text("New topic tomorrow. Rehearsals are open any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    /// The latest finished calibration, until the user moves on from its result.
    private var unseenCalibration: Attempt? {
        attempts.first { $0.kind == .calibration && $0.endedAt != nil }
            .flatMap { $0.id.uuidString == seenCalibrationID ? nil : $0 }
    }

    private func startCalibration(_ prompt: String) async {
        if await Calibration.start(prompt: prompt, in: context) == nil { micDenied = true }
    }

    private func startScenario(_ scenario: Scenario) async {
        if await Scenarios.start(scenario, attempts: attempts, in: context) == nil, !Permissions.microphoneGranted {
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
