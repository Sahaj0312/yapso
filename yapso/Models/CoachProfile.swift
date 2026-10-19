import Foundation
import SwiftData

/// The coach's rolling memory of the user. Logically a singleton; CloudKit sync can briefly
/// produce duplicates across devices, so always read through `latest(in:)`.
@Model
final class CoachProfile {
    var updatedAt: Date = Date()
    var memoryData: Data?

    init(memory: CoachMemory, updatedAt: Date = .now) {
        self.updatedAt = updatedAt
        self.memory = memory
    }

    var memory: CoachMemory {
        get { memoryData.flatMap { try? JSONDecoder().decode(CoachMemory.self, from: $0) } ?? CoachMemory() }
        set { memoryData = try? JSONEncoder().encode(newValue) }
    }

    static func latest(in context: ModelContext) -> CoachProfile? {
        var descriptor = FetchDescriptor<CoachProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
