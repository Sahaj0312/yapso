import Foundation

nonisolated struct Topic: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let domain: String
}

nonisolated enum TopicPicker {
    /// A random topic the user hasn't had yet. Once the pool is exhausted, repeats are allowed.
    static func pick<R: RandomNumberGenerator>(from pool: [Topic], excluding used: Set<String>, using rng: inout R) -> Topic? {
        let fresh = pool.filter { !used.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement(using: &rng)
    }

    static func pick(from pool: [Topic], excluding used: Set<String>) -> Topic? {
        var rng = SystemRandomNumberGenerator()
        return pick(from: pool, excluding: used, using: &rng)
    }
}

nonisolated enum TopicLibrary {
    enum LoadError: Error { case missingResource }

    static func loadBundled(bundle: Bundle = .main) throws -> [Topic] {
        guard let url = bundle.url(forResource: "topics", withExtension: "json") else { throw LoadError.missingResource }
        return try JSONDecoder().decode([Topic].self, from: Data(contentsOf: url))
    }
}
