import Foundation
import Accelerate

/// HF-optimised spectral noise reduction for the TS-890S.
///
/// Algorithm (per 256-sample hop at 48 kHz):
///   1. Time-domain impulse blanker  — removes lightning static / impulse noise
///   2. Overlap-add STFT             — 512-pt Hann window, 50 % overlap
///   3. Minimum-statistics estimator — tracks noise floor across ~1.4 s history
///   4. Decision-directed a priori SNR (α = 0.98)
///   5. Wiener spectral gain with minimum gain floor
///   6. Passband mask                — zero gain outside IF filter width
///   7. Inverse STFT + OLA
///
/// All DSP uses Accelerate (vDSP) — no external library dependencies.
/// Latency: one hop = 256 / 48 000 ≈ 5.3 ms.
/// Passband width is a runtime parameter: set `config.passbandHz` from
/// RadioState whenever the filter width changes.  Any value from ~300 Hz
/// (narrow CW) to 8 000 Hz (wide AM / 4 kHz SSB) is supported.
///
/// Implements `NoiseReductionProcessor` so it is a drop-in replacement
/// for `RNNoiseProcessor` or can be used as the primary stage of
/// `CascadeNoiseReductionProcessor`.
final class HFNoiseReductionProcessor: NoiseReductionProcessor {

    // MARK: - Configuration

    struct Config {
        /// 0 = gentle (gain floor ≈ 0.20), 1 = aggressive (gain floor ≈ 0.01).
        var aggressiveness: Float = 0.5
        /// Audio passband width in Hz.  Gain is zeroed outside this band.
        /// Set to 0 to disable passband masking (process full spectrum).
        /// Typical values: 2400 (SSB), 4000 (wide SSB / AM), 500 (CW).
        var passbandHz: Float = 2400
        /// Enable time-domain impulse blanker (lightning / QRN removal).
        var impulseBlanker: Bool = true
    }

    var config: Config { didSet { recomputeDerived() } }

    // MARK: - NoiseReductionProcessor

    var isAvailable: Bool { true }
    var isEnabled:   Bool = false

    nonisolated deinit { vDSP_destroy_fftsetup(fftSetup) }

    func processFrame48kMono(_ frame: [Float]) -> [Float] {
        var f = frame; processFrame48kMonoInPlace(&f); return f
    }

    func processFrame48kMonoInPlace(_ frame: inout [Float]) {
        guard isEnabled else { return }
        inQ.append(contentsOf: frame)
        while inQ.count >= K.hopN {
            hopScratch.withUnsafeMutableBufferPointer { dst in
                inQ.withUnsafeBufferPointer { src in
                    dst.baseAddress!.update(from: src.baseAddress!, count: K.hopN)
                }
            }
            inQ.removeFirst(K.hopN)
            if config.impulseBlanker { blankerProcess(&hopScratch) }
            outQ.append(contentsOf: olaProcess(hopScratch))
        }
        let outCount = frame.count
        guard outQ.count >= outCount else { return }
        frame.withUnsafeMutableBufferPointer { dst in
            outQ.withUnsafeBufferPointer { src in
                dst.baseAddress!.update(from: src.baseAddress!, count: dst.count)
            }
        }
        outQ.removeFirst(outCount)
    }

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config

        let n    = K.fftN
        let bins = K.binN
        let log2n = vDSP_Length(log2(Float(n)))
        fftSetup  = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.log2n = log2n

        var w = [Float](repeating: 0, count: n)
        vDSP_hann_window(&w, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        window = w

        rawIn   = [Float](repeating: 0, count: n)
        realBuf = [Float](repeating: 0, count: n)
        imagBuf = [Float](repeating: 0, count: n)
        olaAcc  = [Float](repeating: 0, count: n)

        gainBuf    = [Float](repeating: 0, count: bins)
        powerSpec  = [Float](repeating: 1e-6, count: bins)
        noisePsd   = [Float](repeating: 1e-6, count: bins)
        prevGain   = [Float](repeating: 1.0,  count: bins)
        prevPower  = [Float](repeating: 1e-6, count: bins)
        msSmoothed = [Float](repeating: 1e-3, count: bins)
        msWins     = [[Float]](repeating: [Float](repeating: 1e3, count: bins),
                               count: K.subWins)

        // Pre-seed output queue with one FFT-frame of zeros so the caller
        // always receives output samples (first ~10 ms is silence).
        outQ = [Float](repeating: 0, count: n)
        inQ.reserveCapacity(K.hopN * 8)
        outQ.reserveCapacity(K.hopN * 8)

        recomputeDerived()
    }

    // MARK: - Private constants

    private enum K {
        static let fftN    = 512            // FFT size
        static let hopN    = 256            // hop size (50 % overlap)
        static let binN    = fftN / 2 + 1  // unique bins = 257
        static let subWins = 16             // min-stat sub-windows
        static let subHops = 6             // hops per sub-window (~32 ms)
        static let ddAlpha  = Float(0.98)  // decision-directed SNR smoothing
        static let msSmooth = Float(0.92)  // noise floor power smoothing
        static let msBias   = Float(1.66)  // min-stat bias correction
        static let ibAlpha  = Float(0.996) // impulse blanker RMS release
        static let ibThresh = Float(8.0)   // blanker threshold (× RMS)
    }

    // MARK: - DSP state

    private let fftSetup: FFTSetup
    private let log2n:    vDSP_Length
    private let window:   [Float]       // Hann, length K.fftN

    private var rawIn:   [Float]        // sliding analysis window (unwindowed)
    private var realBuf: [Float]        // FFT real part work buffer
    private var imagBuf: [Float]        // FFT imag part work buffer
    private var olaAcc:  [Float]        // overlap-add accumulator

    private var inQ:  [Float] = []
    private var outQ: [Float] = []

    // Reused per-hop scratch buffers — avoid array allocations on every 5.3 ms hop.
    private var hopScratch = [Float](repeating: 0, count: K.hopN)
    private var olaOutHop  = [Float](repeating: 0, count: K.hopN)
    private var gainBuf:    [Float]

    // Spectral state — all length K.binN
    private var powerSpec:  [Float]
    private var noisePsd:   [Float]
    private var prevGain:   [Float]
    private var prevPower:  [Float]

    // Minimum-statistics sub-window ring buffer
    private var msWins:     [[Float]]   // [K.subWins][K.binN]
    private var msSmoothed: [Float]
    private var msHopCount = 0
    private var msWinIdx   = 0

    // Impulse blanker
    private var ibRms: Float = 0.01

    // Derived from Config
    private var gainFloor: Float = 0.105
    private var pbBins:    Int   = K.binN

    // MARK: - OLA engine

    private func olaProcess(_ hop: [Float]) -> [Float] {
        let n    = K.fftN
        let h    = K.hopN
        let bins = K.binN

        // 1. Slide rawIn left by h, fill right with new hop.
        for i in 0..<(n - h) { rawIn[i] = rawIn[i + h] }
        for i in 0..<h        { rawIn[n - h + i] = hop[i] }

        // 2. Apply Hann window → realBuf; clear imagBuf.
        vDSP_vmul(rawIn, 1, window, 1, &realBuf, 1, vDSP_Length(n))
        vDSP_vclr(&imagBuf, 1, vDSP_Length(n))

        // 3. Forward FFT (in-place complex).
        withFFT { vDSP_fft_zip(fftSetup, &$0, 1, log2n, FFTDirection(FFT_FORWARD)) }

        // 4. Power spectrum for bins 0 .. binN-1.
        withReadonlyFFT { vDSP_zvmags(&$0, 1, &powerSpec, 1, vDSP_Length(bins)) }

        // 5. Update noise floor estimate.
        updateNoisePsd()

        // 6. Wiener gain with decision-directed SNR (fills gainBuf).
        computeGain()

        // 7. Apply gain and passband mask.
        for k in 0..<bins {
            let g = (k < pbBins) ? gainBuf[k] : Float(0)
            realBuf[k] *= g
            imagBuf[k] *= g
        }

        // 8. Mirror for negative frequencies (make spectrum Hermitian).
        for k in 1..<(n / 2) {
            realBuf[n - k] =  realBuf[k]
            imagBuf[n - k] = -imagBuf[k]
        }
        // DC and Nyquist are purely real.
        imagBuf[0]     = 0
        imagBuf[n / 2] = 0

        // 9. Inverse FFT.
        withFFT { vDSP_fft_zip(fftSetup, &$0, 1, log2n, FFTDirection(FFT_INVERSE)) }

        // 10. Normalise (vDSP forward+inverse is scaled by N).
        var scale = Float(1) / Float(n)
        vDSP_vsmul(realBuf, 1, &scale, &realBuf, 1, vDSP_Length(n))

        // 11. Overlap-add (Hann at 50 % satisfies COLA — no synthesis window needed).
        vDSP_vadd(olaAcc, 1, realBuf, 1, &olaAcc, 1, vDSP_Length(n))

        // 12. Output first h samples (into reused buffer); shift accumulator.
        for i in 0..<h { olaOutHop[i] = olaAcc[i] }
        for i in 0..<(n - h) { olaAcc[i] = olaAcc[i + h] }
        for i in (n - h)..<n  { olaAcc[i] = 0 }

        return olaOutHop
    }

    // MARK: - Noise floor (minimum statistics)

    private func updateNoisePsd() {
        let bins = K.binN
        var beta    = K.msSmooth
        var invBeta = Float(1) - beta

        // Exponentially smooth current power.
        vDSP_vsmul(msSmoothed, 1, &beta,    &msSmoothed, 1, vDSP_Length(bins))
        vDSP_vsma (powerSpec,  1, &invBeta, msSmoothed, 1, &msSmoothed, 1, vDSP_Length(bins))

        // Flush into a new sub-window periodically.
        msHopCount += 1
        if msHopCount >= K.subHops {
            msHopCount = 0
            msWins[msWinIdx] = msSmoothed
            msWinIdx = (msWinIdx + 1) % K.subWins
        }

        // Noise PSD = minimum across all sub-windows × bias correction.
        for k in 0..<bins {
            var minVal = msWins[0][k]
            for w in 1..<K.subWins { if msWins[w][k] < minVal { minVal = msWins[w][k] } }
            noisePsd[k] = minVal * K.msBias
        }
    }

    // MARK: - Wiener gain (decision-directed SNR)

    private func computeGain() {
        let bins  = K.binN
        let alpha = K.ddAlpha
        let floor = gainFloor

        for k in 0..<bins {
            let noise  = max(noisePsd[k], Float(1e-12))
            // A posteriori SNR
            let gamma  = powerSpec[k] / noise
            // A priori SNR (decision-directed)
            let xi     = alpha * prevGain[k] * prevGain[k] * prevPower[k] / noise
                       + (1 - alpha) * max(gamma - 1, 0)
            // Wiener gain with floor
            let g      = max(floor, xi / (1 + xi))
            gainBuf[k]   = g
            prevGain[k]  = g
            prevPower[k] = powerSpec[k]
        }
    }

    // MARK: - Impulse blanker

    private func blankerProcess(_ hop: inout [Float]) {
        let alpha  = K.ibAlpha
        let thresh = K.ibThresh
        for i in 0..<hop.count {
            let s = hop[i]
            ibRms = alpha * ibRms + (1 - alpha) * abs(s)
            if abs(s) > thresh * ibRms { hop[i] = 0 }
        }
    }

    // MARK: - Helpers

    /// Calls `body` with a mutable `DSPSplitComplex` backed by realBuf / imagBuf.
    private func withFFT(_ body: (inout DSPSplitComplex) -> Void) {
        realBuf.withUnsafeMutableBufferPointer { rp in
            imagBuf.withUnsafeMutableBufferPointer { ip in
                var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                body(&sc)
            }
        }
    }

    /// Calls `body` with a read-only `DSPSplitComplex` (for vDSP functions that take `UnsafePointer`).
    private func withReadonlyFFT(_ body: (inout DSPSplitComplex) -> Void) {
        realBuf.withUnsafeMutableBufferPointer { rp in
            imagBuf.withUnsafeMutableBufferPointer { ip in
                var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                body(&sc)
            }
        }
    }

    private func recomputeDerived() {
        // Gain floor: aggressiveness 0 → 0.20, 1 → 0.01
        gainFloor = 0.20 - config.aggressiveness * 0.19

        // Passband bin cutoff
        if config.passbandHz > 0 {
            let nyquist = Float(48000) / 2
            let frac    = min(config.passbandHz / nyquist, 1.0)
            pbBins = max(1, Int(frac * Float(K.binN)))
        } else {
            pbBins = K.binN
        }
    }
}
