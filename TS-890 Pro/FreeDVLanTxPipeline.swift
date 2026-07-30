import Foundation
import AVFoundation

/// Captures mic audio, encodes via a `FreeDVEncoding` engine (codec2 or the
/// neural RADE engine), and sends the resulting modem tones to the radio over
/// the KNS LAN audio socket. start()/stop() bracket one over (PTT down/up).
final class FreeDVLanTxPipeline {
    nonisolated deinit {}   // prevent Swift 6.1 isolated-deinit crash (AVAudioEngine holds os_unfair_lock)

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let encoder:  FreeDVEncoding
    private let receiver: KenwoodLanAudioReceiver   // uses its sendMicFramePCM16

    private let avEngine   = AVAudioEngine()
    private var convToSpeech: AVAudioConverter?
    /// Encoder speech input format: 8 kHz for codec2, 16 kHz for RADE.
    private let speechFormat: AVAudioFormat

    // Buffers
    private var modem16kBuf:  [Int16] = []  // upsampled modem output waiting to be sent
    private var modem16kReadOffset = 0
    private var lastModemSample: Float?
    /// Reused converter output buffer — avoids an AVAudioPCMBuffer allocation per
    /// 20 ms mic tap. Created in start() once the speech format is known.
    private var convOutBuffer: AVAudioPCMBuffer?
    /// Reused 320-sample KNS packet scratch.
    private var sendScratch = [Int16](repeating: 0, count: 320)

    private var isRunning = false

    init(encoder: FreeDVEncoding, receiver: KenwoodLanAudioReceiver) {
        self.encoder  = encoder
        self.receiver = receiver
        self.speechFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: Double(encoder.txSpeechSampleRate),
                                          channels: 1, interleaved: true)!
    }

    func start() {
        stop()
        guard encoder.isOpen else {
            onError?("FreeDVLanTxPipeline: engine not open")
            return
        }

        let input       = avEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let conv  = AVAudioConverter(from: inputFormat, to: speechFormat) else {
            onError?("FreeDVLanTxPipeline: AVAudioConverter init failed")
            return
        }
        convToSpeech = conv
        convOutBuffer = AVAudioPCMBuffer(
            pcmFormat: speechFormat,
            frameCapacity: AVAudioFrameCount(speechFormat.sampleRate * 0.1 + 16))

        // 20 ms tap at native rate.
        let tapFrames = AVAudioFrameCount(max(1, Int((inputFormat.sampleRate * 0.02).rounded())))
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { [weak self] buf, _ in
            self?.handleMicTap(buf)
        }

        modem16kBuf.removeAll(keepingCapacity: true)
        modem16kReadOffset = 0
        lastModemSample = nil
        encoder.resetTx()

        avEngine.prepare()
        do {
            try avEngine.start()
            isRunning = true
            onLog?("FreeDVLanTxPipeline: started (mic \(Int(inputFormat.sampleRate)) Hz → \(encoder.txSpeechSampleRate) Hz → encode → 16 kHz KNS)")
        } catch {
            onError?("FreeDVLanTxPipeline: AVAudioEngine start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        avEngine.inputNode.removeTap(onBus: 0)

        // Emit the encoder's end-of-over frame (RADE EOO/callsign) while the
        // radio is still keyed, then flush any partial KNS packet (zero-padded).
        let eoo = encoder.finishOver()
        if !eoo.isEmpty { appendModem8k(eoo) }
        flushModem(padPartial: true)

        avEngine.stop()
        convToSpeech = nil
        convOutBuffer = nil
        modem16kBuf.removeAll()
        modem16kReadOffset = 0
        lastModemSample = nil
        onLog?("FreeDVLanTxPipeline: stopped")
    }

    // MARK: - Mic tap

    private func handleMicTap(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, let conv = convToSpeech, let out = convOutBuffer else { return }
        // Reset the reused output buffer before each conversion.
        out.frameLength = 0

        var hadInput = false
        let status = conv.convert(to: out, error: nil) { _, outStatus in
            if hadInput { outStatus.pointee = .noDataNow; return nil }
            hadInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let ch = out.int16ChannelData, out.frameLength > 0 else { return }

        let count = Int(out.frameLength)
        let speech = Array(UnsafeBufferPointer(start: ch[0], count: count))

        // Encode (engine buffers partial frames internally) → real 8 kHz modem.
        appendModem8k(encoder.encodeFromSpeech(speech))
        flushModem(padPartial: false)
    }

    /// Upsample real 8 kHz modem Int16 → 16 kHz (×2, linear interp) into the
    /// outgoing KNS buffer.
    private func appendModem8k(_ modem8k: [Int16]) {
        guard !modem8k.isEmpty else { return }
        // Upsample ×2 (linear interp) straight into modem16kBuf — no intermediate
        // float / up16k arrays. A doublet is emitted for each adjacent pair, so the
        // batch's final sample is carried over as `lastModemSample` for next time.
        modem16kBuf.reserveCapacity(modem16kBuf.count + modem8k.count * 2)
        var prev = lastModemSample
        for s in modem8k {
            let cur = Float(s) / 32768.0
            if let p = prev { appendDoublet(from: p, to: cur, into: &modem16kBuf) }
            prev = cur
        }
        lastModemSample = prev
    }

    /// Send buffered modem output in 320-sample KNS packets. When `padPartial`
    /// is set (end of over), zero-pad and send the final short packet too.
    private func flushModem(padPartial: Bool) {
        while modem16kBuf.count - modem16kReadOffset >= 320 {
            for i in 0..<320 { sendScratch[i] = modem16kBuf[modem16kReadOffset + i] }
            modem16kReadOffset += 320
            sendScratch.withUnsafeBufferPointer { ptr in
                receiver.sendMicFramePCM16(ptr.baseAddress!, count: 320)
            }
        }
        if padPartial, modem16kBuf.count > modem16kReadOffset {
            let n = modem16kBuf.count - modem16kReadOffset
            for i in 0..<n   { sendScratch[i] = modem16kBuf[modem16kReadOffset + i] }
            for i in n..<320 { sendScratch[i] = 0 }
            modem16kBuf.removeAll(keepingCapacity: true)
            modem16kReadOffset = 0
            sendScratch.withUnsafeBufferPointer { ptr in
                receiver.sendMicFramePCM16(ptr.baseAddress!, count: 320)
            }
        } else {
            compactModemBufferIfNeeded()
        }
    }

    private func compactModemBufferIfNeeded() {
        guard modem16kReadOffset > 0 else { return }
        if modem16kReadOffset == modem16kBuf.count {
            modem16kBuf.removeAll(keepingCapacity: true)
            modem16kReadOffset = 0
        } else if modem16kReadOffset >= 320 * 8 {
            modem16kBuf.removeFirst(modem16kReadOffset)
            modem16kReadOffset = 0
        }
    }

    // Linear interpolation: 2 output samples between a (inclusive) and b (exclusive).
    private func appendDoublet(from a: Float, to b: Float, into out: inout [Int16]) {
        let d = b - a
        out.append(Int16(clamping: Int32((a) * 32767.0)))
        out.append(Int16(clamping: Int32((a + d * 0.5) * 32767.0)))
    }
}
