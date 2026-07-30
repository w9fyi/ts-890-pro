import Foundation

/// Receives 48 kHz mono float, frames to RNNoise-sized chunks, processes, and emits.
final class LanAudioPipeline {

    nonisolated deinit {}
    private let processor: any NoiseReductionProcessor
    private let frameSize: Int
    private var buffer: [Float] = []
    private var readOffset = 0
    private var frameScratch: [Float]
    private var dryScratch: [Float]

    var wetDry: Float = 1.0

    init(processor: any NoiseReductionProcessor, frameSize: Int = 480) {
        self.processor = processor
        self.frameSize = frameSize
        self.frameScratch = [Float](repeating: 0, count: frameSize)
        self.dryScratch = [Float](repeating: 0, count: frameSize)
        buffer.reserveCapacity(frameSize * 4)
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        readOffset = 0
    }

    func process48kMono(_ samples: [Float], onOutput: ([Float]) -> Void) {
        guard !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)

        while buffer.count - readOffset >= frameSize {
            frameScratch.withUnsafeMutableBufferPointer { frame in
                dryScratch.withUnsafeMutableBufferPointer { dry in
                    buffer.withUnsafeBufferPointer { src in
                        let base = src.baseAddress!.advanced(by: readOffset)
                        frame.baseAddress!.update(from: base, count: frameSize)
                        dry.baseAddress!.update(from: base, count: frameSize)
                    }
                }
            }
            readOffset += frameSize

            processor.processFrame48kMonoInPlace(&frameScratch)

            let mix = wetDry
            if mix < 1 {
                let inv = 1 - mix
                for i in 0..<frameSize {
                    frameScratch[i] = dryScratch[i] * inv + frameScratch[i] * mix
                }
            }
            onOutput(frameScratch)
        }

        compactConsumedPrefixIfNeeded()
    }

    private func compactConsumedPrefixIfNeeded() {
        guard readOffset > 0 else { return }
        if readOffset == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            readOffset = 0
        } else if readOffset >= frameSize * 8 {
            buffer.removeFirst(readOffset)
            readOffset = 0
        }
    }
}

