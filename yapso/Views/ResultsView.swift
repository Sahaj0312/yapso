import SwiftUI

/// A finished attempt: delivery metrics first, then the transcript, then the coach's feedback.
/// Shown on Today (with the streak) and from History (without).
struct ResultsView<Footer: View>: View {
    let attempt: Attempt
    /// All attempts, for 7-day baselines.
    let history: [Attempt]
    /// Today's streak; nil when opened from History.
    let streak: Int?
    /// What comes after the feedback: practice on Today, a redo in History.
    let footer: Footer

    init(attempt: Attempt, history: [Attempt], streak: Int?, @ViewBuilder footer: () -> Footer) {
        self.attempt = attempt
        self.history = history
        self.streak = streak
        self.footer = footer()
    }

    @State private var error: Error?
    @State private var feedbackError: Error?
    private var connectivity = Connectivity.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    if let streak {
                        TodayHeader(streak: streak)
                            .padding(.bottom, 24)
                    }
                    Eyebrow(attempt.kind == .practice && streak != nil ? "Practice · \(attempt.topicDomain)" : attempt.topicDomain)
                    Text(attempt.topicTitle)
                        .font(.display)
                        .fixedSize(horizontal: false, vertical: true)
                    if streak == nil {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                content

                footer
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(Color.paper.ignoresSafeArea())
        .task(id: attempt.id) { await process() }
        // An offline talk is saved on the phone; analyze it the moment the connection comes back.
        .onChange(of: connectivity.isOnline) { _, online in
            if online, error != nil || feedbackError != nil { Task { await process() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if attempt.isTranscribed {
            if let timeline = attempt.transcriptTimeline, !timeline.words.isEmpty {
                if attempt.transcriptionSource == .onDevice {
                    OfflineModelNotice(canRetry: connectivity.isOnline) { Task { await retranscribeOnline() } }
                }
                MetricGrid(attempt: attempt, history: history)
                TranscriptSection(timeline: timeline, audioURL: localAudioURL)
                if attempt.kind == .calibration {
                    if let profile = attempt.speakingProfile {
                        LiveTilt { tilt in ProfileCard(type: profile.type, tilt: tilt, scale: 0.5) }
                            .frame(maxWidth: .infinity)
                        ProfileNote(profile: profile)
                    }
                } else {
                    FeedbackSection(attempt: attempt, error: feedbackError) { Task { await process() } }
                }
            } else {
                EmptyTalkCard()
            }
        } else if let error, APIError.isOffline(error) {
            OfflineCard()
        } else if let error {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't transcribe this talk. \(error.localizedDescription)").foregroundStyle(.secondary)
                Button("Try again") { Task { await process() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if !hasLocalAudio {
            Text("This talk was recorded on another device.")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Transcribing…").foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private var subtitle: String {
        let date = attempt.revealedAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
        switch attempt.kind {
        case .practice: return "\(date) · Practice"
        case .calibration: return "\(date) · Your first talk"
        case .daily: return date
        }
    }

    private var hasLocalAudio: Bool { localAudioURL != nil }

    /// The recording, if it's on this device (it isn't synced, and it's deleted after 30 days).
    private var localAudioURL: URL? {
        guard let name = attempt.audioFileName else { return nil }
        let url = Recordings.url(for: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func process() async {
        withAnimation { error = nil; feedbackError = nil }
        do {
            try await AttemptProcessor.transcribeIfNeeded(attempt)
        } catch {
            withAnimation { self.error = error }
            return
        }
        do {
            try await AttemptProcessor.requestFeedbackIfNeeded(attempt, history: history)
        } catch {
            withAnimation { feedbackError = error }
        }
    }

    /// Replaces an offline-model transcript with a cloud one now that there's a connection.
    private func retranscribeOnline() async {
        attempt.isTranscribed = false
        // The feedback was on the offline transcript, so it's redone too.
        attempt.feedbackStatus = .notRequested
        await process()
    }
}

// MARK: - Metrics

private struct MetricGrid: View {
    let attempt: Attempt
    let history: [Attempt]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricCard(label: "Pace", value: attempt.wordsPerMinute, unit: "wpm", order: 0,
                           baseline: baseline(\.wordsPerMinute)) { "\(Int($0.rounded()))" }
                MetricCard(label: "Fillers", value: Double(attempt.fillerCount), unit: nil, order: 1,
                           baseline: baseline { Double($0.fillerCount) }) { "\(Int($0.rounded()))" }
            }
            GridRow {
                MetricCard(label: "Longest pause", value: attempt.longestPauseSeconds, unit: "s", order: 2,
                           baseline: baseline(\.longestPauseSeconds)) { String(format: "%.1f", $0) }
                MetricCard(label: "Time used", value: attempt.secondsUsed, unit: "/ \(attempt.timeline.speakingCap.clockString)", order: 3,
                           baseline: baseline(\.secondsUsed)) { $0.clockString }
            }
        }
    }

    private func baseline(_ value: (Attempt) -> Double) -> Double? {
        attempt.baseline(in: history, value)
    }

    private func baseline(_ keyPath: KeyPath<Attempt, Double>) -> Double? {
        baseline { $0[keyPath: keyPath] }
    }
}

private struct MetricCard: View {
    let label: String
    let value: Double
    let unit: String?
    let order: Int
    let baseline: Double?
    let format: (Double) -> String

    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                CountingText(value: shown, format: format)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                if let unit {
                    Text(unit).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(baseline.map { "7-day avg \(format($0))" } ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground(cornerRadius: 16)
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(Double(order) * 0.08)) { shown = value }
        }
        .onChange(of: value) { _, new in withAnimation(.smooth) { shown = new } }
    }
}

/// Text whose number interpolates frame by frame when animated, so metrics count up.
private struct CountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

// MARK: - Transcript

private struct TranscriptSection: View {
    let timeline: TranscriptTimeline
    let audioURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Transcript")
            if let audioURL {
                AudioPlayerBar(url: audioURL)
                    .padding(.bottom, 4)
            }
            Text(attributed)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
            HStack(spacing: 14) {
                Text("filler")
                    .padding(.horizontal, 3)
                    .background(Color.ember.opacity(0.22), in: .rect(cornerRadius: 3))
                Text("— 2.0s —  pause")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var attributed: AttributedString {
        let spans = DeliveryAnalyzer.fillerSpans(in: timeline.words)
        let fillerIndices = Set(spans.flatMap { Array($0) })
        // The transcriber folds silence into the following word, so a pause belongs before the first word that ends after it.
        var pauses = timeline.pauses.filter { $0.duration >= DeliveryAnalyzer.notablePause }.makeIterator()
        var nextPause = pauses.next()

        var result = AttributedString()
        for (index, word) in timeline.words.enumerated() {
            while let pause = nextPause, word.end >= pause.end {
                var marker = AttributedString(" — \(String(format: "%.1f", pause.duration))s — ")
                marker.foregroundColor = .secondary
                marker.font = .callout
                result += marker
                nextPause = pauses.next()
            }
            // Leading spaces sit outside the highlight so it hugs the word, except inside a multi-word filler ("you know").
            let token = word.text.trimmingCharacters(in: .whitespaces)
            if index > 0 && word.text.first?.isWhitespace == true {
                var space = AttributedString(" ")
                if spans.contains(where: { $0.contains(index) && $0.contains(index - 1) }) {
                    space.backgroundColor = Color.ember.opacity(0.22)
                }
                result += space
            }
            var piece = AttributedString(token)
            if fillerIndices.contains(index) {
                piece.backgroundColor = Color.ember.opacity(0.22)
            }
            result += piece
        }
        return result
    }
}

/// A daily talk recorded without a connection: it's saved, and analysis needs the internet.
private struct OfflineCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You're offline", systemImage: "wifi.slash")
                .font(.title3.weight(.semibold))
            Text("Your talk is saved on your phone. Connect to Wi-Fi or cellular and it'll be analyzed right away.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground(cornerRadius: 16)
    }
}

/// A practice talk transcribed by the less accurate on-device model because there was no connection.
private struct OfflineModelNotice: View {
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcribed with the offline model. For more accurate results, connect to the internet.")
                if canRetry {
                    Button("Transcribe again online", action: onRetry)
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground(cornerRadius: 12)
    }
}

/// Play/pause plus a draggable progress bar for listening back.
private struct AudioPlayerBar: View {
    let url: URL
    @State private var playback = AudioPlayback()

    var body: some View {
        HStack(spacing: 14) {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(Color.primary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play recording")
            .sensoryFeedback(.selection, trigger: playback.isPlaying)

            GeometryReader { proxy in
                let fraction = playback.duration > 0 ? playback.currentTime / playback.duration : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.primary).frame(width: proxy.size.width * fraction)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    playback.seek(to: value.location.x / proxy.size.width)
                })
            }
            .frame(height: 40)

            Text((playback.isPlaying || playback.currentTime > 0 ? playback.currentTime : playback.duration).clockString)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .onAppear { playback.load(url) }
        .onDisappear { playback.stop() }
    }
}

private struct EmptyTalkCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing came out this time.")
                .font(.title3.weight(.semibold))
            Text("Blanking happens to everyone. That's exactly what this trains. Your streak still counts.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground(cornerRadius: 16)
    }
}
