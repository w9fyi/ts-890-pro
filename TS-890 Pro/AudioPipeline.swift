import Foundation

final class AudioFrameBuffer {

    nonisolated deinit {}
    private var buffer: [Float] = []
    private let frameSize: Int
    private var readOffset = 0
    // Reused frame scratch — avoids a heap allocation on every frame boundary.
    // `onFrame` is non-escaping and consumes the frame synchronously, so a single
    // shared buffer is safe.
    private var frameScratch: [Float]

    init(frameSize: Int) {
        self.frameSize = frameSize
        self.frameScratch = [Float](repeating: 0, count: frameSize)
        buffer.reserveCapacity(frameSize * 2)
    }

    func append(_ samples: [Float], onFrame: ([Float]) -> Void) {
        guard !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)

        while buffer.count - readOffset >= frameSize {
            frameScratch.withUnsafeMutableBufferPointer { dst in
                buffer.withUnsafeBufferPointer { src in
                    dst.baseAddress!.update(from: src.baseAddress!.advanced(by: readOffset), count: frameSize)
                }
            }
            readOffset += frameSize
            onFrame(frameScratch)
        }

        compactConsumedPrefixIfNeeded()
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        readOffset = 0
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

final class NoiseReductionPipeline {
    private let processor: any NoiseReductionProcessor
    private let frameBuffer: AudioFrameBuffer

    init(processor: any NoiseReductionProcessor, frameSize: Int) {
        self.processor = processor
        self.frameBuffer = AudioFrameBuffer(frameSize: frameSize)
    }

    /// Accepts 48 kHz mono float samples and returns denoised output frames.
    func process(samples: [Float], onOutput: ([Float]) -> Void) {
        frameBuffer.append(samples) { [processor] frame in
            let processed = processor.processFrame48kMono(frame)
            onOutput(processed)
        }
    }

    func reset() { frameBuffer.reset() }
}
