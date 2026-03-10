import Foundation
import AudioToolbox
import CoreAudio

/// Routes audio from a Mac input device (e.g. a USB microphone) to a CoreAudio
/// output device (e.g. the TS-890S USB Codec) for use as radio TX audio.
///
/// This is the transmit complement of AudioMonitor, which goes in the reverse
/// direction (radio USB Codec → NR processing → Mac speakers).
///
/// Usage:
///   1. Resolve CoreAudio device IDs for the chosen mic and the radio USB Codec.
///   2. Call start(inputDeviceID:outputDeviceID:).
///   3. Send MS002; via CAT to route USB audio to the radio TX chain.
///   4. Call stop() when done; send MS001; to restore the front-panel mic.
final class AudioPassthrough {

    enum PassthroughError: LocalizedError {
        case unsupportedSampleRate(Double)
        case audioUnitError(OSStatus, String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSampleRate(let sr):
                return "Unsupported sample rate \(sr) Hz — radio USB Codec expects 48000 Hz."
            case .audioUnitError(let status, let context):
                return "\(context) (OSStatus=\(status))"
            }
        }
    }

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?

    /// Linear gain applied to the microphone input before sending to the radio.
    /// 1.0 = unity gain.  Adjust to match desired TX mic level.
    var inputGain: Float = 1.0

    private let sampleRate: Double = 48_000
    private let channels:   UInt32 = 1

    private var inputUnit:  AudioUnit?
    private var outputUnit: AudioUnit?

    private var inputScratch: [Float] = Array(repeating: 0, count: 4096)
    private let fifo = AudioRingBuffer(capacitySamples: 48_000 * 2)

    private var isRunning = false

    // MARK: - Start / Stop

    func start(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID) throws {
        stop()

        // Verify the output device (TS-890S USB Codec) is at 48 kHz.
        let outputSR = nominalSampleRate(of: outputDeviceID)
        if let sr = outputSR, abs(sr - sampleRate) > 1 {
            throw PassthroughError.unsupportedSampleRate(sr)
        }

        fifo.clear()
        inputUnit  = try makeInputUnit(deviceID: inputDeviceID)
        outputUnit = try makeOutputUnit(deviceID: outputDeviceID)
        try initializeAndStartUnits()

        isRunning = true
        onLog?("TX passthrough started — 48 kHz mono, gain=\(inputGain)")
    }

    func stop() {
        isRunning = false
        stopAndDispose(&inputUnit)
        stopAndDispose(&outputUnit)
        fifo.clear()
        onLog?("TX passthrough stopped")
    }

    // MARK: - AudioUnit construction (mirrors AudioMonitor pattern)

    private func makeInputUnit(deviceID: AudioDeviceID) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType:         kAudioUnitType_Output,
            componentSubType:      kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw PassthroughError.audioUnitError(-1, "AudioComponentFindNext failed (mic input)")
        }
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(comp, &unit)
        guard status == noErr, let unit else {
            throw PassthroughError.audioUnitError(status, "AudioComponentInstanceNew failed (mic input)")
        }

        // Enable input on bus 1, disable output on bus 0.
        var one:  UInt32 = 1
        var zero: UInt32 = 0
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,  1, &one,  4)
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "EnableIO input") }
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output, 0, &zero, 4)
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Disable output (input unit)") }

        var dev = deviceID
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                      kAudioUnitScope_Global, 0, &dev,
                                      UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set mic device") }

        var asbd = makeASBD()
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, 1, &asbd,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set mic stream format") }

        var cb = AURenderCallbackStruct(
            inputProc: { refCon, flags, ts, bus, frames, data in
                Unmanaged<AudioPassthrough>.fromOpaque(refCon).takeUnretainedValue()
                    .handleInput(flags: flags, ts: ts, bus: bus, frames: frames, data: data)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global, 0, &cb,
                                      UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set mic input callback") }

        return unit
    }

    private func makeOutputUnit(deviceID: AudioDeviceID) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType:         kAudioUnitType_Output,
            componentSubType:      kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw PassthroughError.audioUnitError(-1, "AudioComponentFindNext failed (USB Codec output)")
        }
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(comp, &unit)
        guard status == noErr, let unit else {
            throw PassthroughError.audioUnitError(status, "AudioComponentInstanceNew failed (USB Codec output)")
        }

        // Enable output on bus 0, disable input on bus 1.
        var one:  UInt32 = 1
        var zero: UInt32 = 0
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output, 0, &one,  4)
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "EnableIO output") }
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,  1, &zero, 4)
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Disable input (output unit)") }

        var dev = deviceID
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                      kAudioUnitScope_Global, 0, &dev,
                                      UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set USB Codec output device") }

        var asbd = makeASBD()
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, 0, &asbd,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set USB Codec output stream format") }

        var cb = AURenderCallbackStruct(
            inputProc: { refCon, flags, ts, bus, frames, data in
                Unmanaged<AudioPassthrough>.fromOpaque(refCon).takeUnretainedValue()
                    .handleOutput(flags: flags, ts: ts, bus: bus, frames: frames, data: data)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, 0, &cb,
                                      UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw PassthroughError.audioUnitError(status, "Set USB Codec render callback") }

        return unit
    }

    private func initializeAndStartUnits() throws {
        if let u = inputUnit {
            var s = AudioUnitInitialize(u)
            guard s == noErr else { throw PassthroughError.audioUnitError(s, "AudioUnitInitialize (mic)") }
            s = AudioOutputUnitStart(u)
            guard s == noErr else { throw PassthroughError.audioUnitError(s, "AudioOutputUnitStart (mic)") }
        }
        if let u = outputUnit {
            var s = AudioUnitInitialize(u)
            guard s == noErr else { throw PassthroughError.audioUnitError(s, "AudioUnitInitialize (USB Codec)") }
            s = AudioOutputUnitStart(u)
            guard s == noErr else { throw PassthroughError.audioUnitError(s, "AudioOutputUnitStart (USB Codec)") }
        }
    }

    private func stopAndDispose(_ unit: inout AudioUnit?) {
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
        unit = nil
    }

    private func makeASBD() -> AudioStreamBasicDescription {
        let bps = UInt32(MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate:       sampleRate,
            mFormatID:         kAudioFormatLinearPCM,
            mFormatFlags:      kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket:   bps * channels,
            mFramesPerPacket:  1,
            mBytesPerFrame:    bps * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel:   8 * bps,
            mReserved: 0
        )
    }

    // MARK: - CoreAudio render callbacks

    private func handleInput(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        ts: UnsafePointer<AudioTimeStamp>?,
        bus: UInt32,
        frames: UInt32,
        data: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let inputUnit else { return noErr }
        let n = Int(frames)
        guard n > 0, n <= inputScratch.count else { return noErr }

        return inputScratch.withUnsafeMutableBufferPointer { scratch in
            var abl = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize:   UInt32(n * MemoryLayout<Float>.size),
                    mData:           scratch.baseAddress
                )
            )
            var renderFlags: AudioUnitRenderActionFlags = []
            var timestamp = ts?.pointee ?? AudioTimeStamp()
            let status = withUnsafePointer(to: &timestamp) { tsPtr in
                AudioUnitRender(inputUnit, &renderFlags, tsPtr, 1, frames, &abl)
            }
            guard status == noErr else { return status }

            if inputGain != 1 {
                for i in 0..<n { scratch[i] *= inputGain }
            }
            _ = fifo.write(from: scratch.baseAddress!, count: n)
            return noErr
        }
    }

    private func handleOutput(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        ts: UnsafePointer<AudioTimeStamp>?,
        bus: UInt32,
        frames: UInt32,
        data: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let data else { return noErr }
        let n = Int(frames)
        guard n > 0 else { return noErr }

        let buffers = UnsafeMutableAudioBufferListPointer(data)
        guard let first = buffers.first,
              first.mNumberChannels == channels,
              let outPtr = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        let got = fifo.read(into: outPtr, count: n)
        if got < n {
            outPtr.advanced(by: got).initialize(repeating: 0, count: n - got)
        }
        return noErr
    }

    // MARK: - Helpers

    private func nominalSampleRate(of deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var value: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
