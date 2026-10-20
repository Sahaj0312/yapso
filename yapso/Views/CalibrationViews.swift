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
    /// False while the card is center stage on the dark reveal; true once tapped away to the note.
    @State private var showingNote = false
    @State private var entered = false
    @State private var drag: CGSize = .zero
    private var connectivity = Connectivity.shared

    init(attempt: Attempt, history: [Attempt], onContinue: @escaping () -> Void) {
        self.attempt = attempt
        self.history = history
        self.onContinue = onContinue
    }

    var body: some View {
        Group {
            if let profile = attempt.speakingProfile {
                reveal(profile)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if attempt.feedbackStatus == .skippedEmpty {
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
            }
        }
        .task(id: attempt.id) { await process() }
        .onChange(of: connectivity.isOnline) { _, online in
            if online, error != nil { Task { await process() } }
        }
    }

    /// The card alone on a dark stage, then (on tap) gliding up to the top with the coach's note below it.
    private func reveal(_ profile: SpeakingProfile) -> some View {
        GeometryReader { proxy in
            let bigScale = min(1.15, (proxy.size.width - 72) / ProfileCard.size.width)
            let scale: CGFloat = showingNote ? 0.48 : bigScale
            let cardHeight = ProfileCard.size.height * scale
            ScrollView {
                VStack(spacing: 28) {
                    LiveTilt(drag: drag) { tilt in
                        ProfileCard(type: profile.type, tilt: tilt, scale: scale)
                    }
                    .padding(.top, showingNote ? 8 : max(24, (proxy.size.height - cardHeight) / 2 - 24))
                    .rotation3DEffect(.degrees(entered ? 0 : 80), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .opacity(entered ? 1 : 0)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard !showingNote else { return }
                                drag = CGSize(width: max(-1, min(1, value.translation.width / 140)),
                                              height: max(-1, min(1, -value.translation.height / 180)))
                            }
                            .onEnded { _ in withAnimation(.spring(duration: 0.6, bounce: 0.4)) { drag = .zero } }
                    )

                    if showingNote {
                        ProfileNote(profile: profile)
                            .transition(.opacity.combined(with: .offset(y: 24)))
                        Button("Spin your first topic", action: onContinue)
                            .buttonStyle(PrimaryButtonStyle(fill: .ember))
                            .transition(.opacity)
                    } else {
                        Text("Tap to see what I noticed")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .opacity(entered ? 1 : 0)
                            .animation(.easeIn(duration: 0.6).delay(1.2), value: entered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!showingNote)
            .background((showingNote ? Color.paper : Color(white: 0.05)).ignoresSafeArea())
            .contentShape(.rect)
            .onTapGesture {
                guard !showingNote else { return }
                withAnimation(.spring(duration: 0.8, bounce: 0.18)) { showingNote = true }
            }
        }
        .statusBarHidden(!showingNote)
        .toolbarVisibility(showingNote ? .automatic : .hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: entered) { _, new in new }
        .sensoryFeedback(.impact(weight: .medium), trigger: showingNote) { _, new in new }
        .onAppear {
            if AppConfig.calibrationNote { showingNote = true }
            withAnimation(.spring(duration: 1.2, bounce: 0.3).delay(0.25)) { entered = true }
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

/// What the coach learned from the calibration, in its own words, under the card.
struct ProfileNote: View {
    let profile: SpeakingProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("What I noticed")
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 18))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Starting point: \(Int(profile.baselineWordsPerMinute.rounded())) wpm · "
                 + "\(String(format: "%.1f", profile.baselineFillersPerMinute)) fillers a minute · "
                 + "\(String(format: "%.1f", profile.baselineLongestPause))s longest pause")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paragraphs: [String] {
        (profile.message ?? profile.summary)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private extension View {
    func reveal(_ shown: Bool, order: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .animation(.smooth(duration: 0.6).delay(0.1 + Double(order) * 0.18), value: shown)
    }
}
