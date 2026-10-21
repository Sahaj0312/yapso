import Foundation

/// The real-life moments users told us they struggle with, for rehearsal.
nonisolated enum ScenarioCategory: String, Codable, CaseIterable, Sendable {
    case interviews, speakingUp, presenting, meetings, everyday

    var title: String {
        switch self {
        case .interviews: "Interviews"
        case .speakingUp: "Speaking up"
        case .presenting: "Presenting"
        case .meetings: "Meetings"
        case .everyday: "Everyday"
        }
    }

    var symbol: String {
        switch self {
        case .interviews: "briefcase"
        case .speakingUp: "hand.raised"
        case .presenting: "rectangle.on.rectangle"
        case .meetings: "person.3"
        case .everyday: "cup.and.saucer"
        }
    }

    /// Categories in the order to show them: the user's own situations first, from their onboarding answers
    /// (the raw strings saved in `OnboardingAnswers`).
    static func ordered(for answers: OnboardingAnswers?) -> [ScenarioCategory] {
        var first: [ScenarioCategory] = []
        switch answers?.situation {
        case "Interviews": first.append(.interviews)
        case "Presentations": first.append(.presenting)
        case "Meetings": first.append(.meetings)
        case "Explaining things to friends", "I ramble in general": first.append(.everyday)
        default: break
        }
        if answers?.struggles.contains("I lose confidence") == true { first.append(.speakingUp) }
        let rest = allCases.filter { !first.contains($0) }
        return first + rest
    }
}

/// One rehearsal: a situation with the line the user answers. Bundled in `scenarios.json`.
nonisolated struct Scenario: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// Short card title ("Tell me about yourself").
    let title: String
    /// What the user responds to, as it would be said to them.
    let prompt: String
    let category: ScenarioCategory
}

nonisolated enum ScenarioLibrary {
    static func load(from url: URL) throws -> [Scenario] {
        try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: url))
    }

    /// Today's suggestions: two from the user's first category, then one each from the next ones, preferring
    /// scenarios they haven't tried. Rotates daily but stays the same all day.
    static func picks(from scenarios: [Scenario], order: [ScenarioCategory], attempted: Set<String>, day: DayKey,
                      count: Int = 4) -> [Scenario] {
        guard !scenarios.isEmpty else { return [] }
        let dayNumber = Int(day.date()?.timeIntervalSinceReferenceDate ?? 0) / 86_400
        var picked: [Scenario] = []

        func next(in category: ScenarioCategory) -> Scenario? {
            let pool = scenarios.filter { $0.category == category && !picked.contains($0) }
            guard !pool.isEmpty else { return nil }
            let rotated = Array(pool[(dayNumber % pool.count)...] + pool[..<(dayNumber % pool.count)])
            return rotated.first { !attempted.contains($0.id) } ?? rotated.first
        }

        let pattern = order.isEmpty ? [] : [order[0], order[0]] + order.dropFirst()
        for category in pattern.prefix(count) {
            if let scenario = next(in: category) { picked.append(scenario) }
        }
        // Top up from the remaining categories if the first ones ran dry.
        for category in order where picked.count < count {
            if let scenario = next(in: category) { picked.append(scenario) }
        }
        return picked
    }

    static func loadBundled(bundle: Bundle = .main) throws -> [Scenario] {
        guard let url = bundle.url(forResource: "scenarios", withExtension: "json") else { throw TopicLibrary.LoadError.missingResource }
        return try load(from: url)
    }
}
