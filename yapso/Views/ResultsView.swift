import SwiftUI

/// A finished attempt: delivery metrics first (instant, on-device), then the transcript.
struct ResultsView: View {
    let attempt: Attempt
    /// All attempts, for 7-day baselines.
    let history: [Attempt]
    let streak: Int

    init(attempt: Attempt, history: [Attempt], streak: Int) {
        self.attempt = attempt
        self.history = history
        self.streak = streak
    }

    @State private var error: Error?
    private var connectivity = Connectivity.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    StreakLabel(streak: streak)
                        .padding(.bottom, 24)
                    Eyebrow(attempt.topicDomain)
                    Text(attempt.topicTitle)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                content

                Text("New topic tomorrow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .task(id: attempt.id) { await transcribe() }
        // An offline talk is saved on the phone; analyze it the moment the connection comes back.
        .onChange(of: connectivity.isOnline) { _, online in
            if online, error != nil { Task { await transcribe() } }
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
                TranscriptSection(timeline: timeline)
            } else {
                EmptyTalkCard()
            }
        } else if let error, TranscriptionError.isOffline(error) {
            OfflineCard()
        } else if let error {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't transcribe this talk. \(error.localizedDescription)").foregroundStyle(.secondary)
                Button("Try again") { Task { await transcribe() } }
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

    private var hasLocalAudio: Bool {
        guard let name = attempt.audioFileName else { return false }
        return FileManager.default.fileExists(atPath: Recordings.url(for: name).path)
    }

    private func transcribe() async {
        withAnimation { error = nil }
        do {
            try await AttemptProcessor.transcribeIfNeeded(attempt)
        } catch {
            withAnimation { self.error = error }
        }
    }

    /// Replaces an offline-model transcript with a cloud one now that there's a connection.
    private func retranscribeOnline() async {
        attempt.isTranscribed = false
        await transcribe()
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
                MetricCard(label: "Time used", value: attempt.secondsUsed, unit: "/ 1:30", order: 3,
                           baseline: baseline(\.secondsUsed)) { $0.clockString }
            }
        }
    }

    private func baseline(_ value: (Attempt) -> Double) -> Double? {
        guard let day = attempt.day else { return nil }
        let samples = history
            .filter { $0.kind == .daily && $0.isTranscribed && $0.wordCount > 0 && $0.id != attempt.id }
            .compactMap { a in a.day.map { (day: $0, value: value(a)) } }
        return DeliveryAnalyzer.baseline(samples, before: day)
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
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Transcript")
            Text(attributed)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
            HStack(spacing: 14) {
                Text("filler")
                    .padding(.horizontal, 3)
                    .background(Color.yellow.opacity(0.35), in: .rect(cornerRadius: 3))
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
                    space.backgroundColor = Color.yellow.opacity(0.35)
                }
                result += space
            }
            var piece = AttributedString(token)
            if fillerIndices.contains(index) {
                piece.backgroundColor = Color.yellow.opacity(0.35)
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
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
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
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
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
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
    }
}
