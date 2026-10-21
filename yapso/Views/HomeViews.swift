import SwiftData
import SwiftUI

/// The selected tab, shared so other screens can send the user to Today (e.g. after starting a rehearsal from History).
@Observable
final class AppRouter {
    var tab: AppTab
    init(tab: AppTab) { self.tab = tab }
}

// MARK: - Today's topic

/// The daily talk at the top of Today: Spin before it's done, a summary (opening the full result) after.
struct DailyCard: View {
    let attempt: Attempt?
    let history: [Attempt]
    let onSpin: () -> Void

    var body: some View {
        if let attempt {
            NavigationLink(value: attempt.id) { done(attempt) }
                .buttonStyle(.plain)
                // Keeps transcription and feedback going if the full result was closed early.
                .task(id: attempt.id) {
                    try? await AttemptProcessor.transcribeIfNeeded(attempt)
                    try? await AttemptProcessor.requestFeedbackIfNeeded(attempt, history: history)
                }
        } else {
            ready
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Today's topic")
                    Text("Ready when you are.")
                        .font(.displaySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Illustration(name: "IllustrationRolodex", height: 72)
            }
            Text("10 minutes to research. 90 seconds to explain it. One go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Button("Spin", action: onSpin)
                .buttonStyle(PrimaryButtonStyle(fill: .ember))
                .padding(.top, 20)
        }
        .padding(20)
        .cardBackground(cornerRadius: 20)
    }

    private func done(_ attempt: Attempt) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Today · \(attempt.topicDomain)")
                Text(attempt.topicTitle)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary(attempt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let score = attempt.averageScore {
                ScoreBadge(score: score)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .cardBackground(cornerRadius: 20)
        .contentShape(.rect)
    }

    private func summary(_ attempt: Attempt) -> String {
        switch attempt.feedbackStatus {
        case .complete: "Done · new topic tomorrow"
        case .locked: "\(Int(attempt.wordsPerMinute.rounded())) wpm · \(attempt.fillerCount) fillers"
        default: attempt.isTranscribed ? "Your coach is listening back…" : "Analysing your talk…"
        }
    }
}

/// The coach's average rating, as a small ember pill.
struct ScoreBadge: View {
    let score: Double

    var body: some View {
        Text(score, format: .number.precision(.fractionLength(1)))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.ember.opacity(0.12), in: .capsule)
            .foregroundStyle(Color.ember)
            .accessibilityLabel("Average rating \(score.formatted(.number.precision(.fractionLength(1)))) out of 5")
    }
}

extension Attempt {
    /// The mean of the coach's ratings, once there are some.
    var averageScore: Double? {
        guard feedbackStatus == .complete, let ratings = contentFeedback?.ratings, !ratings.isEmpty else { return nil }
        return Double(ratings.map(\.score).reduce(0, +)) / Double(ratings.count)
    }
}

// MARK: - Scenarios

/// "Practice for real life" on Today: three rehearsals picked for the user today, then a way into the full library.
struct ScenarioShelf: View {
    let attempts: [Attempt]
    let onboarding: OnboardingAnswers?
    let onStart: (Scenario) -> Void

    @State private var browsing = false

    var body: some View {
        let order = ScenarioCategory.ordered(for: onboarding)
        let attempted = Set(attempts.filter { $0.kind == .scenario }.map(\.topicID))
        let picks = ScenarioLibrary.picks(from: ScenarioStore.all, order: order, attempted: attempted, day: DayKey(.now))
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Practice for real life")
                Text("Rehearse the moments that matter.")
                    .font(.displaySmall)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Scenarios.caption(attempts: attempts))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScenarioList(scenarios: picks, attempts: attempts, showsCategory: true, onStart: onStart)

            Button {
                browsing = true
            } label: {
                HStack {
                    Text("Browse all \(ScenarioStore.all.count) rehearsals")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.ember)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationDestination(isPresented: $browsing) {
            ScenarioBrowser(attempts: attempts, order: order, onStart: onStart)
        }
        .onAppear { if AppConfig.openBrowser { browsing = true } }
    }
}

/// Every rehearsal: a row of category chips and one list.
struct ScenarioBrowser: View {
    let attempts: [Attempt]
    let order: [ScenarioCategory]
    let onStart: (Scenario) -> Void

    @State private var category: ScenarioCategory?

    var body: some View {
        let selected = category ?? order.first ?? .interviews
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(order, id: \.self) { option in
                            Button {
                                withAnimation(.snappy(duration: 0.25)) { category = option }
                            } label: {
                                Label(option.title, systemImage: option.symbol)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(option == selected ? Color.white : .primary)
                                    .background(option == selected ? Color.ember : Color.card, in: .capsule)
                                    .overlay(Capsule().strokeBorder(option == selected ? Color.clear : Color.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -24)
                .sensoryFeedback(.selection, trigger: selected)

                Text(Scenarios.caption(attempts: attempts))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScenarioList(scenarios: ScenarioStore.all.filter { $0.category == selected }, attempts: attempts,
                             showsCategory: false, onStart: onStart)
                    .id(selected)
                    .transition(.opacity)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("Rehearsals")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Scenarios as rows in one card. Tapping one starts it, or explains why it can't.
struct ScenarioList: View {
    let scenarios: [Scenario]
    let attempts: [Attempt]
    let showsCategory: Bool
    let onStart: (Scenario) -> Void

    @State private var showPaywall = false
    @State private var limitReached = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                if index > 0 { Divider().padding(.leading, showsCategory ? 54 : 18) }
                Button {
                    switch Scenarios.availability(attempts: attempts) {
                    case .available: onStart(scenario)
                    case .needsPro: showPaywall = true
                    case .limitReached: limitReached = true
                    }
                } label: {
                    row(scenario)
                }
                .buttonStyle(.plain)
            }
        }
        .cardBackground(cornerRadius: 18)
        .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
        .alert("That's \(Scenarios.dailyLimit) for today", isPresented: $limitReached) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rest the voice. Rehearsals open again tomorrow.")
        }
    }

    private func row(_ scenario: Scenario) -> some View {
        HStack(spacing: 14) {
            if showsCategory {
                Image(systemName: scenario.category.symbol)
                    .font(.body)
                    .foregroundStyle(Color.ember)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(scenario.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(scenario.prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let best = attempts.filter({ $0.kind == .scenario && $0.topicID == scenario.id }).compactMap(\.averageScore).max() {
                ScoreBadge(score: best)
            }
            Image(systemName: "mic.fill")
                .font(.footnote)
                .foregroundStyle(Color.ember)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

/// On a past rehearsal (in History or its result): take it again, compared against this one.
struct ScenarioRetryButton: View {
    let attempt: Attempt
    let attempts: [Attempt]
    /// Called once the new attempt exists, e.g. to switch to the Today tab.
    var onStarted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var showPaywall = false

    var body: some View {
        if let scenario = ScenarioStore.scenario(id: attempt.topicID) {
            let availability = Scenarios.availability(attempts: attempts)
            Button {
                switch availability {
                case .available:
                    Task {
                        if await Scenarios.start(scenario, attempts: attempts, in: context) != nil { onStarted() }
                    }
                case .needsPro:
                    showPaywall = true
                case .limitReached:
                    break
                }
            } label: {
                Label("Try again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PrimaryButtonStyle(fill: .ember))
            .disabled(availability == .limitReached)
            .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
        }
    }
}
