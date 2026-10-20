import Foundation

/// Deepgram Nova-3 transcription, through the Worker (which holds the API key and picks the model).
nonisolated enum CloudTranscriber {
    static func transcribe(fileURL: URL, keyterms: [String]) async throws -> (text: String, words: [TranscribedWord]) {
        var request = makeRequest(keyterms: keyterms)
        request.httpMethod = "POST"
        request.setValue(fileURL.pathExtension == "m4a" ? "audio/mp4" : "audio/x-caf", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        } catch {
            throw APIError.isOffline(error) ? APIError.offline : error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        try APIError.check(http)
        return try parse(data)
    }

    private static func makeRequest(keyterms: [String]) -> URLRequest {
        // Keyterm prompting helps with the niche vocabulary every topic brings ("Lindy", "Rosetta").
        let keytermItems = keyterms.map { URLQueryItem(name: "keyterm", value: $0) }

        if let key = AppConfig.directDeepgramKey {
            var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
            // Mirrors the Worker's parameters.
            components.queryItems = [
                URLQueryItem(name: "model", value: "nova-3"),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "filler_words", value: "true"),
                URLQueryItem(name: "punctuate", value: "true"),
            ] + keytermItems
            var request = URLRequest(url: components.url!)
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
            return request
        }
        var components = URLComponents(url: AppConfig.apiBaseURL.appending(path: "transcribe"), resolvingAgainstBaseURL: false)!
        components.queryItems = keytermItems
        var request = URLRequest(url: components.url!)
        request.setValue(AppConfig.deviceID, forHTTPHeaderField: "X-Yapso-Device")
        return request
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
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw APIError.badResponse }
        guard let best = response.results.channels.first?.alternatives.first else { return ("", []) }
        // Leading spaces match the on-device transcriber's tokens, which the transcript view relies on.
        let words = best.words.enumerated().map { index, word in
            TranscribedWord(text: (index > 0 ? " " : "") + (word.punctuated_word ?? word.word), start: word.start, end: word.end)
        }
        return (best.transcript.trimmingCharacters(in: .whitespacesAndNewlines), words)
    }
}
