import SwiftUI

/// The Pro pitch. Mocked until RevenueCat is in (build step 8): plans and prices are placeholders,
/// and subscribing just closes the sheet because everything is unlocked during development.
struct PaywallView: View {
    enum Context {
        /// End of onboarding: soft, dismissible.
        case onboarding
        /// A free user's one AI feedback is used up.
        case feedbackUsed
        /// Tapped a locked feature (Progress, practice) or Settings.
        case upgrade
    }

    let context: Context
    var onClose: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var plan: Plan = .yearly
    @State private var appeared = false

    private enum Plan { case yearly, monthly }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06), in: .circle)
                }
                .accessibilityLabel("Close")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Yapso Pro")
                        Text(headline)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        benefit("text.bubble", "A coach on every talk", "Ratings, what you missed, and one thing to try tomorrow.", order: 0)
                        benefit("brain", "It remembers you", "Your coach tracks your habits and pushes on the right ones.", order: 1)
                        benefit("arrow.trianglehead.2.clockwise", "Practice after your daily", "Up to five more topics a day, or redo an old one.", order: 2)
                        benefit("chart.line.uptrend.xyaxis", "See yourself improve", "Trends for every rating, your pace and your fillers.", order: 3)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            // Fades the benefits out above the plans instead of cutting them off.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))

            VStack(spacing: 10) {
                planRow(.yearly, title: "Yearly", price: "$39.99 / year", note: "$3.33 a month")
                planRow(.monthly, title: "Monthly", price: "$5.99 / month", note: nil)

                Button("Start Pro") { close() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                    .sensoryFeedback(.success, trigger: plan)

                Text("Cancel anytime in Settings. Purchases aren't connected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if context == .onboarding {
                    Button("Not now") { close() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(24)
        .background(Color(uiColor: .systemBackground))
        .onAppear { withAnimation(.smooth(duration: 0.6)) { appeared = true } }
    }

    private var headline: String {
        switch context {
        case .onboarding: "Get a coach in your corner."
        case .feedbackUsed: "Keep the coach."
        case .upgrade: "Get a coach in your corner."
        }
    }

    private func close() {
        onClose()
        dismiss()
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String, order: Int) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.smooth(duration: 0.5).delay(0.1 + Double(order) * 0.07), value: appeared)
    }

    private func planRow(_ value: Plan, title: String, price: String, note: String?) -> some View {
        let selected = plan == value
        return Button {
            plan = value
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(price).font(.subheadline.weight(.medium))
            }
            .padding(16)
            .background(Color.primary.opacity(selected ? 0.07 : 0.03), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
