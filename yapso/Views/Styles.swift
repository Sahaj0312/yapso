import SwiftUI

/// Solid, full-width, ink-on-paper button. Inverts in dark mode.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color.paper)
            .background(Color.primary, in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.primary)
            .cardBackground(cornerRadius: 14)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small uppercase label used for section captions ("TODAY'S TOPIC", domain names).
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

extension TimeInterval {
    /// "9:41"-style minutes and seconds, rounding up so the clock never shows 0:00 early.
    var clockString: String {
        let total = Int(max(0, self).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
