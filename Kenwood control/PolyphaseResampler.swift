import Foundation

/// Polyphase FIR resampler: 16 kHz → 48 kHz (3× integer upsample).
///
/// Design:
///   - Prototype lowpass FIR, Kaiser-windowed sinc, N = 24 taps (8 per phase)
///   - Cutoff: 8 kHz (= Nyquist of 16 kHz input), stopband ≈ 60 dB (β = 5.0)
///   - Three polyphase sub-filters, one per output sample between each input pair
///   - Circular delay line maintains state across packet boundaries automatically
///   - Unity passband gain; no post-scale needed
///
/// Usage:
///   let r = PolyphaseResampler16To48()
///   let out48k = r.process(samples16k)   // out48k.count == samples16k.count * 3
///   r.reset()                             // call on reconnect to clear delay line
final class PolyphaseResampler16To48 {
    nonisolated deinit {}

    private static let numPhases    = 3   // upsample factor L
    private static let tapsPerPhase = 8   // FIR taps per polyphase branch

    // Polyphase coefficient bank: bank[phase 0‥2][tap 0‥7]
    // Built once at init from a Kaiser-windowed sinc prototype.
    private let bank: [[Float]]

    // Circular delay line — holds the tapsPerPhase most recent input samples.
    private var delayLine: [Float]
    private var writePos = 0

    init() {
        bank      = Self.buildPolyphaseBank()
        delayLine = [Float](repeating: 0.0, count: Self.tapsPerPhase)
    }

    /// Zero the delay line and reset write position.
    /// Call whenever the audio stream is restarted (radio reconnect, etc.)
    /// so stale samples from the previous session don't bleed into new audio.
    func reset() {
        for i in delayLine.indices { delayLine[i] = 0.0 }
        writePos = 0
    }

    /// Resample `input` from 16 kHz to 48 kHz.
    /// Returns exactly `input.count × 3` samples.
    func process(_ input: [Float]) -> [Float] {
        let outputCount = input.count * Self.numPhases
        var output = [Float](repeating: 0.0, count: outputCount)
        var outIdx = 0

        for sample in input {
            // Write new input sample into the circular delay line.
            delayLine[writePos] = sample

            // Compute one output sample for each of the numPhases sub-filters.
            // bank[p][k] = h[L·k + p], where h is the prototype lowpass FIR.
            // y[L·n + p] = Σ_k  bank[p][k] · x[n - k]
            for p in 0..<Self.numPhases {
                let coeffs = bank[p]
                var acc: Float = 0.0
                var pos = writePos
                for tap in 0..<Self.tapsPerPhase {
                    acc += coeffs[tap] * delayLine[pos]
                    pos = pos == 0 ? Self.tapsPerPhase - 1 : pos - 1
                }
                output[outIdx] = acc
                outIdx += 1
            }

            writePos = (writePos + 1) % Self.tapsPerPhase
        }

        return output
    }

    // MARK: - Filter design

    /// Build the 3 × 8 polyphase coefficient bank from a Kaiser-windowed sinc prototype.
    private static func buildPolyphaseBank() -> [[Float]] {
        let N      = numPhases * tapsPerPhase   // 24 prototype taps total
        let beta   = Float(5.0)                  // Kaiser β → ~60 dB stopband attenuation
        let center = Float(N - 1) / 2.0          // 11.5 — filter symmetry axis
        let i0Beta = besselI0(beta)

        // Prototype lowpass FIR:
        //   h[n] = sinc((n − center) / L) × Kaiser(n, β)
        //
        // The sinc argument (n−center)/L gives cutoff at fs_in/2 = 8 kHz.
        // Kaiser window controls the stopband floor.
        // Normalisation below ensures each polyphase sub-filter sums to 1.0
        // so DC gain through the upsampler is unity.
        var h = [Float](repeating: 0.0, count: N)
        for n in 0..<N {
            let x      = (Float(n) - center) / Float(numPhases)
            let sinc   = abs(x) < 1e-6 ? Float(1.0) : sin(.pi * x) / (.pi * x)
            let norm   = 2.0 * Float(n) / Float(N - 1) - 1.0   // −1 ‥ 1
            let window = besselI0(beta * sqrt(max(0.0, 1.0 - norm * norm))) / i0Beta
            h[n] = sinc * window
        }

        // Normalise: scale h so the sum of the entire prototype equals numPhases,
        // which guarantees each polyphase branch sums to ≈ 1.0 (unity amplitude).
        let totalSum = h.reduce(0.0, +)
        if totalSum > 0 {
            let scale = Float(numPhases) / totalSum
            for i in h.indices { h[i] *= scale }
        }

        // Decompose into polyphase bank.
        // bank[p][k] = h[L·k + p]  (p = phase, k = tap index within phase)
        var bankOut = [[Float]](
            repeating: [Float](repeating: 0.0, count: tapsPerPhase),
            count: numPhases
        )
        for p in 0..<numPhases {
            for k in 0..<tapsPerPhase {
                bankOut[p][k] = h[numPhases * k + p]
            }
        }
        return bankOut
    }

    /// Modified Bessel function of the first kind, order 0 (I₀).
    /// Computed via the standard power-series expansion; converges rapidly for β ≤ 10.
    private static func besselI0(_ x: Float) -> Float {
        var sum:  Float = 1.0
        var term: Float = 1.0
        let halfX = x / 2.0
        for k in 1...25 {
            let t = halfX / Float(k)
            term *= t * t
            sum  += term
            if term < 1e-12 { break }
        }
        return sum
    }
}
