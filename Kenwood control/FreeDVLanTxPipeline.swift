import Foundation
import AVFoundation

/// Captures mic audio, encodes via FreeDVEngine, and sends modem tones
/// to the radio over the KNS LAN audio socket.
final class FreeDVLanTxPipeline {
    nonisolated deinit {}   // prevent Swift 6.1 isolated-deinit crash (AVAudioEngine holds os_unfair_lock)

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let engine:   FreeDVEngine
    private let receiver: KenwoodLanAudioReceiver   // uses its sendMicFramePCM16

    private let avEngine   = AVAudioEngine()
    private var converter8k: AVAudioConverter?
    private let format8k   = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                           sampleRate: 8_000, channels: 1, interleaved: true)!

    // Buffers
    private var speech8kBuf:  [Int16] = []  // pending mic samples at 8 kHz
    private var modem16kBuf:  [Int16] = []  // upsampled modem output waiting to be sent
    private var lastModemSample: Float?

    private var isRunning = false

    init(engine: FreeDVEngine, receiver: KenwoodLanAudioReceiver) {
        self.engine   = engine
        self.receiver = receiver
    }

    func start() {
        stop()
        guard engine.isOpen, engine.nSpeechSamples > 0 else {
            onError?("FreeDVLanTxPipeline: engine not open")
            return
        }

        let input       = avEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let conv  = AVAudioConverter(from: inputFormat, to: format8k) else {
            onError?("FreeDVLanTxPipeline: AVAudioConverter init failed")
            return
        }
        converter8k = conv

        // 20 ms tap at native rate.
        let tapFrames = AVAudioFrameCount(max(1, Int((inputFormat.sampleRate * 0.02).rounded())))
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { [weak self] buf, _ in
            self?.handleMicTap(buf)
        }

        speech8kBuf.removeAll(keepingCapacity: true)
        modem16kBuf.removeAll(keepingCapacity: true)
        lastModemSample = nil

        avEngine.prepare()
        do {
            try avEngine.start()
            isRunning = true
            onLog?("FreeDVLanTxPipeline: started (mic \(Int(inputFormat.sampleRate)) Hz → 8 kHz → FreeDV → 16 kHz KNS)")
        } catch {
            onError?("FreeDVLanTxPipeline: AVAudioEngine start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        avEngine.inputNode.removeTap(onBus: 0)
        avEngine.stop()
        converter8k = nil
        isRunning = false
        speech8kBuf.removeAll()
        modem16kBuf.removeAll()
        lastModemSample = nil
        onLog?("FreeDVLanTxPipeline: stopped")
    }

    // MARK: - Mic tap

    private func handleMicTap(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, let conv = converter8k else { return }

        // Convert mic audio to 8 kHz Int16.
        let frameCapacity = AVAudioFrameCount(engine.nSpeechSamples * 2 + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: format8k, frameCapacity: frameCapacity) else { return }

        var hadInput = false
        let status = conv.convert(to: out, error: nil) { _, outStatus in
            if hadInput { outStatus.pointee = .noDataNow; return nil }
            hadInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let ch = out.int16ChannelData, out.frameLength > 0 else { return }

        let count = Int(out.frameLength)
        speech8kBuf.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))

        // Encode in nSpeechSamples-sized frames.
        while speech8kBuf.count >= engine.nSpeechSamples {
            let frame = Array(speech8kBuf.prefix(engine.nSpeechSamples))
            speech8kBuf.removeFirst(engine.nSpeechSamples)
            let modem8k = engine.encodeSpeech(frame)
            guard !modem8k.isEmpty else { continue }

            // Upsample 8→16 kHz (×2, linear interpolation).
            let modemFloat = modem8k.map { Float($0) / 32768.0 }
            var up16k = [Int16]()
            up16k.reserveCapacity(modemFloat.count * 2)

            if let prev = lastModemSample, let first = modemFloat.first {
                appendDoublet(from: prev, to: first, into: &up16k)
            }
            for i in 0 ..< (modemFloat.count - 1) {
                appendDoublet(from: modemFloat[i], to: modemFloat[i + 1], into: &up16k)
            }
            lastModemSample = modemFloat.last

            modem16kBuf.append(contentsOf: up16k)
        }

        // Send buffered modem output in 320-sample KNS packets.
        while modem16kBuf.count >= 320 {
            let chunk = Array(modem16kBuf.prefix(320))
            modem16kBuf.removeFirst(320)
            chunk.withUnsafeBufferPointer { ptr in
                receiver.sendMicFramePCM16(ptr.baseAddress!, count: 320)
            }
        }
    }

    // Linear interpolation: 2 output samples between a (inclusive) and b (exclusive).
    private func appendDoublet(from a: Float, to b: Float, into out: inout [Int16]) {
        let d = b - a
        out.append(Int16(clamping: Int32((a) * 32767.0)))
        out.append(Int16(clamping: Int32((a + d * 0.5) * 32767.0)))
    }
}
