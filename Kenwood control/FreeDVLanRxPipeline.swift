import Foundation
import AVFoundation

/// Intercepts raw 16 kHz Int16 samples from KenwoodLanAudioReceiver,
/// runs them through FreeDVEngine (→ 8 kHz speech), and emits 48 kHz Float
/// for AudioOutputPlayer — bypassing the normal NR LanAudioPipeline.
final class FreeDVLanRxPipeline {
    nonisolated deinit {}   // prevent Swift 6.1 isolated-deinit crash on macOS 26

    /// 48 kHz Float mono output — wire this to AudioOutputPlayer / LanAudioPipeline.
    var onAudio48kMono: (([Float]) -> Void)?

    private let engine: FreeDVEngine
    private var lastSpeechSample: Float?

    // Downsampling state (16→8 kHz): simple decimation by 2.
    private var decimCounter: Int = 0
    private var modem8kBuffer: [Int16] = []

    init(engine: FreeDVEngine) {
        self.engine = engine
    }

    func reset() {
        decimCounter = 0
        modem8kBuffer.removeAll()
        lastSpeechSample = nil
    }

    /// Feed 16 kHz Int16 samples from KNS UDP packet (always 320 samples).
    func feed16kSamples(_ samples: [Int16]) {
        // Decimate 16→8 kHz: keep every other sample.
        var decimated = [Int16]()
        decimated.reserveCapacity(samples.count / 2)
        for (i, s) in samples.enumerated() {
            if (i + decimCounter) % 2 == 0 { decimated.append(s) }
        }
        decimCounter = (decimCounter + samples.count) % 2
        modem8kBuffer.append(contentsOf: decimated)

        // Feed to FreeDVEngine (handles its own nin-sized buffering).
        let speech8k = engine.feedModemSamples(modem8kBuffer)
        modem8kBuffer.removeAll(keepingCapacity: true)

        guard !speech8k.isEmpty else { return }

        // Convert Int16 → Float and upsample 8 kHz → 48 kHz (×6, linear interpolation).
        let speechFloat = speech8k.map { Float($0) / 32768.0 }
        var out48k = [Float]()
        out48k.reserveCapacity(speechFloat.count * 6)

        if let prev = lastSpeechSample {
            if let first = speechFloat.first {
                appendSextuples(from: prev, to: first, into: &out48k)
            }
            for i in 0 ..< (speechFloat.count - 1) {
                appendSextuples(from: speechFloat[i], to: speechFloat[i + 1], into: &out48k)
            }
        } else {
            // No prior sample — just repeat first sample 6× for the very first chunk.
            for i in 0 ..< (speechFloat.count - 1) {
                appendSextuples(from: speechFloat[i], to: speechFloat[i + 1], into: &out48k)
            }
        }
        lastSpeechSample = speechFloat.last

        if !out48k.isEmpty { onAudio48kMono?(out48k) }
    }

    // Linearly interpolate 6 output samples between `a` and `b` (exclusive of `b`).
    private func appendSextuples(from a: Float, to b: Float, into out: inout [Float]) {
        let d = b - a
        for k in 0..<6 { out.append(a + d * Float(k) / 6.0) }
    }
}
