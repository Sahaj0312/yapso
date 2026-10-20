import Charts
import SwiftData
import SwiftUI

/// Trends across daily talks and what the coach is watching. Pro only; practice talks don't count.
struct ProgressScreen: View {
    @Query(sort: \Attempt.revealedAt) private var attempts: [Attempt]
    @Query(sort: \CoachProfile.updatedAt, order: .reverse) private var profiles: [CoachProfile]

    var body: some View {
        NavigationStack {
            ScrollView {
                if AppConfig.hasPro {
                    content
                } else {
                    content
                        .blur(radius: 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .overlay(alignment: .top) { ProLock().padding(.top, 120) }
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Progress")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 36) {
            StatsRow(days: completedDays, talks: talks.count)
            if talks.count >= 2 {
                TrendCard(talks: Array(talks.suffix(30)))
            } else {
                Text("Your trends start after two daily talks.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
            }
            FocusAreas(memory: profiles.first?.memory ?? CoachMemory())
        }
        .padding(24)
    }

    /// Daily talks with something said, oldest first.
    private var talks: [Attempt] {
        attempts.filter { $0.kind == .daily && $0.isTranscribed && $0.wordCount > 0 }
    }

    private var completedDays: Set<DayKey> {
        Set(attempts.filter { $0.kind == .daily && $0.endedAt != nil }.compactMap(\.day))
    }
}

private struct StatsRow: View {
    let days: Set<DayKey>
    let talks: Int

    var body: some View {
        HStack(spacing: 12) {
            stat("Streak", Streak.current(completedDays: days, today: DayKey(.now)))
            stat("Best", Streak.best(completedDays: days))
            stat("Talks", talks)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: 28, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case ratings = "Ratings", pace = "Pace", fillers = "Fillers", pauses = "Pauses"
    var id: Self { self }
}

private struct TrendCard: View {
    let talks: [Attempt]
    @State private var metric: TrendMetric = .ratings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: metric)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            chart
                .frame(minHeight: 220)
                .animation(.smooth, value: metric)
        }
    }

    private var caption: String {
        switch metric {
        case .ratings: "The coach's 1–5 ratings over your last \(talks.count) talks."
        case .pace: "Words per minute. Conversational pace is 130–160."
        case .fillers: "Filler words per talk."
        case .pauses: "Longest pause in each talk, in seconds."
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .ratings:
            RatingGrid(talks: talks)
        case .pace:
            singleSeries(\.wordsPerMinute) {
                RectangleMark(yStart: .value("Low", 130), yEnd: .value("High", 160))
                    .foregroundStyle(Color.primary.opacity(0.06))
            }
        case .fillers:
            singleSeries { Double($0.fillerCount) }
        case .pauses:
            singleSeries(\.longestPauseSeconds)
        }
    }

    private func singleSeries(_ value: @escaping (Attempt) -> Double) -> some View {
        singleSeries(value) { EmptyChartContent() }
    }

    private func singleSeries<Band: ChartContent>(_ value: @escaping (Attempt) -> Double,
                                                  @ChartContentBuilder band: () -> Band) -> some View {
        Chart {
            band()
            ForEach(talks) { talk in
                LineMark(x: .value("Talk", talk.revealedAt), y: .value(metric.rawValue, value(talk)))
                    .foregroundStyle(Color.primary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Talk", talk.revealedAt), y: .value(metric.rawValue, value(talk)))
                    .foregroundStyle(Color.primary)
                    .symbolSize(24)
            }
        }
    }
}

/// One small chart per criterion: four overlaid lines of whole-number scores are unreadable.
private struct RatingGrid: View {
    let talks: [Attempt]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow { card(.clarity); card(.structure) }
            GridRow { card(.accuracy); card(.ownership) }
        }
    }

    private func card(_ criterion: ContentCriterion) -> some View {
        let points = talks.compactMap { talk in
            talk.contentFeedback?.ratings.first { $0.criterion == criterion }.map { (date: talk.revealedAt, score: $0.score) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(criterion.title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let latest = points.last?.score {
                    Text("\(latest)").font(.title3.weight(.semibold).monospacedDigit())
                }
            }
            Chart(points, id: \.date) { point in
                AreaMark(x: .value("Talk", point.date), yStart: .value("Floor", 1), yEnd: .value("Score", point.score))
                    .foregroundStyle(Color.primary.opacity(0.06))
                LineMark(x: .value("Talk", point.date), y: .value("Score", point.score))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .chartYScale(domain: 1...5)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Chart content that draws nothing, for series without a reference band.
private struct EmptyChartContent: ChartContent {
    var body: some ChartContent {
        RuleMark(y: .value("None", 0)).foregroundStyle(.clear)
    }
}

private struct FocusAreas: View {
    let memory: CoachMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Your focus areas")
            if memory.weaknesses.isEmpty && memory.strengths.isEmpty {
                Text("After a few talks, your coach will note what to work on here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(memory.weaknesses, id: \.self) { area in
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.label).font(.headline)
                    Text(area.evidence == "From onboarding" ? "From what you told us" : area.evidence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
            }
            if !memory.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Working for you")
                        .padding(.top, 8)
                    ForEach(memory.strengths, id: \.self) { strength in
                        Label(strength, systemImage: "checkmark")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct ProLock: View {
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.title2)
            Text("Progress is part of Pro").font(.headline)
            Text("See your ratings, pace and fillers improve, and what your coach is watching.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock Pro") { showPaywall = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        // Solid, not material: material makes the button's ink vibrant (washed-out grey).
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
        .padding(.horizontal, 24)
        .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
    }
}
