import SwiftData
import SwiftUI

/// First launch: the rules, three quick questions that seed the coach, a reflect-back, the mic, then the soft paywall.
/// No speaking happens here.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @State private var step: Step = .oneTopic
    @State private var forward = true
    @State private var situation: Situation?
    @State private var struggles: [Struggle] = []
    @State private var goal: Goal?
    @State private var showPaywall = false

    enum Step: Int, CaseIterable {
        case oneTopic, tenMinutes, ninetySeconds, situation, struggles, goal, reflect, microphone
    }

    var body: some View {
        VStack(spacing: 0) {
            header
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
            }
            .opacity(step == .oneTopic ? 0 : 1)
            .disabled(step == .oneTopic)
            .accessibilityLabel("Back")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.primary)
                        .frame(width: proxy.size.width * Double(step.rawValue + 1) / Double(Step.allCases.count))
                }
            }
            .frame(height: 4)
            .animation(.smooth, value: step)

            Color.clear.frame(width: 32, height: 32)
        }
        .foregroundStyle(.primary)
        .padding(.bottom, 32)
    }

    private var footer: some View {
        Button(primaryLabel) { advance() }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.35)
            .animation(.smooth(duration: 0.2), value: canContinue)
    }

    private var primaryLabel: String {
        switch step {
        case .reflect: "That's me"
        case .microphone: Permissions.microphoneGranted ? "Continue" : "Allow microphone"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .situation: situation != nil
        case .struggles: !struggles.isEmpty
        case .goal: goal != nil
        default: true
        }
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

    // MARK: - Pages

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .oneTopic:
            RulePage(eyebrow: "Every day", title: "One topic you didn't choose.",
                     detail: "Spin once a day for something niche, like how submarines dive or why Venice is sinking. Once it lands, it's yours.") {
                RolodexDemo()
            }
        case .tenMinutes:
            RulePage(eyebrow: "Then", title: "Ten minutes to learn it.",
                     detail: "Research anywhere: Google, YouTube, a book. The clock keeps running while you're away, and we'll nudge you before time's up.") {
                ClockDemo()
            }
        case .ninetySeconds:
            RulePage(eyebrow: "Then", title: "Ninety seconds to explain it.",
                     detail: "Speaking starts on its own. One take, no restarts. Then you get honest feedback on how clearly you explained it.") {
                RingDemo()
            }
        case .situation:
            QuestionPage(title: "When does speaking trip you up?", subtitle: nil) {
                ForEach(Situation.allCases) { option in
                    OptionRow(title: option.rawValue, selected: situation == option, multiple: false) {
                        situation = option
                    }
                }
            }
        case .struggles:
            QuestionPage(title: "What happens?", subtitle: "Pick all that apply.") {
                ForEach(Struggle.allCases) { option in
                    OptionRow(title: option.rawValue, selected: struggles.contains(option), multiple: true) {
                        if let index = struggles.firstIndex(of: option) {
                            struggles.remove(at: index)
                        } else {
                            struggles.append(option)
                        }
                    }
                }
            }
        case .goal:
            QuestionPage(title: "What's it for?", subtitle: nil) {
                ForEach(Goal.allCases) { option in
                    OptionRow(title: option.rawValue, selected: goal == option, multiple: false) {
                        goal = option
                    }
                }
            }
        case .reflect:
            ReflectPage(text: reflection)
        case .microphone:
            RulePage(eyebrow: "One last thing", title: "Yapso needs to hear you.",
                     detail: "Your talk is transcribed so your coach can give feedback. The recording stays on your phone for 30 days, then it's deleted.") {
                Illustration(name: "IllustrationMicrophone", height: 220)
            }
        }
    }

    /// `-yapsoOnboardingStep <0-7|paywall>` (Debug only) opens on that page with sample answers, for screenshots.
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

    /// "In meetings, you blank under pressure and ramble." plus how Yapso trains it.
    private var reflection: String {
        let habits = struggles.map(\.habit)
        let list: String = switch habits.count {
        case 0: "lose the thread"
        case 1: habits[0]
        default: habits.dropLast().joined(separator: ", ") + " and " + habits.last!
        }
        let opener = situation?.phrase.map { "\($0), you \(list)." } ?? "You \(list)."
        let training = "Yapso trains exactly that: a topic you didn't pick, ten minutes to get it, and ninety seconds to say it clearly, every day."
        let focus = struggles.first.map { " Your coach will watch for \($0.watchFor) from day one." } ?? ""
        return [opener.prefix(1).uppercased() + opener.dropFirst(), training + focus, goal?.closer ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
        case .blank: "the moments you freeze"
        case .um: "your fillers"
        case .ramble: "whether you land your point"
        case .fast: "your pace"
        case .confidence: "where you start to hedge"
        }
    }
}

private enum Goal: String, CaseIterable, Identifiable {
    case career = "My career"
    case school = "School"
    case confidence = "Confidence"
    case sharper = "Just getting sharper"
    var id: Self { self }

    var closer: String {
        switch self {
        case .career: "Ninety seconds a day adds up to the person who explains things well at work."
        case .school: "Ninety seconds a day adds up to answers that land in class and in exams."
        case .confidence: "Ninety seconds a day adds up to trusting yourself when it's your turn to talk."
        case .sharper: "Ninety seconds a day, and a lot of niche things learned along the way."
        }
    }
}

// MARK: - Page layouts

private struct RulePage<Visual: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let visual: Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            visual
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            Eyebrow(eyebrow).padding(.bottom, 10)
            Text(title)
                .font(.display)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }
}

private struct QuestionPage<Options: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let options: Options

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer()
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .font(.title3)
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Color.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.primary.opacity(0.85) : Color.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

private struct ReflectPage: View {
    let text: String
    @State private var shown = false

    var body: some View {
        let paragraphs = text.components(separatedBy: "\n\n")
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow("Here's what we heard")
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(index == 0 ? .display : .body)
                    .foregroundStyle(index == 0 ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)
                    .animation(.smooth(duration: 0.7).delay(0.15 + Double(index) * 0.35), value: shown)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .onAppear { shown = true }
    }
}

// MARK: - Rule visuals

/// The real rolodex, looping on sample topics.
private struct RolodexDemo: View {
    @State private var landsAt = Date.now.addingTimeInterval(AppConfig.spinDuration)
    @State private var target = "How submarines control depth"

    var body: some View {
        RolodexView(target: target, domain: "Technology", landsAt: landsAt, pool: TopicStore.all)
            .id(landsAt)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(AppConfig.spinDuration + 1.8))
                    let next = TopicStore.all.randomElement()
                    target = next?.title ?? target
                    landsAt = .now.addingTimeInterval(AppConfig.spinDuration)
                }
            }
    }
}

/// A research clock ticking down from 10:00, fast-forwarded.
private struct ClockDemo: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) * 30
            Text((600 - elapsed).clockString)
                .font(.system(size: 88, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth, value: elapsed)
        }
    }
}

/// The speaking ring filling over a few seconds, on a loop.
private struct RingDemo: View {
    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text((90 * (1 - progress)).clockString)
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
            }
            .frame(width: 180, height: 180)
        }
    }
}
