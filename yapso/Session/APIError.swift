import Foundation

/// Failures talking to the Worker (or Deepgram directly), for transcription and feedback alike.
nonisolated enum APIError: LocalizedError {
    case offline
    case rateLimited
    case server(status: Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline."
        case .rateLimited: "You've hit today's limit. Try again tomorrow."
        case .server(let status): "The server had a problem (\(status))."
        case .badResponse: "The server sent back something unexpected."
        }
    }

    static func check(_ response: HTTPURLResponse) throws {
        if response.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw APIError.server(status: response.statusCode) }
    }

    /// Network failures that mean "no connection", as opposed to the service misbehaving.
    static func isOffline(_ error: Error) -> Bool {
        if case APIError.offline = error { return true }
        guard let urlError = error as? URLError else { return false }
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        ]
        return offlineCodes.contains(urlError.code)
    }
}
