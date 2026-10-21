import SwiftUI
import SwiftData

/// Every finished or forfeited talk, newest first, grouped by month.
struct HistoryView: View {
    @Query(sort: \Attempt.revealedAt, order: .reverse) private var attempts: [Attempt]
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            Group {
                if past.isEmpty {
                    VStack(spacing: 14) {
                        Illustration(name: "IllustrationSeedling", height: 120)
                            .padding(.bottom, 10)
                        Text("No talks yet")
                            .font(.displaySmall)
                        Text("Every talk you give lands here, with its transcript, recording and feedback.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(months, id: \.title) { month in
                            Section {
                                ForEach(month.attempts) { attempt in
                                    if attempt.endedAt != nil {
                                        NavigationLink(value: attempt.id) { HistoryRow(attempt: attempt) }
                                            .listRowBackground(Color.paper)
                                    } else {
                                        HistoryRow(attempt: attempt)
                                            .listRowBackground(Color.paper)
                                    }
                                }
                            } header: {
                                Text(month.title)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let attempt = attempts.first(where: { $0.id == id }) {
                    ResultsView(attempt: attempt, history: attempts, streak: nil) {
                        if attempt.kind == .scenario {
                            ScenarioRetryButton(attempt: attempt, attempts: attempts) { router.tab = .today }
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    /// Talks that are over: spoken, or forfeited by never speaking.
    private var past: [Attempt] {
        let now = Date.now
        return attempts.filter { attempt in
            switch attempt.timeline.phase(now: now) {
            case .finished, .forfeited: true
            default: false
            }
        }
    }

    private var months: [(title: String, attempts: [Attempt])] {
        var groups: [(title: String, attempts: [Attempt])] = []
        for attempt in past {
            let title = attempt.revealedAt.formatted(.dateTime.month(.wide).year())
            if groups.last?.title == title {
                groups[groups.count - 1].attempts.append(attempt)
            } else {
                groups.append((title, [attempt]))
            }
        }
        return groups
    }
}

private struct HistoryRow: View {
    let attempt: Attempt

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 0) {
                Text(attempt.revealedAt.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(attempt.revealedAt.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(attempt.topicTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(spoken ? .primary : .secondary)
                    .lineLimit(2)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let score = averageScore {
                Text(score, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12), in: .capsule)
                    .foregroundStyle(Color.ember)
                    .accessibilityLabel("Average rating \(score.formatted(.number.precision(.fractionLength(1)))) out of 5")
            }
        }
        .padding(.vertical, 6)
    }

    private var spoken: Bool { attempt.endedAt != nil }

    private var details: String {
        var parts = [attempt.topicDomain]
        if attempt.kind == .practice { parts.append("Practice") }
        if attempt.kind == .scenario { parts.append("Rehearsal") }
        if !spoken {
            parts.append("Not spoken")
        } else {
            parts.append(attempt.secondsUsed.clockString)
            if attempt.wordCount > 0 { parts.append("\(Int(attempt.wordsPerMinute.rounded())) wpm") }
        }
        return parts.joined(separator: " · ")
    }

    private var averageScore: Double? {
        guard attempt.feedbackStatus == .complete, let ratings = attempt.contentFeedback?.ratings, !ratings.isEmpty else { return nil }
        return Double(ratings.map(\.score).reduce(0, +)) / Double(ratings.count)
    }
}
