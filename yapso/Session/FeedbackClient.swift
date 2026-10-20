import Foundation

/// Asks the Worker's coach for content feedback on one talk. The prompt lives in the Worker; this sends only facts.
nonisolated enum FeedbackClient {
    struct Request: Encodable, Sendable {
        struct Topic: Encodable, Sendable { var title: String; var domain: String }
        struct Metrics: Encodable, Sendable {
            var wordCount: Int
            var wordsPerMinute: Double
            var fillerCount: Int
            var longestPause: Double
            var secondsUsed: Double
        }
        struct Averages: Encodable, Sendable {
            var wordsPerMinute: Double
            var fillerCount: Double
            var longestPause: Double
            var secondsUsed: Double
        }
        struct Previous: Encodable, Sendable {
            var transcript: String
            var ratings: [String: Int]
        }

        var kind: AttemptKind
        var topic: Topic
        var transcript: String
        var metrics: Metrics
        var averages: Averages?
        var memory: CoachMemory
        var previous: Previous?
    }

    /// The model's reply. Daily talks also get a replacement memory (without onboarding answers, which only the app keeps).
    private struct Response: Decodable {
        struct Rating: Decodable { var score: Int; var reason: String }
        struct Ratings: Decodable { var clarity, structure, accuracy, ownership: Rating }
        struct Memory: Decodable {
            var weaknesses: [FocusArea]
            var strengths: [String]
            var recentTips: [String]
        }

        var coachNote: String?
        var ratings: Ratings
        var flaggedClaims: [FlaggedClaim]
        var whatYouMissed: [String]
        var nextTimeTip: String
        var comparison: String?
        var memory: Memory?
    }

    static func request(_ body: Request) async throws -> (feedback: ContentFeedback, memory: CoachMemory?) {
        let data = try await post(body)
        guard let reply = try? JSONDecoder().decode(Response.self, from: data) else { throw APIError.badResponse }
        return (feedback(from: reply), reply.memory.map { CoachMemory(weaknesses: $0.weaknesses, strengths: $0.strengths, recentTips: $0.recentTips) })
    }

    /// The calibration talk's reply: the speaker type and starting focus areas. Baselines are filled in by the caller.
    struct CalibrationReply: Decodable, Sendable {
        var type: SpeakerType
        var summary: String
        var strengths: [String]
        var workOn: [FocusArea]
        var firstTip: String
    }

    static func calibrate(_ body: Request) async throws -> CalibrationReply {
        let data = try await post(body)
        guard let reply = try? JSONDecoder().decode(CalibrationReply.self, from: data) else { throw APIError.badResponse }
        return reply
    }

    private static func post(_ body: Request) async throws -> Data {
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: "feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.deviceID, forHTTPHeaderField: "X-Yapso-Device")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.isOffline(error) ? APIError.offline : error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        try APIError.check(http)
        return data
    }

    private static func feedback(from reply: Response) -> ContentFeedback {
        let r = reply.ratings
        let ratings: [(ContentCriterion, Response.Rating)] = [
            (.clarity, r.clarity), (.structure, r.structure), (.accuracy, r.accuracy), (.ownership, r.ownership),
        ]
        return ContentFeedback(
            coachNote: reply.coachNote,
            ratings: ratings.map { CriterionRating(criterion: $0, score: min(5, max(1, $1.score)), reason: $1.reason) },
            flaggedClaims: reply.flaggedClaims,
            whatYouMissed: reply.whatYouMissed,
            nextTimeTip: reply.nextTimeTip,
            comparison: reply.comparison
        )
    }
}
