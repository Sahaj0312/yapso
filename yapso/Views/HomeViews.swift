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

/// "Practice for real life": scenario rows grouped by situation, the user's own situations first.
struct ScenarioShelf: View {
    let attempts: [Attempt]
    let onboarding: OnboardingAnswers?
    let onStart: (Scenario) -> Void

    @State private var showPaywall = false
    @State private var limitReached = false

    var body: some View {
        let availability = Scenarios.availability(attempts: attempts)
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Practice for real life")
                Text("Rehearse the moments that matter.")
                    .font(.displaySmall)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption(availability))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(ScenarioCategory.ordered(for: onboarding), id: \.self) { category in
                VStack(alignment: .leading, spacing: 12) {
                    Label(category.title, systemImage: category.symbol)
                        .font(.headline)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(ScenarioStore.all.filter { $0.category == category }) { scenario in
                                ScenarioCard(scenario: scenario, best: bestScore(for: scenario)) {
                                    switch availability {
                                    case .available: onStart(scenario)
                                    case .needsPro: showPaywall = true
                                    case .limitReached: limitReached = true
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -24)
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
        .alert("That's \(Scenarios.dailyLimit) for today", isPresented: $limitReached) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rest the voice. Rehearsals open again tomorrow.")
        }
    }

    private func caption(_ availability: Scenarios.Availability) -> String {
        switch availability {
        case .available where !AppConfig.hasPro: "Your first rehearsal is free. 30 seconds to think, 90 to answer."
        case .available: "30 seconds to think, 90 to answer, as many takes as you like."
        case .needsPro: "Rehearsals are part of Pro."
        case .limitReached: "That's \(Scenarios.dailyLimit) for today. Back tomorrow."
        }
    }

    private func bestScore(for scenario: Scenario) -> Double? {
        attempts.filter { $0.kind == .scenario && $0.topicID == scenario.id }.compactMap(\.averageScore).max()
    }
}

private struct ScenarioCard: View {
    let scenario: Scenario
    let best: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scenario.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(scenario.prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    if let best {
                        Label(best.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ember)
                    } else {
                        Text("90s").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ember)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(width: 196, height: 116, alignment: .topLeading)
            .padding(16)
            .cardBackground(cornerRadius: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
