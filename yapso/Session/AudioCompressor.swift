import AVFoundation

/// Re-encodes a finished recording as mono AAC: about 350 KB for a full 90 seconds instead of ~4 MB of PCM,
/// which keeps the upload fast on cellular and the recordings folder small.
nonisolated enum AudioCompressor {
    static func compressToAAC(_ sourceURL: URL) throws -> URL {
        let destination = sourceURL.deletingPathExtension().appendingPathExtension("m4a")
        // Written under a temporary name so a crash never leaves a half-written file that looks finished.
        let partial = sourceURL.deletingPathExtension().appendingPathExtension("partial.m4a")
        try? FileManager.default.removeItem(at: partial)

        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 32_000,
        ]
        do {
            let output = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: format.commonFormat,
                                         interleaved: format.isInterleaved)
            let chunk: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw CocoaError(.fileReadUnknown) }
            while source.framePosition < source.length {
                try source.read(into: buffer, frameCount: chunk)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        }  // The output file is closed (and finalized) when it goes out of scope.

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }
}
