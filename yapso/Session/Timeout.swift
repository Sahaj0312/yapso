import Foundation
import os

nonisolated struct TimedOut: LocalizedError {
    var errorDescription: String? { "This took too long." }
}

/// Runs `work`, giving up after `seconds`. Unlike a task group, this returns on time even if `work`
/// ignores cancellation (SpeechAnalyzer can hang indefinitely on bad input).
nonisolated func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let resumed = OSAllocatedUnfairLock(initialState: false)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        @Sendable func finish(_ result: Result<T, Error>) {
            let first = resumed.withLock { done in
                defer { done = true }
                return !done
            }
            if first { continuation.resume(with: result) }
        }
        let worker = Task {
            do { finish(.success(try await work())) } catch { finish(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            worker.cancel()
            finish(.failure(TimedOut()))
        }
    }
}
