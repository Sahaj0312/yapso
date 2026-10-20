import Foundation

nonisolated enum TranscriptionError: LocalizedError {
    case offline
    case notConfigured
    case server(status: Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline."
        case .notConfigured: "Transcription isn't set up in this build."
        case .server(let status): "The transcription service had a problem (\(status))."
        case .badResponse: "The transcription service sent back something unexpected."
        }
    }

    /// Network failures that mean "no connection", as opposed to the service misbehaving.
    static func isOffline(_ error: Error) -> Bool {
        if case TranscriptionError.offline = error { return true }
        guard let urlError = error as? URLError else { return false }
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        ]
        return offlineCodes.contains(urlError.code)
    }
}

/// Deepgram Nova-3 transcription. Release builds go through the Worker (which holds the API key);
/// Debug builds can call Deepgram directly with `-yapsoDeepgramKey <key>`.
nonisolated enum CloudTranscriber {
    static func transcribe(fileURL: URL, keyterms: [String]) async throws -> (text: String, words: [TranscribedWord]) {
        var request = try makeRequest(keyterms: keyterms)
        request.httpMethod = "POST"
        request.setValue(fileURL.pathExtension == "m4a" ? "audio/mp4" : "audio/x-caf", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        } catch {
            throw TranscriptionError.isOffline(error) ? TranscriptionError.offline : error
        }
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw TranscriptionError.server(status: http.statusCode) }
        return try parse(data)
    }

    private static func makeRequest(keyterms: [String]) throws -> URLRequest {
        var query = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "filler_words", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        // Keyterm prompting helps with the niche vocabulary every topic brings ("Lindy", "Rosetta").
        query += keyterms.map { URLQueryItem(name: "keyterm", value: $0) }

        if let key = AppConfig.deepgramKey {
            var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
            return request
        }
        if let base = AppConfig.apiBaseURL {
            var components = URLComponents(url: base.appending(path: "transcribe"), resolvingAgainstBaseURL: false)!
            components.queryItems = keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
            return URLRequest(url: components.url!)
        }
        throw TranscriptionError.notConfigured
    }

    /// Deepgram's response shape; the Worker passes it through unchanged.
    private struct Response: Decodable {
        struct Results: Decodable { var channels: [Channel] }
        struct Channel: Decodable { var alternatives: [Alternative] }
        struct Alternative: Decodable {
            var transcript: String
            var words: [Word]
        }
        struct Word: Decodable {
            var word: String
            var punctuated_word: String?
            var start: Double
            var end: Double
        }
        var results: Results
    }

    static func parse(_ data: Data) throws -> (text: String, words: [TranscribedWord]) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw TranscriptionError.badResponse }
        guard let best = response.results.channels.first?.alternatives.first else { return ("", []) }
        // Leading spaces match the on-device transcriber's tokens, which the transcript view relies on.
        let words = best.words.enumerated().map { index, word in
            TranscribedWord(text: (index > 0 ? " " : "") + (word.punctuated_word ?? word.word), start: word.start, end: word.end)
        }
        return (best.transcript.trimmingCharacters(in: .whitespacesAndNewlines), words)
    }
}
