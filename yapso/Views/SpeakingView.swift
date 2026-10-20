import SwiftUI

struct CountdownView: View {
    let value: Int

    var body: some View {
        VStack(spacing: 12) {
            Eyebrow("Speak in")
            Text("\(value)")
                .font(.system(size: 120, weight: .light).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: value)
    }
}

struct SpeakingView: View {
    let topicTitle: String
    let remaining: TimeInterval
    let levels: [Float]
    let onDone: () -> Void

    @State private var confirmingDone = false

    private var secondsLeft: Int { Int(max(0, remaining).rounded(.up)) }

    var body: some View {
        VStack(spacing: 0) {
            Text(topicTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: remaining / SessionTimeline.speakingCap)
                    .stroke(Color.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: remaining)
                Text("\(secondsLeft)")
                    .font(.system(size: 72, weight: .light).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: secondsLeft)
            }
            .frame(width: 240, height: 240)

            WaveformView(levels: levels)
                .frame(height: 44)
                .padding(.horizontal, 48)
                .padding(.top, 40)

            Spacer()

            Button("Done") { confirmingDone = true }
                .buttonStyle(SecondaryButtonStyle())
                .padding(24)
        }
        .padding(.top, 24)
        // A soft tick each second through the final five.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: secondsLeft) { _, new in new <= 5 && new > 0 }
        .confirmationDialog("End your talk now?", isPresented: $confirmingDone, titleVisibility: .visible) {
            Button("End talk", role: .destructive) { onDone() }
        } message: {
            Text("This is your one go for today.")
        }
    }
}

struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(0.25 + Double(index) / Double(levels.count) * 0.6))
                    .frame(height: max(3, CGFloat(levels[index]) * 44))
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}
