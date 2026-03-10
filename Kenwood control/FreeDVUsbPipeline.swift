import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation

/// FreeDV over USB AUDIO CODEC.
/// RX: USB AUDIO CODEC input (48 kHz) → FreeDV decode → Mac speaker (48 kHz)
/// TX: System mic (48 kHz) → FreeDV encode → USB AUDIO CODEC output (48 kHz)
final class FreeDVUsbPipeline {

    enum PipelineError: LocalizedError {
        case audioUnitError(OSStatus, String)
        case missingDevice

        var errorDescription: String? {
            switch self {
            case .audioUnitError(let s, let ctx): return "\(ctx) (OSStatus=\(s))"
            case .missingDevice: return "USB AUDIO CODEC device not found"
            }
        }
    }

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let fdvEngine: FreeDVEngine
    private let sampleRate: Double = 48_000

    // RX audio units
    private var usbInputUnit:     AudioUnit?
    private var speakerOutputUnit: AudioUnit?

    // TX audio units
    private var micInputUnit:    AudioUnit?
    private var usbOutputUnit:   AudioUnit?

    // Processing queues / ring buffers
    private let rxRaw  = AudioRingBuffer(capacitySamples: 48_000 * 2)
    private let rxOut  = AudioRingBuffer(capacitySamples: 48_000 * 2)
    private let txRaw  = AudioRingBuffer(capacitySamples: 48_000 * 2)
    private let txOut  = AudioRingBuffer(capacitySamples: 48_000 * 2)

    private let processQueue = DispatchQueue(label: "FreeDVUsbPipeline.process")
    private var processTimer: DispatchSourceTimer?
    private var inputScratch = [Float](repeating: 0, count: 8192)

    // Sample-rate conversion state
    private var rxLastSpeech:  Float?
    private var txLastModem:   Float?
    private var rxSpeech8kBuf: [Int16] = []
    private var txSpeech8kBuf: [Int16] = []

    private var isRunning = false

    // Context objects for AudioUnit render callbacks — kept alive for the callback's lifetime.
    private final class OutputCallbackCtx {
        unowned let owner: FreeDVUsbPipeline
        let isUsb: Bool
        init(_ owner: FreeDVUsbPipeline, isUsb: Bool) { self.owner = owner; self.isUsb = isUsb }
    }
    private var speakerOutCtx: OutputCallbackCtx?
    private var usbOutCtx:     OutputCallbackCtx?

    init(engine: FreeDVEngine) {
        self.fdvEngine = engine
    }

    // MARK: - Start / Stop

    func start(usbDeviceID: AudioDeviceID, speakerDeviceID: AudioDeviceID) throws {
        stop()
        guard fdvEngine.isOpen else {
            onError?("FreeDVUsbPipeline: FreeDV engine not open")
            return
        }

        rxRaw.clear(); rxOut.clear(); txRaw.clear(); txOut.clear()
        rxSpeech8kBuf.removeAll(); txSpeech8kBuf.removeAll()
        rxLastSpeech = nil; txLastModem = nil

        usbInputUnit     = try makeInputUnit(deviceID: usbDeviceID, label: "USB in")
        speakerOutputUnit = try makeOutputUnit(deviceID: speakerDeviceID, label: "Speaker out")
        micInputUnit     = try makeInputUnit(deviceID: AudioDeviceID(kAudioObjectSystemObject) /* default mic */, label: "Mic in",
                                             useDefault: true)
        usbOutputUnit    = try makeOutputUnit(deviceID: usbDeviceID, label: "USB out")

        for unit in [usbInputUnit, speakerOutputUnit, micInputUnit, usbOutputUnit].compactMap({ $0 }) {
            var s = AudioUnitInitialize(unit); guard s == noErr else { throw PipelineError.audioUnitError(s, "Initialize"); }
            s = AudioOutputUnitStart(unit); guard s == noErr else { throw PipelineError.audioUnitError(s, "Start"); }
        }

        startProcessingLoop()
        isRunning = true
        onLog?("FreeDVUsbPipeline: started (USB device \(usbDeviceID))")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        processTimer?.cancel(); processTimer = nil
        for u in [usbInputUnit, speakerOutputUnit, micInputUnit, usbOutputUnit] {
            stopAndDispose(u)
        }
        usbInputUnit = nil; speakerOutputUnit = nil
        micInputUnit = nil; usbOutputUnit    = nil
        speakerOutCtx = nil; usbOutCtx = nil
        onLog?("FreeDVUsbPipeline: stopped")
    }

    // MARK: - AudioUnit construction

    private func makeInputUnit(deviceID: AudioDeviceID, label: String,
                               useDefault: Bool = false) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw PipelineError.audioUnitError(-1, "AudioComponentFindNext (\(label))")
        }
        var unit: AudioUnit?
        var s = AudioComponentInstanceNew(comp, &unit)
        guard s == noErr, let unit else { throw PipelineError.audioUnitError(s, "New (\(label))") }

        var one: UInt32 = 1, zero: UInt32 = 0
        s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Input, 1, &one,
                                 UInt32(MemoryLayout<UInt32>.size)); guard s == noErr else { throw PipelineError.audioUnitError(s, "EnableIO input (\(label))") }
        s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Output, 0, &zero,
                                 UInt32(MemoryLayout<UInt32>.size)); guard s == noErr else { throw PipelineError.audioUnitError(s, "DisableIO output (\(label))") }

        if !useDefault {
            var dev = deviceID
            s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                     kAudioUnitScope_Global, 0, &dev,
                                     UInt32(MemoryLayout<AudioDeviceID>.size))
            guard s == noErr else { throw PipelineError.audioUnitError(s, "SetDevice (\(label))") }
        }

        var fmt = makeASBD()
        s = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 1, &fmt,
                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard s == noErr else { throw PipelineError.audioUnitError(s, "StreamFormat (\(label))") }

        // Determine which ring buffer this input feeds.
        let isUsb = !useDefault
        var cb = AURenderCallbackStruct(
            inputProc: { refCon, flags, ts, bus, nFrames, _ in
                let p = Unmanaged<FreeDVUsbPipeline>.fromOpaque(refCon).takeUnretainedValue()
                return p.handleInput(isUsb: bus == 0, flags: flags, ts: ts, bus: bus, nFrames: nFrames)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        // Tag the unit: bus 0 = USB input, bus 1 = mic input (we distinguish via separate units).
        // We route USB input to rxRaw, mic input to txRaw.
        let cbProp: AudioUnitPropertyID = isUsb
            ? kAudioOutputUnitProperty_SetInputCallback
            : kAudioOutputUnitProperty_SetInputCallback
        s = AudioUnitSetProperty(unit, cbProp, kAudioUnitScope_Global, 0, &cb,
                                 UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard s == noErr else { throw PipelineError.audioUnitError(s, "InputCallback (\(label))") }

        return unit
    }

    private func makeOutputUnit(deviceID: AudioDeviceID, label: String) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw PipelineError.audioUnitError(-1, "AudioComponentFindNext (\(label))")
        }
        var unit: AudioUnit?
        var s = AudioComponentInstanceNew(comp, &unit)
        guard s == noErr, let unit else { throw PipelineError.audioUnitError(s, "New (\(label))") }

        var one: UInt32 = 1, zero: UInt32 = 0
        s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Output, 0, &one,
                                 UInt32(MemoryLayout<UInt32>.size)); guard s == noErr else { throw PipelineError.audioUnitError(s, "EnableIO output (\(label))") }
        s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Input, 1, &zero,
                                 UInt32(MemoryLayout<UInt32>.size)); guard s == noErr else { throw PipelineError.audioUnitError(s, "DisableIO input (\(label))") }

        var dev = deviceID
        s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        guard s == noErr else { throw PipelineError.audioUnitError(s, "SetDevice (\(label))") }

        var fmt = makeASBD()
        s = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Input, 0, &fmt,
                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard s == noErr else { throw PipelineError.audioUnitError(s, "StreamFormat (\(label))") }

        // Use a context object so the C callback doesn't capture any Swift context.
        let ctx = OutputCallbackCtx(self, isUsb: label == "USB out")
        if label == "USB out" { usbOutCtx = ctx } else { speakerOutCtx = ctx }
        var cb = AURenderCallbackStruct(
            inputProc: { refCon, _, _, _, nFrames, ioData in
                let c = Unmanaged<OutputCallbackCtx>.fromOpaque(refCon).takeUnretainedValue()
                return c.owner.handleOutput(isUsb: c.isUsb, nFrames: nFrames, ioData: ioData)
            },
            inputProcRefCon: Unmanaged.passUnretained(ctx).toOpaque()
        )
        s = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                 kAudioUnitScope_Input, 0, &cb,
                                 UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard s == noErr else { throw PipelineError.audioUnitError(s, "RenderCallback (\(label))") }

        return unit
    }

    private func makeASBD() -> AudioStreamBasicDescription {
        let bps = UInt32(MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: bps, mFramesPerPacket: 1,
            mBytesPerFrame: bps, mChannelsPerFrame: 1,
            mBitsPerChannel: 8 * bps, mReserved: 0)
    }

    private func stopAndDispose(_ unit: AudioUnit?) {
        guard let u = unit else { return }
        AudioOutputUnitStop(u); AudioUnitUninitialize(u); AudioComponentInstanceDispose(u)
    }

    // MARK: - AudioUnit callbacks

    private func handleInput(isUsb: Bool, flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
                             ts: UnsafePointer<AudioTimeStamp>?, bus: UInt32,
                             nFrames: UInt32) -> OSStatus {
        let unit = isUsb ? usbInputUnit : micInputUnit
        guard let unit else { return noErr }
        let frames = Int(nFrames)
        guard frames > 0, frames <= inputScratch.count else { return noErr }

        return inputScratch.withUnsafeMutableBufferPointer { scratch in
            var abl = AudioBufferList(mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1,
                                      mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                                      mData: scratch.baseAddress))
            var tsCopy = ts?.pointee ?? AudioTimeStamp()
            var flagsCopy: AudioUnitRenderActionFlags = []
            let s = withUnsafePointer(to: &tsCopy) { tsPtr in
                AudioUnitRender(unit, &flagsCopy, tsPtr, 1, nFrames, &abl)
            }
            guard s == noErr else { return s }
            _ = (isUsb ? rxRaw : txRaw).write(from: scratch.baseAddress!, count: frames)
            return noErr
        }
    }

    private func handleOutput(isUsb: Bool, nFrames: UInt32,
                              ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData else { return noErr }
        let frames = Int(nFrames)
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        guard let first = buffers.first,
              let ptr = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let fifo = isUsb ? txOut : rxOut
        let got = fifo.read(into: ptr, count: frames)
        if got < frames { ptr.advanced(by: got).initialize(repeating: 0, count: frames - got) }
        return noErr
    }

    // MARK: - Processing loop

    private func startProcessingLoop() {
        let timer = DispatchSource.makeTimerSource(queue: processQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.drainAndProcess() }
        processTimer = timer
        timer.resume()
    }

    private func drainAndProcess() {
        guard isRunning else { return }
        processRx()
        processTx()
    }

    // USB input → FreeDV decode → speaker output
    private func processRx() {
        let chunkSize = 480 // 10 ms at 48 kHz
        while rxRaw.availableToRead() >= chunkSize {
            var frame = [Float](repeating: 0, count: chunkSize)
            let got = frame.withUnsafeMutableBufferPointer { rxRaw.read(into: $0.baseAddress!, count: chunkSize) }
            guard got == chunkSize else { break }

            // Decimate 48→8 kHz (factor 6): take every 6th sample.
            var decimated = [Int16]()
            decimated.reserveCapacity(chunkSize / 6)
            var i = 0
            while i < chunkSize {
                decimated.append(Int16(clamping: Int32(frame[i] * 32767.0)))
                i += 6
            }
            rxSpeech8kBuf.append(contentsOf: decimated)
        }

        // Feed accumulated 8 kHz modem samples to FreeDV.
        if !rxSpeech8kBuf.isEmpty {
            let speech = fdvEngine.feedModemSamples(rxSpeech8kBuf)
            rxSpeech8kBuf.removeAll(keepingCapacity: true)
            if !speech.isEmpty {
                // Upsample decoded speech 8→48 kHz (factor 6, linear interpolation).
                let fSpeech = speech.map { Float($0) / 32768.0 }
                var out = [Float](); out.reserveCapacity(fSpeech.count * 6)
                for i in 0 ..< max(0, fSpeech.count - 1) {
                    let a = fSpeech[i], b = fSpeech[i + 1], d = b - a
                    for k in 0..<6 { out.append(a + d * Float(k) / 6.0) }
                }
                rxLastSpeech = fSpeech.last
                _ = out.withUnsafeBufferPointer { rxOut.write(from: $0.baseAddress!, count: out.count) }
            }
        }
    }

    // Mic input → FreeDV encode → USB output
    private func processTx() {
        guard fdvEngine.nSpeechSamples > 0 else { return }
        let chunkSize = 480
        while txRaw.availableToRead() >= chunkSize {
            var frame = [Float](repeating: 0, count: chunkSize)
            let got = frame.withUnsafeMutableBufferPointer { txRaw.read(into: $0.baseAddress!, count: chunkSize) }
            guard got == chunkSize else { break }

            // Decimate 48→8 kHz.
            var i = 0
            while i < chunkSize {
                txSpeech8kBuf.append(Int16(clamping: Int32(frame[i] * 32767.0)))
                i += 6
            }
        }

        while txSpeech8kBuf.count >= fdvEngine.nSpeechSamples {
            let frame = Array(txSpeech8kBuf.prefix(fdvEngine.nSpeechSamples))
            txSpeech8kBuf.removeFirst(fdvEngine.nSpeechSamples)
            let modem8k = fdvEngine.encodeSpeech(frame)
            guard !modem8k.isEmpty else { continue }

            // Upsample modem 8→48 kHz.
            let fModem = modem8k.map { Float($0) / 32768.0 }
            var out = [Float](); out.reserveCapacity(fModem.count * 6)
            for i in 0 ..< max(0, fModem.count - 1) {
                let a = fModem[i], b = fModem[i + 1], d = b - a
                for k in 0..<6 { out.append(a + d * Float(k) / 6.0) }
            }
            txLastModem = fModem.last
            _ = out.withUnsafeBufferPointer { txOut.write(from: $0.baseAddress!, count: out.count) }
        }
    }
}
