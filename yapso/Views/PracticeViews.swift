import SwiftData
import SwiftUI

/// The selected tab, shared so other screens can send the user to Today (e.g. after starting a redo from History).
@Observable
final class AppRouter {
    var tab: AppTab
    init(tab: AppTab) { self.tab = tab }
}

/// "Want another?" under today's result: starts a fresh practice topic, or pitches Pro.
struct PracticeCard: View {
    let availability: Practice.Availability
    let onStart: () -> Void

    @State private var showPaywall = false

    var body: some View {
        if availability != .afterDaily {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Practice")
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch availability {
                case .available:
                    Button("Practice a new topic", action: onStart)
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                case .needsPro:
                    Button("Unlock practice") { showPaywall = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                case .afterDaily, .limitReached:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
            .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
        }
    }

    private var title: String {
        availability == .limitReached ? "That's five for today." : "Want another?"
    }

    private var detail: String {
        switch availability {
        case .available(let remaining):
            "A new topic, same rules. It won't touch your streak. \(remaining) left today."
        case .needsPro:
            "Practice up to five more topics a day with Pro."
        case .limitReached:
            "Rest the voice. New topic tomorrow."
        case .afterDaily:
            ""
        }
    }
}

/// On a past talk in History: practice the same topic again, compared against this attempt.
struct RedoButton: View {
    let attempt: Attempt
    let attempts: [Attempt]

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var showPaywall = false

    var body: some View {
        let availability = Practice.availability(attempts: attempts)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                switch availability {
                case .available:
                    Task {
                        if await Practice.start(redoing: attempt, attempts: attempts, in: context) != nil {
                            router.tab = .today
                        }
                    }
                case .needsPro:
                    showPaywall = true
                case .afterDaily, .limitReached:
                    break
                }
            } label: {
                Label("Redo this topic", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(availability == .afterDaily || availability == .limitReached || hasActiveSession)

            if let note = note(for: availability) {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
    }

    private var hasActiveSession: Bool {
        let now = Date.now
        return attempts.contains { attempt in
            switch attempt.timeline.phase(now: now) {
            case .finished, .forfeited: false
            default: true
            }
        }
    }

    private func note(for availability: Practice.Availability) -> String? {
        if hasActiveSession { return "Finish the talk in progress first." }
        switch availability {
        case .available: return "Practice: your coach compares it with this attempt."
        case .needsPro: return "Redos are part of Pro."
        case .afterDaily: return "Practice opens after today's talk."
        case .limitReached: return "That's five practice talks today."
        }
    }
}
