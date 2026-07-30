import Foundation

/// Pure Swift wrapper around the codec2 FreeDV C API.
/// One instance per active FreeDV session. Open before use, close when done.
final class FreeDVEngine {
    nonisolated deinit {}   // prevent Swift 6.1 isolated-deinit crash (NSLock holds os_unfair_lock)

    enum Mode: Int32, CaseIterable, Identifiable {
        case mode1600 = 0
        case mode700C = 6
        case mode700D = 7
        case mode700E = 13

        var id: Int32 { rawValue }

        var label: String {
            switch self {
            case .mode1600: return "1600"
            case .mode700C: return "700C"
            case .mode700D: return "700D"
            case .mode700E: return "700E"
            }
        }

        var details: String {
            switch self {
            case .mode1600: return "1125 Hz BW · 4 dB SNR · Widest compatibility"
            case .mode700C: return "1500 Hz BW · 2 dB SNR · Fast sync"
            case .mode700D: return "1000 Hz BW · −2 dB SNR · Best low-SNR"
            case .mode700E: return "1500 Hz BW · 1 dB SNR · Best multipath"
            }
        }
    }

    // MARK: - Callbacks (set before open)

    /// Called on a background thread after each RX frame. Update UI on main.
    var onStatsUpdate: ((_ sync: Bool, _ snrDB: Float, _ ber: Float,
                         _ totalBits: Int, _ totalBitErrors: Int,
                         _ rxStatus: Int32) -> Void)?

    /// Called on main thread when a text channel character arrives.
    var onTextReceived: ((String) -> Void)?

    // MARK: - Properties (valid after open)

    private(set) var speechSampleRate: Int = 8000
    private(set) var modemSampleRate:  Int = 8000
    private(set) var nSpeechSamples:   Int = 0   // TX input frame size (speech samples)
    private(set) var nTxModemSamples:  Int = 0   // TX output frame size (modem samples)
    private(set) var nMaxModemSamples: Int = 0   // max RX input buffer
    private(set) var nMaxSpeechSamples: Int = 0  // max RX output buffer

    var isOpen: Bool { fdv != nil }

    // TX text channel — cycles through callsign + space
    var txCallsign: String = "AI5OS" { didSet { rebuildTxText() } }

    // MARK: - Private

    private var fdv: OpaquePointer?
    private let rxLock = NSLock()
    private var modemRxBuffer: [Int16] = []
    private var modemRxReadOffset = 0

    // TX text state (accessed only on codec2 TX thread — no lock needed)
    private var txTextChars: [CChar] = []
    private var txTextIdx:   Int = 0

    // Streaming-encode buffer (accessed only on the TX thread)
    private var txStreamBuf: [Int16] = []
    private var txStreamReadOffset = 0

    // Reused scratch buffers — avoid per-frame array allocations in the hot paths.
    private var txFrameScratch:     [Int16] = []  // one speech frame (TX), sized nSpeechSamples
    private var rxChunkScratch:     [Int16] = []  // one modem chunk (RX), sized nMaxModemSamples
    private var speechFrameScratch: [Int16] = []  // freedv_rx output, sized nMaxSpeechSamples

    // MARK: - Open / Close

    func open(mode: Mode) {
        close()
        guard let f = freedv_open(mode.rawValue) else {
            AppFileLogger.shared.log("FreeDVEngine: freedv_open(\(mode.label)) returned nil")
            return
        }
        fdv = f

        speechSampleRate   = Int(freedv_get_speech_sample_rate(f))
        modemSampleRate    = Int(freedv_get_modem_sample_rate(f))
        nSpeechSamples     = Int(freedv_get_n_speech_samples(f))
        nTxModemSamples    = Int(freedv_get_n_tx_modem_samples(f))
        nMaxModemSamples   = Int(freedv_get_n_max_modem_samples(f))
        nMaxSpeechSamples  = Int(freedv_get_n_max_speech_samples(f))

        modemRxBuffer.removeAll(keepingCapacity: true)
        modemRxReadOffset = 0
        modemRxBuffer.reserveCapacity(nMaxModemSamples * 4)
        txFrameScratch     = [Int16](repeating: 0, count: max(nSpeechSamples, 1))
        rxChunkScratch     = [Int16](repeating: 0, count: max(nMaxModemSamples, 1))
        speechFrameScratch = [Int16](repeating: 0, count: max(nMaxSpeechSamples, 1))

        rebuildTxText()
        installTextCallbacks(f)
        freedv_set_squelch_en(f, false)

        AppFileLogger.shared.log(
            "FreeDVEngine: opened \(mode.label) "
            + "speech=\(speechSampleRate) Hz modem=\(modemSampleRate) Hz "
            + "nSpeech=\(nSpeechSamples) nTxModem=\(nTxModemSamples)")
    }

    func close() {
        rxLock.lock()
        let f = fdv
        fdv = nil
        modemRxBuffer.removeAll()
        modemRxReadOffset = 0
        rxLock.unlock()

        guard let f else { return }
        freedv_close(f)
        txStreamBuf.removeAll()
        txStreamReadOffset = 0
        AppFileLogger.shared.log("FreeDVEngine: closed")
    }

    // MARK: - TX: 8 kHz Int16 speech → 8 kHz Int16 modem

    /// Streaming encode: feed arbitrary-length 8 kHz speech; returns modem Int16
    /// for every full `nSpeechSamples` frame buffered so far. Partial frames are
    /// retained for the next call. Mirrors `RADEEngine.encodeFromSpeech` so the
    /// audio pipelines can drive either engine through `FreeDVEncoding`.
    func encodeFromSpeech(_ speech: [Int16]) -> [Int16] {
        guard nSpeechSamples > 0 else { return [] }
        txStreamBuf.append(contentsOf: speech)
        var modem: [Int16] = []
        while txStreamBuf.count - txStreamReadOffset >= nSpeechSamples {
            for i in 0..<nSpeechSamples { txFrameScratch[i] = txStreamBuf[txStreamReadOffset + i] }
            txStreamReadOffset += nSpeechSamples
            modem.append(contentsOf: encodeSpeech(txFrameScratch))
        }
        compactTxStreamBufferIfNeeded()
        return modem
    }

    /// Clear the streaming-encode buffer at the start of an over.
    func resetTx() {
        txStreamBuf.removeAll(keepingCapacity: true)
        txStreamReadOffset = 0
    }

    /// Encode one speech frame. Input must be exactly `nSpeechSamples` Int16 samples.
    /// Returns `nTxModemSamples` Int16 modem samples, or empty on error.
    func encodeSpeech(_ speech: [Int16]) -> [Int16] {
        guard let f = fdv,
              speech.count == nSpeechSamples,
              nTxModemSamples > 0 else { return [] }
        var modemOut = [Int16](repeating: 0, count: nTxModemSamples)
        speech.withUnsafeBufferPointer { sPtr in
            modemOut.withUnsafeMutableBufferPointer { mPtr in
                freedv_tx(f, mPtr.baseAddress!, UnsafeMutablePointer(mutating: sPtr.baseAddress!))
            }
        }
        return modemOut
    }

    // MARK: - RX: 8 kHz Int16 modem → 8 kHz Int16 speech

    /// Append modem samples to internal buffer; returns decoded speech when a full frame is ready.
    /// May be called from any thread; returns empty array while buffering.
    func feedModemSamples(_ samples: [Int16]) -> [Int16] {
        rxLock.lock()
        defer { rxLock.unlock() }
        guard let f = fdv, nMaxSpeechSamples > 0 else { return [] }

        modemRxBuffer.append(contentsOf: samples)
        var speechAccum: [Int16] = []
        while true {
            let nin = Int(freedv_nin(f))
            guard nin > 0, modemRxBuffer.count - modemRxReadOffset >= nin else { break }
            for i in 0..<nin { rxChunkScratch[i] = modemRxBuffer[modemRxReadOffset + i] }
            modemRxReadOffset += nin

            let nout = rxChunkScratch.withUnsafeMutableBufferPointer { modemPtr in
                speechFrameScratch.withUnsafeMutableBufferPointer { speechPtr in
                    freedv_rx(f, speechPtr.baseAddress!, modemPtr.baseAddress!)
                }
            }
            if nout > 0 {
                speechAccum.append(contentsOf: speechFrameScratch.prefix(Int(nout)))
            }
            collectStats(f)
        }
        compactModemRxBufferIfNeeded()
        return speechAccum
    }

    private func compactTxStreamBufferIfNeeded() {
        guard txStreamReadOffset > 0 else { return }
        if txStreamReadOffset == txStreamBuf.count {
            txStreamBuf.removeAll(keepingCapacity: true)
            txStreamReadOffset = 0
        } else if txStreamReadOffset >= nSpeechSamples * 8 {
            txStreamBuf.removeFirst(txStreamReadOffset)
            txStreamReadOffset = 0
        }
    }

    private func compactModemRxBufferIfNeeded() {
        guard modemRxReadOffset > 0 else { return }
        if modemRxReadOffset == modemRxBuffer.count {
            modemRxBuffer.removeAll(keepingCapacity: true)
            modemRxReadOffset = 0
        } else if modemRxReadOffset >= max(nMaxModemSamples, 1) * 8 {
            modemRxBuffer.removeFirst(modemRxReadOffset)
            modemRxReadOffset = 0
        }
    }

    // MARK: - Stats

    private func collectStats(_ f: OpaquePointer) {
        var syncI: Int32 = 0
        var snr: Float = 0
        freedv_get_modem_stats(f, &syncI, &snr)
        let status = freedv_get_rx_status(f)
        let tb  = Int(freedv_get_total_bits(f))
        let tbe = Int(freedv_get_total_bit_errors(f))
        let ber: Float = tb > 200 ? Float(tbe) / Float(tb) : 0
        onStatsUpdate?(syncI != 0, snr, ber, tb, tbe, status)
    }

    // MARK: - Text channel callbacks

    private func installTextCallbacks(_ f: OpaquePointer) {
        // C-compatible closures must not capture Swift values — use callback_state (void*) as self.
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        let rxCb: freedv_callback_rx = { ctx, ch in
            guard let ctx, ch > 0 else { return }
            Unmanaged<FreeDVEngine>.fromOpaque(ctx).takeUnretainedValue().didReceiveChar(ch)
        }
        let txCb: freedv_callback_tx = { ctx -> CChar in
            guard let ctx else { return 0 }
            return Unmanaged<FreeDVEngine>.fromOpaque(ctx).takeUnretainedValue().nextTxChar()
        }
        freedv_set_callback_txt(f, rxCb, txCb, ctx)
    }

    private func rebuildTxText() {
        let s = txCallsign + " "
        txTextChars = s.utf8.map { CChar(bitPattern: $0) }
        txTextIdx = 0
    }

    // Called on codec2's internal TX thread — no lock (single-threaded from codec2 side)
    private func nextTxChar() -> CChar {
        guard !txTextChars.isEmpty else { return 0 }
        let ch = txTextChars[txTextIdx]
        txTextIdx = (txTextIdx + 1) % txTextChars.count
        return ch
    }

    // Called on codec2's internal RX thread
    private func didReceiveChar(_ ch: CChar) {
        let scalar = Unicode.Scalar(UInt8(bitPattern: ch))
        let s = String(scalar)
        DispatchQueue.main.async { [weak self] in
            self?.onTextReceived?(s)
        }
    }
}
