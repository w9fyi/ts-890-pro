import Foundation

/// Pure-Swift wrapper around the librade (RADE V1, "no Python") C API plus the
/// FARGAN vocoder shim. RADE is the neural Radio Autoencoder — the default
/// on-air FreeDV HF voice mode. One instance per active session.
///
/// Pipeline (mirrors radae_nopy's rade_demod_wav.c):
///   8 kHz real SSB Int16  → /32768 → streaming Hilbert → complex RADE_COMP
///   → rade_rx() loop (honours rade_nin() each call) → FARGAN feature vectors
///   → FARGAN vocoder → 16 kHz speech.
///
/// Decoded speech is 16 kHz (RADE_SPEECH_SAMPLE_RATE), unlike codec2's 8 kHz.
final class RADEEngine {
    nonisolated deinit {}   // match FreeDVEngine: avoid isolated-deinit lock crash

    /// RADE currently ships a single waveform (V1). Modelled as an enum so it
    /// slots into the same mode-picker UI as the legacy codec2 modes.
    enum Mode: Int32, CaseIterable, Identifiable {
        case radeV1 = 0
        var id: Int32 { rawValue }
        var label: String { "RADE" }
        var details: String { "Neural voice · default on-air FreeDV HF mode" }
    }

    // MARK: - Callbacks (set before open)

    /// Called on the RX thread after each processed frame. Marshal to main for UI.
    var onStatsUpdate: ((_ sync: Bool, _ snrDB: Int, _ rxStatus: Int32) -> Void)?

    /// Called on main when an End-of-Over frame yields a station callsign.
    var onCallsignReceived: ((String) -> Void)?

    // MARK: - Properties (valid after open)

    private(set) var speechSampleRate: Int = Int(RADE_SPEECH_SAMPLE_RATE) // 16000
    private(set) var modemSampleRate:  Int = Int(RADE_MODEM_SAMPLE_RATE)  // 8000

    var isOpen: Bool { r != nil }

    // MARK: - Private (RADE)

    private var r: UnsafeMutablePointer<rade>?   // struct rade *
    private var fargan: OpaquePointer?       // RADEFargan *  (created via shim)
    private let rxLock = NSLock()

    private var ninMax: Int = 0
    private var nFeatures: Int = 0           // rade_n_features_in_out (floats per rade_tx/rade_rx)
    private var nEooBits: Int = 0

    // Scratch buffers (RX thread only, under rxLock)
    private var complexBuffer: [RADE_COMP] = []   // demodulated IQ awaiting rade_rx
    private var featuresOut: [Float] = []
    private var eooOut: [Float] = []
    private var pcmOut: [Float] = []

    // MARK: - Private (RADE TX — under txLock)

    /// LPCNet feature extractor (RADEEncoder * via shim). RADE's transmitter
    /// consumes 36-float feature vectors; this turns 16 kHz speech into them.
    private var encoder: OpaquePointer?
    private let txLock = NSLock()

    private var nTxOut: Int = 0              // RADE_COMP samples per rade_tx() call (8 kHz)
    private var nTxEooOut: Int = 0           // RADE_COMP samples in the End-of-Over frame

    private var txSpeechBuf: [Int16] = []    // 16 kHz speech awaiting 160-sample feature frames
    private var txFeatureBuf: [Float] = []   // extracted features awaiting a full rade_tx() batch
    private var txComplex: [RADE_COMP] = []  // rade_tx() output scratch
    private var txEooComplex: [RADE_COMP] = [] // rade_tx_eoo() output scratch

    /// Station callsign embedded in the End-of-Over frame (max RADE_EOO_CALLSIGN_MAX
    /// chars, uppercased). Setting it re-encodes the EOO bits if the engine is open.
    var txCallsign: String = "" { didSet { applyTxCallsign() } }

    // MARK: - Streaming Hilbert (real → analytic IQ); matches real2iq.c

    private static let hilbertNTaps = 127
    private static let hilbertDelay = (127 - 1) / 2   // 63
    private static let hilbertCoeffs: [Float] = {
        let n = hilbertNTaps
        var c = [Float](repeating: 0, count: n)
        let center = hilbertDelay
        for i in 0..<n {
            let m = i - center
            if m == 0 || (m & 1) == 0 {
                c[i] = 0
            } else {
                let h = 2.0 / (Float.pi * Float(m))
                let w = 0.54 - 0.46 * cos(2.0 * Float.pi * Float(i) / Float(n - 1))
                c[i] = h * w
            }
        }
        return c
    }()

    // Sliding window of the most recent `hilbertNTaps` input samples, newest last.
    private var hist = [Float](repeating: 0, count: 127)

    private func resetHilbert() {
        for i in hist.indices { hist[i] = 0 }
    }

    /// Push one real sample, return its analytic (complex) value.
    private func hilbertStep(_ x: Float) -> RADE_COMP {
        // shift window: drop oldest, append newest
        hist.removeFirst()
        hist.append(x)
        // newest is hist[126] = x[n]; hist[126 - k] = x[n-k]
        var imag: Float = 0
        let coeffs = RADEEngine.hilbertCoeffs
        for k in 0..<RADEEngine.hilbertNTaps {
            imag += coeffs[k] * hist[126 - k]
        }
        // real path is the input delayed by hilbertDelay to align with the FIR
        let real = hist[126 - RADEEngine.hilbertDelay]
        return RADE_COMP(real: real, imag: imag)
    }

    // MARK: - Open / Close

    /// Opens the RADE decoder. Returns `true` on success; `false` if `rade_open`
    /// fails (callers must not activate the pipeline when this returns false).
    @discardableResult
    func open(mode: Mode = .radeV1) -> Bool {
        close()

        rade_initialize()   // no-op in the no-Python build, kept for API correctness
        // model_file is ignored by librade (weights are compiled in); pass a name
        // anyway for parity with upstream logging.
        var name = Array("rade".utf8CString)
        let flags = RADE_VERBOSE_0
        let handle = name.withUnsafeMutableBufferPointer {
            rade_open($0.baseAddress, flags)
        }
        guard let handle else {
            AppFileLogger.shared.log("RADEEngine: rade_open returned nil")
            rade_finalize()
            return false
        }
        r = handle

        ninMax    = Int(rade_nin_max(handle))
        nFeatures = Int(rade_n_features_in_out(handle))
        nEooBits  = Int(rade_n_eoo_bits(handle))

        featuresOut = [Float](repeating: 0, count: max(nFeatures, 1))
        eooOut      = [Float](repeating: 0, count: max(nEooBits, 1))
        // FARGAN can emit one 160-sample frame per feature frame (36 floats each).
        let maxFrames = max(nFeatures / Int(RADE_FARGAN_FEATURES_PER_FRAME), 1)
        pcmOut = [Float](repeating: 0, count: maxFrames * Int(RADE_FARGAN_SAMPLES_PER_FRAME))

        complexBuffer.removeAll(keepingCapacity: true)
        complexBuffer.reserveCapacity(ninMax * 4)
        resetHilbert()

        fargan = rade_fargan_create()
        if fargan == nil {
            AppFileLogger.shared.log("RADEEngine: rade_fargan_create failed")
        }

        // TX: feature extractor + rade_tx() output sizing.
        nTxOut    = Int(rade_n_tx_out(handle))
        nTxEooOut = Int(rade_n_tx_eoo_out(handle))
        txComplex    = [RADE_COMP](repeating: RADE_COMP(real: 0, imag: 0), count: max(nTxOut, 1))
        txEooComplex = [RADE_COMP](repeating: RADE_COMP(real: 0, imag: 0), count: max(nTxEooOut, 1))
        txSpeechBuf.removeAll(keepingCapacity: true)
        txFeatureBuf.removeAll(keepingCapacity: true)
        encoder = rade_encoder_create()
        if encoder == nil {
            AppFileLogger.shared.log("RADEEngine: rade_encoder_create failed (TX unavailable)")
        }
        applyTxCallsign()

        AppFileLogger.shared.log(
            "RADEEngine: opened \(mode.label) modem=\(modemSampleRate) Hz "
            + "speech=\(speechSampleRate) Hz ninMax=\(ninMax) nFeatures=\(nFeatures) "
            + "nTxOut=\(nTxOut) nTxEoo=\(nTxEooOut)")
        return true
    }

    func close() {
        // Take both locks so an in-flight RX (rxLock) or TX (txLock) frame can't
        // touch `r` / the shims while we free them. Lock order rxLock→txLock is
        // the only place both are held; RX and TX each take just one, so no cycle.
        rxLock.lock()
        txLock.lock()
        defer { txLock.unlock(); rxLock.unlock() }
        if let f = fargan {
            rade_fargan_destroy(f)
            fargan = nil
        }
        if let e = encoder {
            rade_encoder_destroy(e)
            encoder = nil
        }
        if let handle = r {
            rade_close(handle)
            rade_finalize()
            r = nil
            AppFileLogger.shared.log("RADEEngine: closed")
        }
        complexBuffer.removeAll()
        txSpeechBuf.removeAll()
        txFeatureBuf.removeAll()
    }

    // MARK: - RX: 8 kHz Int16 real SSB → 16 kHz Int16 speech

    /// Append modem samples (raw full-scale Int16 at 8 kHz), returning decoded
    /// 16 kHz Int16 speech once full frames are available. Safe from any thread.
    func feedModemSamples(_ samples: [Int16]) -> [Int16] {
        rxLock.lock()
        defer { rxLock.unlock() }
        // Read the handle *under* the lock: close() frees it while holding rxLock,
        // so capturing it before locking risks a use-after-free if deactivate races
        // an in-flight RX frame.
        guard let handle = r else { return [] }

        // real SSB → analytic IQ
        for s in samples {
            complexBuffer.append(hilbertStep(Float(s) / 32768.0))
        }

        var speechAccum: [Int16] = []
        while true {
            let nin = Int(rade_nin(handle))
            guard nin > 0, complexBuffer.count >= nin else { break }

            var rxIn = Array(complexBuffer.prefix(nin))
            complexBuffer.removeFirst(nin)

            var hasEoo: Int32 = 0
            let nOut = rxIn.withUnsafeMutableBufferPointer { rxPtr in
                featuresOut.withUnsafeMutableBufferPointer { featPtr in
                    eooOut.withUnsafeMutableBufferPointer { eooPtr in
                        rade_rx(handle, featPtr.baseAddress, &hasEoo,
                                eooPtr.baseAddress, rxPtr.baseAddress)
                    }
                }
            }

            if nOut > 0, let f = fargan {
                let nFrames = Int(nOut) / Int(RADE_FARGAN_FEATURES_PER_FRAME)
                if nFrames > 0 {
                    let written = featuresOut.withUnsafeBufferPointer { featPtr in
                        pcmOut.withUnsafeMutableBufferPointer { pcmPtr in
                            rade_fargan_synthesize(f, featPtr.baseAddress,
                                                   Int32(nFrames), pcmPtr.baseAddress)
                        }
                    }
                    if written > 0 {
                        speechAccum.reserveCapacity(speechAccum.count + Int(written))
                        for i in 0..<Int(written) {
                            speechAccum.append(floatToInt16(pcmOut[i]))
                        }
                    }
                }
            }

            if hasEoo != 0 { handleEoo(handle) }
            collectStats(handle)
        }
        return speechAccum
    }

    // MARK: - TX: 16 kHz Int16 speech → 8 kHz Int16 real modem

    /// Clear the encoder history and pending TX buffers. Call at the start of
    /// each over (PTT down) so the feature extractor begins from a clean state.
    func resetTx() {
        txLock.lock()
        defer { txLock.unlock() }
        if let e = encoder { rade_encoder_reset(e) }
        txSpeechBuf.removeAll(keepingCapacity: true)
        txFeatureBuf.removeAll(keepingCapacity: true)
    }

    /// Stream 16 kHz Int16 speech into the encoder; returns whatever real 8 kHz
    /// Int16 modem samples are ready. Speech is buffered internally into
    /// 160-sample (10 ms) feature frames, then batched into rade_tx() calls.
    /// Safe from any thread (TX thread); concurrent with RX (separate state).
    func encodeFromSpeech(_ speech: [Int16]) -> [Int16] {
        txLock.lock()
        defer { txLock.unlock() }
        guard let handle = r, let enc = encoder, nFeatures > 0, nTxOut > 0 else { return [] }

        txSpeechBuf.append(contentsOf: speech)

        // Speech → features, one 160-sample frame at a time (extractor is stateful).
        let frameLen = Int(RADE_ENC_SAMPLES_PER_FRAME)
        let featPerFrame = Int(RADE_ENC_FEATURES_PER_FRAME)
        var features = [Float](repeating: 0, count: featPerFrame)
        while txSpeechBuf.count >= frameLen {
            var frame = Array(txSpeechBuf.prefix(frameLen))
            txSpeechBuf.removeFirst(frameLen)
            frame.withUnsafeBufferPointer { sp in
                _ = features.withUnsafeMutableBufferPointer { fp in
                    rade_encoder_compute_features(enc, sp.baseAddress, fp.baseAddress)
                }
            }
            txFeatureBuf.append(contentsOf: features)
        }

        // Features → IQ, one rade_tx() batch (nFeatures floats) at a time.
        var modemOut: [Int16] = []
        while txFeatureBuf.count >= nFeatures {
            var featIn = Array(txFeatureBuf.prefix(nFeatures))
            txFeatureBuf.removeFirst(nFeatures)
            let n = featIn.withUnsafeMutableBufferPointer { fp in
                txComplex.withUnsafeMutableBufferPointer { cp in
                    rade_tx(handle, cp.baseAddress, fp.baseAddress)
                }
            }
            appendReal(of: txComplex, count: Int(n), into: &modemOut)
        }
        return modemOut
    }

    /// Generate the End-of-Over frame (real 8 kHz Int16) carrying the callsign,
    /// and drop any partial buffered speech. Call once at the end of an over.
    func finishOver() -> [Int16] {
        txLock.lock()
        defer { txLock.unlock() }
        txSpeechBuf.removeAll(keepingCapacity: true)
        txFeatureBuf.removeAll(keepingCapacity: true)
        guard let handle = r, nTxEooOut > 0 else { return [] }
        let n = txEooComplex.withUnsafeMutableBufferPointer { cp in
            rade_tx_eoo(handle, cp.baseAddress)
        }
        var out: [Int16] = []
        appendReal(of: txEooComplex, count: Int(n), into: &out)
        return out
    }

    /// Take the real part of the first `count` analytic IQ samples (the inverse
    /// of the RX Hilbert step) and append as full-scale Int16 real SSB audio.
    private func appendReal(of iq: [RADE_COMP], count: Int, into out: inout [Int16]) {
        guard count > 0 else { return }
        out.reserveCapacity(out.count + count)
        for i in 0..<min(count, iq.count) { out.append(floatToInt16(iq[i].real)) }
    }

    private func applyTxCallsign() {
        txLock.lock()
        defer { txLock.unlock() }
        guard let handle = r, nEooBits > 0 else { return }
        let cs = String(txCallsign.uppercased().prefix(Int(RADE_EOO_CALLSIGN_MAX)))
        cs.withCString { rade_tx_set_eoo_callsign(handle, $0) }
    }

    // MARK: - Helpers

    private func floatToInt16(_ v: Float) -> Int16 {
        let scaled = v * 32768.0
        if scaled >= 32767.0 { return 32767 }
        if scaled <= -32767.0 { return -32767 }
        return Int16((scaled).rounded())
    }

    private func collectStats(_ handle: UnsafeMutablePointer<rade>) {
        let sync = rade_sync(handle) != 0
        let snr = Int(rade_snrdB_3k_est(handle))
        onStatsUpdate?(sync, snr, rade_sync(handle))
    }

    private func handleEoo(_ handle: UnsafeMutablePointer<rade>) {
        guard nEooBits > 0 else { return }
        var callsign = [CChar](repeating: 0, count: 16)
        let got = eooOut.withUnsafeBufferPointer { eooPtr in
            callsign.withUnsafeMutableBufferPointer { csPtr in
                rade_rx_get_eoo_callsign(eooPtr.baseAddress, Int32(nEooBits), csPtr.baseAddress)
            }
        }
        if got != 0 {
            let s = String(cString: callsign)
            if !s.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.onCallsignReceived?(s) }
            }
        }
    }
}
