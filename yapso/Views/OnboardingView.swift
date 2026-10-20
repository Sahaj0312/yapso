import SwiftData
import SwiftUI

/// First launch: a welcome, how it works, three quick questions that seed the coach, the plan they produce,
/// the mic, then the soft paywall. No speaking happens here.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var situation: Situation?
    @State private var struggles: [Struggle] = []
    @State private var goal: Goal?
    @State private var showPaywall = false

    enum Step: Int, CaseIterable {
        case welcome, howItWorks, situation, struggles, goal, plan, microphone
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header.transition(.opacity)
            }
            ZStack {
                page(step)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 40 : -40)),
                        removal: .opacity.combined(with: .offset(x: forward ? -40 : 40))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(24)
        .background(Color.paper)
        .tint(.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .onAppear(perform: jumpForDebugging)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(context: .onboarding) { onFinish() }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.ember)
                        .frame(width: proxy.size.width * Double(step.rawValue) / Double(Step.allCases.count - 1))
                }
            }
            .frame(height: 4)
            .animation(.smooth, value: step)

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var footer: some View {
        // Single-choice questions move on as soon as an answer is tapped.
        if step != .situation && step != .goal {
            Button(primaryLabel) { advance() }
                .buttonStyle(PrimaryButtonStyle(fill: step == .welcome ? .ember : .primary))
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.35)
                .animation(.smooth(duration: 0.2), value: canContinue)
                .transition(.opacity)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: "Get started"
        case .plan: "Sounds right"
        case .microphone: Permissions.microphoneGranted ? "Continue" : "Allow microphone"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        step == .struggles ? !struggles.isEmpty : true
    }

    private func advance() {
        if step == .microphone {
            Task {
                if !Permissions.microphoneGranted { _ = await Permissions.requestMicrophone() }
                saveAnswers()
                showPaywall = true
            }
            return
        }
        go(to: Step(rawValue: step.rawValue + 1))
    }

    private func go(to next: Step?) {
        guard let next else { return }
        forward = next.rawValue > step.rawValue
        withAnimation(.smooth(duration: 0.4)) { step = next }
    }

    /// Lets the tap register visibly before a single-choice question moves on.
    private func answerThenAdvance(_ apply: () -> Void) {
        apply()
        let current = step
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if step == current { go(to: Step(rawValue: current.rawValue + 1)) }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome:
            WelcomePage()
        case .howItWorks:
            HowItWorksPage()
        case .situation:
            QuestionPage(number: 1, title: "When does speaking trip you up?", subtitle: nil) {
                ForEach(Situation.allCases) { option in
                    OptionRow(title: option.rawValue, symbol: option.symbol, selected: situation == option, multiple: false) {
                        answerThenAdvance { situation = option }
                    }
                }
            }
        case .struggles:
            QuestionPage(number: 2, title: "What happens?", subtitle: "Pick all that apply.") {
                ForEach(Struggle.allCases) { option in
                    OptionRow(title: option.rawValue, symbol: option.symbol, selected: struggles.contains(option), multiple: true) {
                        if let index = struggles.firstIndex(of: option) {
                            struggles.remove(at: index)
                        } else {
                            struggles.append(option)
                        }
                    }
                }
            }
        case .goal:
            QuestionPage(number: 3, title: "What's it for?", subtitle: nil) {
                ForEach(Goal.allCases) { option in
                    OptionRow(title: option.rawValue, symbol: option.symbol, selected: goal == option, multiple: false) {
                        answerThenAdvance { goal = option }
                    }
                }
            }
        case .plan:
            PlanPage(headline: headline, watchFor: struggles.map(\.watchFor), closer: goal?.closer)
        case .microphone:
            VStack(alignment: .leading, spacing: 0) {
                Illustration(name: "IllustrationMicrophone", height: 220)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Eyebrow("One last thing").padding(.bottom, 10)
                Text("Yapso needs to hear you.")
                    .font(.display)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your talk is transcribed so your coach can give feedback. The recording stays on your phone for 30 days, then it's deleted.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
        }
    }

    /// `-yapsoOnboardingStep <0-6|paywall>` (Debug only) opens on that page with sample answers, for screenshots.
    private func jumpForDebugging() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "yapsoOnboardingStep") else { return }
        situation = .meetings
        struggles = [.blank, .ramble]
        goal = .career
        if raw == "paywall" {
            step = .microphone
            showPaywall = true
        } else if let index = Int(raw), let target = Step(rawValue: index) {
            step = target
        }
        #endif
    }

    // MARK: - Answers

    /// "In meetings, you blank under pressure and ramble."
    private var headline: String {
        let habits = struggles.map(\.habit)
        let list: String = switch habits.count {
        case 0: "lose the thread"
        case 1: habits[0]
        default: habits.dropLast().joined(separator: ", ") + " and " + habits.last!
        }
        let sentence = situation?.phrase.map { "\($0), you \(list)." } ?? "You \(list)."
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private func saveAnswers() {
        let answers = OnboardingAnswers(situation: situation?.rawValue, struggles: struggles.map(\.rawValue), goal: goal?.rawValue)
        if let profile = CoachProfile.latest(in: context) {
            var memory = profile.memory
            memory.onboarding = answers
            profile.memory = memory
            profile.updatedAt = .now
        } else {
            context.insert(CoachProfile(memory: CoachMemory(onboarding: answers)))
        }
        try? context.save()
    }
}

// MARK: - Options

private enum Situation: String, CaseIterable, Identifiable {
    case meetings = "Meetings"
    case interviews = "Interviews"
    case presentations = "Presentations"
    case friends = "Explaining things to friends"
    case general = "I ramble in general"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .meetings: "person.3"
        case .interviews: "briefcase"
        case .presentations: "rectangle.on.rectangle"
        case .friends: "bubble.left.and.bubble.right"
        case .general: "scribble"
        }
    }

    var phrase: String? {
        switch self {
        case .meetings: "in meetings"
        case .interviews: "in interviews"
        case .presentations: "when you present"
        case .friends: "when you explain things to friends"
        case .general: nil
        }
    }
}

private enum Struggle: String, CaseIterable, Identifiable {
    case blank = "I blank out"
    case um = "I say \"um\" a lot"
    case ramble = "I ramble without a point"
    case fast = "I speak too fast"
    case confidence = "I lose confidence"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .blank: "cloud.fog"
        case .um: "ellipsis.bubble"
        case .ramble: "arrow.triangle.swap"
        case .fast: "hare"
        case .confidence: "arrow.down.right"
        }
    }

    var habit: String {
        switch self {
        case .blank: "blank under pressure"
        case .um: "fill the silences with \"um\""
        case .ramble: "ramble"
        case .fast: "rush"
        case .confidence: "lose confidence halfway through"
        }
    }

    var watchFor: String {
        switch self {
        case .blank: "The moments you freeze"
        case .um: "Your fillers"
        case .ramble: "Whether you land your point"
        case .fast: "Your pace"
        case .confidence: "Where you start to hedge"
        }
    }
}

private enum Goal: String, CaseIterable, Identifiable {
    case career = "My career"
    case school = "School"
    case confidence = "Confidence"
    case sharper = "Just getting sharper"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .career: "chart.line.uptrend.xyaxis"
        case .school: "graduationcap"
        case .confidence: "figure.stand"
        case .sharper: "sparkles"
        }
    }

    var closer: String {
        switch self {
        case .career: "Ninety seconds a day adds up to the person who explains things well at work."
        case .school: "Ninety seconds a day adds up to answers that land in class and in exams."
        case .confidence: "Ninety seconds a day adds up to trusting yourself when it's your turn to talk."
        case .sharper: "Ninety seconds a day, and a lot of niche things learned along the way."
        }
    }
}

// MARK: - Pages

/// The brand moment: the real reel spinning sample topics above the wordmark.
private struct WelcomePage: View {
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RolodexDemo()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            (Text("yapso").foregroundStyle(.primary) + Text(".").foregroundStyle(Color.ember))
                .font(.system(size: 64, weight: .semibold, design: .serif))
                .padding(.bottom, 12)
            Text("One topic a day. Ten minutes to learn it. Ninety seconds to explain it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 36)
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.smooth(duration: 0.8)) { shown = true } }
    }
}

/// The rules on one page: three numbered steps instead of three screens.
private struct HowItWorksPage: View {
    @State private var shown = false

    private let steps: [(title: String, detail: String)] = [
        ("Spin for today's topic", "Something niche, like how submarines dive. Once it lands, it's yours."),
        ("Ten minutes to learn it", "Research anywhere you like. The clock keeps running while you're away."),
        ("Ninety seconds to explain it", "Speaking starts on its own. One take, then honest feedback from your coach."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("How it works").padding(.bottom, 10)
            Text("A small daily rep.")
                .font(.display)
                .padding(.bottom, 32)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text("\(index + 1)")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ember)
                        .frame(width: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(.headline)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 18)
                .overlay(alignment: .bottom) {
                    if index < steps.count - 1 { Rectangle().fill(Color.hairline).frame(height: 1) }
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 10)
                .animation(.smooth(duration: 0.6).delay(0.15 + Double(index) * 0.15), value: shown)
            }

            Spacer()

            Label("One spin a day. No do-overs.", systemImage: "flame.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ember)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.ember.opacity(0.1), in: .capsule)
                .padding(.bottom, 24)
                .opacity(shown ? 1 : 0)
                .animation(.smooth(duration: 0.6).delay(0.7), value: shown)
        }
        .onAppear { shown = true }
    }
}

private struct QuestionPage<Options: View>: View {
    let number: Int
    let title: String
    let subtitle: String?
    @ViewBuilder let options: Options

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Question \(number) of 3")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ember)
                Text(title)
                    .font(.display)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
                VStack(spacing: 10) { options }
                    .padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OptionRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(selected ? Color.ember : .secondary)
                    .frame(width: 24)
                Text(title).font(.body.weight(.medium))
                Spacer()
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .font(.title3)
                    .foregroundStyle(selected ? Color.ember : Color.primary.opacity(0.2))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .background(selected ? Color.ember.opacity(0.08) : Color.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.ember : Color.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

/// The answers turned into what the coach will do, so the questions visibly mattered.
private struct PlanPage: View {
    let headline: String
    let watchFor: [String]
    let closer: String?

    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Your plan")
                    Text(headline)
                        .font(.display)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .reveal(shown, order: 0)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Your coach will watch for")
                        .font(.subheadline.weight(.semibold))
                    ForEach(watchFor.isEmpty ? ["Whether you land your point"] : watchFor, id: \.self) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "scope")
                                .foregroundStyle(Color.ember)
                            Text(item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .cardBackground()
                .reveal(shown, order: 1)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Every day")
                        .font(.subheadline.weight(.semibold))
                    planRow("dice", "A topic you didn't pick")
                    planRow("timer", "Ten minutes to get it")
                    planRow("waveform", "Ninety seconds to say it clearly")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .cardBackground()
                .reveal(shown, order: 2)

                if let closer {
                    Text(closer)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .reveal(shown, order: 3)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear { shown = true }
    }

    private func planRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(text)
        }
    }
}

private extension View {
    func reveal(_ shown: Bool, order: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .animation(.smooth(duration: 0.6).delay(0.1 + Double(order) * 0.2), value: shown)
    }
}

/// The real rolodex, looping on sample topics.
private struct RolodexDemo: View {
    @State private var landsAt = Date.now.addingTimeInterval(AppConfig.spinDuration)
    @State private var topic = Topic(id: "how-submarines-control-depth", title: "How submarines control depth", domain: "Technology")

    var body: some View {
        RolodexView(target: topic.title, domain: topic.domain, landsAt: landsAt, pool: TopicStore.all)
            .id(landsAt)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(AppConfig.spinDuration + 1.8))
                    if let next = TopicStore.all.randomElement() { topic = next }
                    landsAt = .now.addingTimeInterval(AppConfig.spinDuration)
                }
            }
    }
}
