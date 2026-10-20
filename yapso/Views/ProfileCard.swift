import SwiftUI

/// The speaker type as a holographic tarot card. Drawn at one design size in greys, then turned into foil by the
/// `holoFoil` shader; scale it with `scale` rather than re-laying it out, so it looks identical at every size.
struct ProfileCard: View {
    let type: SpeakerType
    /// Roughly -1...1 per axis: device tilt plus any drag.
    var tilt: CGSize = .zero
    var scale: CGFloat = 1
    var glow = true

    static let size = CGSize(width: 270, height: 432)

    var body: some View {
        face
            .frame(width: Self.size.width, height: Self.size.height)
            .compositingGroup()
            .visualEffect { [tilt] content, proxy in
                content.colorEffect(ShaderLibrary.holoFoil(.float2(proxy.size), .float2(Float(tilt.width), Float(tilt.height))))
            }
            .clipShape(.rect(cornerRadius: 18))
            .background { if glow { halo } }
            .rotation3DEffect(.degrees(tilt.height * -9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt.width * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(scale)
            .frame(width: Self.size.width * scale, height: Self.size.height * scale)
            .accessibilityElement()
            .accessibilityLabel("Speaking profile card: \(type.name)")
    }

    /// The card in greys. Light greys become pearl and dark greys become foil in the shader.
    private var face: some View {
        let ink = Color(white: 0.22)
        return ZStack {
            Color(white: 0.94)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ink, lineWidth: 1)
                .padding(10)
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(ink.opacity(0.6), lineWidth: 0.5)
                .padding(14)
            VStack(spacing: 0) {
                Text(type.numeral)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .tracking(2)
                    .padding(.top, 26)
                Image(type.artworkName)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .frame(maxHeight: .infinity)
                Text(type.name.uppercased())
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .tracking(2.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)
                Text("YAPSO")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(3)
                    .opacity(0.7)
                    .padding(.top, 6)
                    .padding(.bottom, 26)
            }
            .foregroundStyle(ink)
        }
        .environment(\.colorScheme, .light)
    }

    /// A soft rainbow bloom behind the card that turns with the tilt.
    private var halo: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(AngularGradient(
                colors: [.pink, .purple, .blue, .mint, .yellow, .orange, .pink],
                center: .center,
                angle: .degrees(tilt.width * 60 + tilt.height * 40)
            ))
            .blur(radius: 36)
            .opacity(0.55)
            .scaleEffect(1.04)
    }
}

extension SpeakerType {
    /// The card's line artwork in the asset catalog.
    var artworkName: String { "Tarot" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Device tilt plus a slow idle drift (so the foil is alive even on a still phone or in the Simulator) and any drag.
struct LiveTilt<Content: View>: View {
    var drag: CGSize = .zero
    @ViewBuilder let content: (CGSize) -> Content

    @State private var device = DeviceTilt()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idle = CGSize(width: sin(t * 0.55) * 0.22, height: cos(t * 0.4) * 0.16)
            content(CGSize(
                width: max(-1, min(1, device.x + idle.width + drag.width)),
                height: max(-1, min(1, device.y + idle.height + drag.height))
            ))
        }
        .onAppear { device.start() }
        .onDisappear { device.stop() }
    }
}
