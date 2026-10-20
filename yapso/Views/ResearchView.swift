import SwiftUI

struct ResearchView: View {
    let attempt: Attempt
    let remaining: TimeInterval
    let total: TimeInterval
    let onReady: () -> Void
    /// Practice only: give up on this topic.
    var onStop: (() -> Void)?

    @State private var confirmingStart = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(attempt.kind == .practice ? "Practice · \(attempt.topicDomain)" : attempt.topicDomain)
                Spacer()
                if let onStop {
                    Button("Stop", action: onStop)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)
            Text(attempt.topicTitle)
                .font(.display)
                .fixedSize(horizontal: false, vertical: true)
                .onLongPressGesture {
                    UIPasteboard.general.string = attempt.topicTitle
                    copied.toggle()
                }
                .sensoryFeedback(.success, trigger: copied)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text(remaining.clockString)
                    .font(.system(size: 72, weight: .light).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(remaining.rounded(.up)))
                Text("to research. Speaking starts automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: 1 - remaining / total)
                    .tint(.ember)
                    .padding(.top, 12)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    if let url = searchURL { UIApplication.shared.open(url) }
                } label: {
                    Label("Search this", systemImage: "magnifyingglass")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("I'm ready — start speaking") { confirmingStart = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .overlay(alignment: .top) {
            if copied {
                Text("Copied").font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation { copied = false }
                    }
            }
        }
        .animation(.snappy, value: copied)
        .confirmationDialog("Start speaking now?", isPresented: $confirmingStart, titleVisibility: .visible) {
            Button("Start — 3, 2, 1") { onReady() }
        } message: {
            Text("You get one go. 90 seconds, no restarts.")
        }
    }

    private var searchURL: URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: attempt.topicTitle)]
        return components?.url
    }
}
