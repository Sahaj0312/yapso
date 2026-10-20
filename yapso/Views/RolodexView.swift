import AudioToolbox
import SwiftUI

/// The daily reveal: a typographic reel of real topic names that decelerates and settles on today's topic.
/// Purely theatre — the result is decided before it starts.
struct RolodexView: View {
    let landsAt: Date
    let domain: String
    @State private var titles: [String]
    @AppStorage(Preferences.spinSound) private var spinSound = false

    private let rowHeight: CGFloat = 52
    private let visibleRows = 5
    /// The reel stops this long before `landsAt`, leaving a beat on the result.
    private static let holdOnResult: TimeInterval = 0.7

    init(target: String, domain: String, landsAt: Date, pool: [Topic]) {
        self.landsAt = landsAt
        self.domain = domain
        let filler = pool.map(\.title).filter { $0 != target }.shuffled().prefix(26)
        _titles = State(initialValue: Array(filler) + [target])
    }

    var body: some View {
        TimelineView(.animation) { context in
            let progress = spinProgress(at: context.date)
            let position = progress * Double(titles.count - 1)
            let landed = progress >= 1

            VStack(spacing: 28) {
                Eyebrow(landed ? domain : "Today's topic")
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: landed)

                ZStack {
                    ForEach(titles.indices, id: \.self) { index in
                        let distance = Double(index) - position
                        if abs(distance) < Double(visibleRows) / 2 + 1 {
                            row(titles[index], distance: distance, isResult: landed && index == titles.count - 1)
                        }
                    }
                }
                .frame(height: rowHeight * CGFloat(visibleRows))
                .frame(maxWidth: .infinity)
                .clipped()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.3),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
            }
            .sensoryFeedback(.selection, trigger: Int(position.rounded()))
            .onChange(of: Int(position.rounded())) {
                // The keyboard click: quiet, and silenced by the ringer switch.
                if spinSound { AudioServicesPlaySystemSound(1104) }
            }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: landed) { _, new in new }
        }
        .padding(.horizontal, 24)
    }

    private func row(_ title: String, distance: Double, isResult: Bool) -> some View {
        let falloff = min(abs(distance) / 2.5, 1)
        return Text(title)
            .font(.system(.title2, design: .serif).weight(isResult ? .bold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(abs(distance) < 0.5 ? .primary : .secondary)
            .opacity(1 - falloff * 0.85)
            .scaleEffect(1 - min(abs(distance), 3) * 0.06)
            .rotation3DEffect(.degrees(-distance * 14), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .offset(y: distance * rowHeight)
    }

    /// 0…1 along the reel, with a quintic ease-out so it starts fast and settles gently.
    private func spinProgress(at date: Date) -> Double {
        let spinLength = AppConfig.spinDuration - Self.holdOnResult
        let start = landsAt.addingTimeInterval(-AppConfig.spinDuration)
        let t = min(max(date.timeIntervalSince(start) / spinLength, 0), 1)
        return 1 - pow(1 - t, 5)
    }
}
