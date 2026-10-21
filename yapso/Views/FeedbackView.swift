import SwiftUI

/// The coach's content feedback for a talk, in every state it can be in.
struct FeedbackSection: View {
    let attempt: Attempt
    let error: Error?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Coach")
            content
        }
        .sensoryFeedback(.success, trigger: attempt.feedbackStatus == .complete) { _, done in done }
    }

    @ViewBuilder
    private var content: some View {
        switch attempt.feedbackStatus {
        case .complete:
            if let feedback = attempt.contentFeedback {
                FeedbackBody(feedback: feedback, animated: true, isScenario: attempt.kind == .scenario)
                    .transition(.opacity)
            }
        case .locked:
            LockedFeedback()
        case .skippedEmpty:
            EmptyView()
        case .notRequested, .pending, .failed:
            // A failed request is retried whenever the screen appears, so only this session's error is shown.
            if let error {
                failure(error)
            } else {
                LoadingFeedback()
            }
        }
    }

    @ViewBuilder
    private func failure(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if APIError.isOffline(error) {
                Label("Feedback needs a connection. It'll arrive as soon as you're back online.", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            } else {
                Text("Couldn't get feedback. \(error.localizedDescription)")
                    .foregroundStyle(.secondary)
                Button("Try again", action: onRetry)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// The feedback itself: coach note, ratings, flagged claims, what was missed, and one tip.
private struct FeedbackBody: View {
    let feedback: ContentFeedback
    let animated: Bool
    /// Scenarios get "A strong answer includes" instead of "What you missed".
    var isScenario = false

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let note = feedback.coachNote {
                Text(note)
                    .font(.body)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.ember).frame(width: 3)
                    }
                    .reveal(appeared, order: 0)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(feedback.ratings.enumerated()), id: \.element.criterion) { index, rating in
                    if index > 0 { Divider() }
                    RatingRow(rating: rating, filled: appeared, order: index)
                        .padding(.vertical, 14)
                        .reveal(appeared, order: index + 1)
                }
                if let comparison = feedback.comparison {
                    Label(comparison, systemImage: "arrow.left.arrow.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .reveal(appeared, order: 5)
                }
            }

            if !feedback.flaggedClaims.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow("Check this")
                    ForEach(feedback.flaggedClaims, id: \.self) { claim in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("“\(claim.quote)”")
                                .italic()
                                .foregroundStyle(.secondary)
                            Text(claim.correction)
                        }
                    }
                }
                .reveal(appeared, order: 6)
            }

            if !feedback.whatYouMissed.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(isScenario ? "A strong answer includes" : "What you missed")
                    ForEach(feedback.whatYouMissed, id: \.self) { idea in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Color.primary.opacity(0.4)).frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                            Text(idea)
                        }
                    }
                }
                .reveal(appeared, order: 7)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Next time", systemImage: "arrow.forward.circle.fill")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ember)
                Text(feedback.nextTimeTip)
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.ember.opacity(0.08), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ember.opacity(0.25)))
            .reveal(appeared, order: 8)
        }
        .onAppear {
            if animated {
                withAnimation(.smooth(duration: 0.5)) { appeared = true }
            } else {
                appeared = true
            }
        }
    }
}

private struct RatingRow: View {
    let rating: CriterionRating
    let filled: Bool
    let order: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rating.criterion.title).font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { step in
                        Capsule()
                            .fill(filled && step <= rating.score ? Color.ember : Color.primary.opacity(0.1))
                            .frame(width: 16, height: 6)
                            .animation(.smooth.delay(0.25 + Double(order) * 0.1 + Double(step) * 0.05), value: filled)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(rating.score) out of 5")
            }
            Text(rating.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A placeholder in the feedback's shape while the coach works.
private struct LoadingFeedback: View {
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Your coach is listening back…").foregroundStyle(.secondary)
            }
            FeedbackBody(feedback: .sample, animated: false)
                .redacted(reason: .placeholder)
                .opacity(pulsing ? 0.35 : 0.7)
                .animation(.easeInOut(duration: 1).repeatForever(), value: pulsing)
                .onAppear { pulsing = true }
                .accessibilityHidden(true)
        }
    }
}

/// Free users past their one feedback: the same sample for everyone, blurred, behind the Pro pitch.
private struct LockedFeedback: View {
    @State private var showPaywall = false

    var body: some View {
        FeedbackBody(feedback: .sample, animated: false)
            .blur(radius: 7)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill").font(.title2)
                    Text("Coach feedback is part of Pro")
                        .font(.headline)
                    Text("Ratings, what you missed, and a tip for tomorrow, every day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Unlock Pro") { showPaywall = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
                // Solid, not material: material makes the button's ink vibrant (washed-out grey).
                .background(Color.card, in: .rect(cornerRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                .padding(.horizontal, 8)
            }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .feedbackUsed) }
    }
}

private extension View {
    /// Fades and lifts a block into place, staggered by `order`.
    func reveal(_ shown: Bool, order: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(.smooth(duration: 0.5).delay(Double(order) * 0.08), value: shown)
    }
}

extension ContentCriterion {
    var title: String {
        switch self {
        case .clarity: "Clarity"
        case .structure: "Structure"
        case .accuracy: "Accuracy"
        case .ownership: "Ownership"
        case .relevance: "Relevance"
        case .presence: "Presence"
        }
    }
}

extension ContentFeedback {
    /// Stand-in content for the loading placeholder and the locked preview. Never shown legibly.
    static let sample = ContentFeedback(
        coachNote: nil,
        ratings: [
            CriterionRating(criterion: .clarity, score: 4, reason: "The bridge analogy made the core idea land for a beginner."),
            CriterionRating(criterion: .structure, score: 3, reason: "Strong opening, but the ending trailed off into a second example."),
            CriterionRating(criterion: .accuracy, score: 5, reason: "Nothing clearly wrong."),
            CriterionRating(criterion: .ownership, score: 3, reason: "Your own example was the best part; the dates sounded recited."),
        ],
        flaggedClaims: [],
        whatYouMissed: ["Why it matters today: the same idea shapes how engineers design for failure."],
        nextTimeTip: "End on one sentence that says why it matters, then stop.",
        comparison: nil
    )
}
