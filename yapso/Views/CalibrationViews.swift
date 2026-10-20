import SwiftUI

/// Today, before the first spin: one easy question to talk about for 60 seconds.
struct CalibrationIntroView: View {
    let onStart: (String) -> Void

    @State private var promptIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayHeader(streak: 0)
            Spacer()

            Text("Calibration · 60 seconds")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.ember)
                .padding(.bottom, 10)
            Text("First, let's hear how you talk.")
                .font(.display)
                .fixedSize(horizontal: false, vertical: true)
            Text("One easy question, no research. Your coach turns it into your speaking profile.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Your question")
                Text(Calibration.prompts[promptIndex])
                    .font(.system(.title2, design: .serif).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(promptIndex)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                Button {
                    withAnimation(.smooth(duration: 0.3)) { promptIndex = (promptIndex + 1) % Calibration.prompts.count }
                } label: {
                    Label("Different question", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: promptIndex)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .cardBackground()
            .padding(.top, 28)

            Spacer()

            Button("I'm ready") { onStart(Calibration.prompts[promptIndex]) }
                .buttonStyle(PrimaryButtonStyle(fill: .ember))
            Text("Starts after a 3-second countdown. You can stop early.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .padding(24)
    }
}

/// The finished calibration on Today: builds the profile (transcription, then the coach), then reveals it.
struct CalibrationResultView: View {
    let attempt: Attempt
    let history: [Attempt]
    /// "Spin your first topic", or "Try again" after an empty talk.
    let onContinue: () -> Void

    @State private var error: Error?
    private var connectivity = Connectivity.shared

    init(attempt: Attempt, history: [Attempt], onContinue: @escaping () -> Void) {
        self.attempt = attempt
        self.history = history
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let profile = attempt.speakingProfile {
                    SpeakingProfileView(profile: profile, animated: true)
                    Button("Spin your first topic", action: onContinue)
                        .buttonStyle(PrimaryButtonStyle(fill: .ember))
                } else if attempt.feedbackStatus == .skippedEmpty {
                    emptyTalk
                } else if let error {
                    failure(error)
                } else {
                    building
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(Color.paper.ignoresSafeArea())
        .task(id: attempt.id) { await process() }
        .onChange(of: connectivity.isOnline) { _, online in
            if online, error != nil { Task { await process() } }
        }
    }

    private var building: some View {
        VStack(spacing: 20) {
            Illustration(name: "IllustrationMicrophone", height: 150)
                .padding(.top, 80)
            Text("Building your speaking profile…")
                .font(.displaySmall)
                .multilineTextAlignment(.center)
            ProgressView()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTalk: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We didn't catch that.")
                .font(.display)
            Text("Nothing came through on the recording. Check you're not muted, and give it another go.")
                .foregroundStyle(.secondary)
            Button("Try again", action: onContinue)
                .buttonStyle(PrimaryButtonStyle(fill: .ember))
                .padding(.top, 12)
        }
        .padding(.top, 80)
    }

    private func failure(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if APIError.isOffline(error) {
                Label("You're offline", systemImage: "wifi.slash")
                    .font(.title3.weight(.semibold))
                Text("Your talk is saved. Connect to Wi-Fi or cellular and your profile will be built right away.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Couldn't build your profile. \(error.localizedDescription)")
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await process() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, 80)
    }

    private func process() async {
        withAnimation { error = nil }
        do {
            try await AttemptProcessor.transcribeIfNeeded(attempt)
            try await AttemptProcessor.requestFeedbackIfNeeded(attempt, history: history)
        } catch {
            withAnimation { self.error = error }
        }
    }
}

/// The speaking profile: the type, a personal summary, starting numbers, and what the coach will work on.
/// Shown after calibration and from History.
struct SpeakingProfileView: View {
    let profile: SpeakingProfile
    var animated = false

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Your speaking profile")
                Text("You're")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.secondary)
                Text(profile.type.name)
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ember)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.type.tagline)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .reveal(shown, order: 0)

            Text(profile.summary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Capsule().fill(Color.ember).frame(width: 3) }
                .reveal(shown, order: 1)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Your starting point")
                HStack(spacing: 10) {
                    stat("Pace", "\(Int(profile.baselineWordsPerMinute.rounded()))", "wpm")
                    stat("Fillers", String(format: "%.1f", profile.baselineFillersPerMinute), "/ min")
                    stat("Longest pause", String(format: "%.1f", profile.baselineLongestPause), "s")
                }
            }
            .reveal(shown, order: 2)

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("What you do well")
                ForEach(profile.strengths, id: \.self) { strength in
                    Label {
                        Text(strength).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Color.ember)
                    }
                }
            }
            .reveal(shown, order: 3)

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("What we'll work on")
                ForEach(profile.workOn, id: \.self) { area in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "scope").foregroundStyle(Color.ember)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(area.label).font(.headline)
                            Text(area.evidence)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Watch out: \(profile.type.watchOut.prefix(1).lowercased() + profile.type.watchOut.dropFirst())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .cardBackground()
            .reveal(shown, order: 4)

            VStack(alignment: .leading, spacing: 8) {
                Label("For your first topic", systemImage: "arrow.forward.circle.fill")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ember)
                Text(profile.firstTip)
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.ember.opacity(0.08), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ember.opacity(0.25)))
            .reveal(shown, order: 5)
        }
        .sensoryFeedback(.success, trigger: shown) { _, new in new && animated }
        .onAppear {
            if animated {
                shown = true
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { shown = true }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground(cornerRadius: 14)
    }
}

private extension View {
    func reveal(_ shown: Bool, order: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .animation(.smooth(duration: 0.6).delay(0.1 + Double(order) * 0.18), value: shown)
    }
}
