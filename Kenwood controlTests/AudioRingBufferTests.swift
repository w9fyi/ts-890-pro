import XCTest
@testable import Kenwood_control

final class AudioRingBufferTests: XCTestCase {

    // MARK: - Helpers

    /// Write an array of floats into the ring buffer.
    @discardableResult
    private func write(_ samples: [Float], into buf: AudioRingBuffer) -> Int {
        samples.withUnsafeBufferPointer { ptr in
            buf.write(from: ptr.baseAddress!, count: samples.count)
        }
    }

    /// Read count samples from the ring buffer into a new array.
    private func read(_ count: Int, from buf: AudioRingBuffer) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBufferPointer { ptr in
            _ = buf.read(into: ptr.baseAddress!, count: count)
        }
        return out
    }

    // MARK: - Basic write / read

    func testWriteThenRead_returnsCorrectSamples() {
        let buf = AudioRingBuffer(capacitySamples: 16)
        write([1, 2, 3, 4], into: buf)
        let result = read(4, from: buf)
        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    func testAvailableToRead_tracksWrittenCount() {
        let buf = AudioRingBuffer(capacitySamples: 16)
        XCTAssertEqual(buf.availableToRead(), 0)
        write([0.1, 0.2, 0.3], into: buf)
        XCTAssertEqual(buf.availableToRead(), 3)
    }

    func testAvailableToRead_decreasesAfterRead() {
        let buf = AudioRingBuffer(capacitySamples: 16)
        write([1, 2, 3, 4, 5], into: buf)
        _ = read(3, from: buf)
        XCTAssertEqual(buf.availableToRead(), 2)
    }

    // MARK: - Wrap-around

    func testWrapAround_readsCorrectlyCrossingEndOfStorage() {
        // Fill the buffer, consume 3, write 3 more so the write index wraps.
        let buf = AudioRingBuffer(capacitySamples: 8)
        write([1, 2, 3, 4, 5, 6, 7, 8], into: buf)
        _ = read(3, from: buf)                        // consumes 1, 2, 3; read index = 3
        write([10, 11, 12], into: buf)               // wraps: writes at indices 8%8=0,1,2
        let tail = read(5, from: buf)                 // should read 4,5,6,7,8 from old tail...
        let wrapped = read(3, from: buf)              // ...then 10,11,12 from wrapped section
        XCTAssertEqual(tail, [4, 5, 6, 7, 8])
        XCTAssertEqual(wrapped, [10, 11, 12])
    }

    func testWrapAround_readSpanningBoundary() {
        // Write 6 samples, consume 5 (read index=5), write 4 more — new data straddles end/start.
        let buf = AudioRingBuffer(capacitySamples: 8)
        write([0, 0, 0, 0, 0, 9, 8, 7], into: buf)
        _ = read(5, from: buf)                        // read index = 5; available = 3
        write([1, 2, 3, 4], into: buf)               // writeIndex wraps: 3 at 5,6,7 then 1 at 0
        // Now buffer contains at read indices 5,6,7,0 → values 9,8,7,1 then 2,3,4 at 1,2,3
        let all = read(7, from: buf)
        XCTAssertEqual(all, [9, 8, 7, 1, 2, 3, 4])
    }

    // MARK: - Overflow (buffer full)

    func testOverflow_dropsNewDataWhenFull() {
        let buf = AudioRingBuffer(capacitySamples: 4)
        let written1 = write([1, 2, 3, 4], into: buf)      // fills completely
        let written2 = write([5, 6], into: buf)             // no space — should drop
        XCTAssertEqual(written1, 4)
        XCTAssertEqual(written2, 0)
        XCTAssertEqual(buf.availableToRead(), 4)
        XCTAssertEqual(read(4, from: buf), [1, 2, 3, 4])   // original data intact
    }

    func testOverflow_partialWriteWhenNearlyFull() {
        let buf = AudioRingBuffer(capacitySamples: 4)
        write([1, 2], into: buf)                            // 2 written, 2 free
        let written = write([3, 4, 5, 6], into: buf)        // only 2 fit
        XCTAssertEqual(written, 2)
        XCTAssertEqual(read(4, from: buf), [1, 2, 3, 4])
    }

    // MARK: - Underflow (read more than available)

    func testUnderflow_returnsOnlyAvailableSamples() {
        let buf = AudioRingBuffer(capacitySamples: 16)
        write([1, 2, 3], into: buf)
        var out = [Float](repeating: -1, count: 6)
        let got = out.withUnsafeMutableBufferPointer { ptr in
            buf.read(into: ptr.baseAddress!, count: 6)
        }
        XCTAssertEqual(got, 3)
        XCTAssertEqual(Array(out.prefix(3)), [1, 2, 3])
    }

    func testUnderflow_emptyBufferReadsZero() {
        let buf = AudioRingBuffer(capacitySamples: 8)
        var out = [Float](repeating: -1, count: 4)
        let got = out.withUnsafeMutableBufferPointer { ptr in
            buf.read(into: ptr.baseAddress!, count: 4)
        }
        XCTAssertEqual(got, 0)
    }

    // MARK: - Clear

    func testClear_resetsAvailableToZero() {
        let buf = AudioRingBuffer(capacitySamples: 8)
        write([1, 2, 3, 4, 5], into: buf)
        buf.clear()
        XCTAssertEqual(buf.availableToRead(), 0)
    }

    func testClear_allowsRewriteAfterClear() {
        let buf = AudioRingBuffer(capacitySamples: 4)
        write([1, 2, 3, 4], into: buf)
        buf.clear()
        write([9, 8, 7, 6], into: buf)
        XCTAssertEqual(read(4, from: buf), [9, 8, 7, 6])
    }

    // MARK: - Capacity

    func testCapacity_matchesConstructorArgument() {
        XCTAssertEqual(AudioRingBuffer(capacitySamples: 48_000).capacity, 48_000)
        XCTAssertEqual(AudioRingBuffer(capacitySamples: 1).capacity, 1)
    }

    func testCapacity_zeroClampedToOne() {
        // Constructor uses max(1, n) to avoid zero-size storage
        XCTAssertGreaterThanOrEqual(AudioRingBuffer(capacitySamples: 0).capacity, 1)
    }

    // MARK: - Zero-length guards

    func testWriteZeroSamples_returnsZeroAndDoesNotChange() {
        let buf = AudioRingBuffer(capacitySamples: 8)
        var dummy: Float = 0
        let n = buf.write(from: &dummy, count: 0)
        XCTAssertEqual(n, 0)
        XCTAssertEqual(buf.availableToRead(), 0)
    }

    func testReadZeroSamples_returnsZeroAndDoesNotChange() {
        let buf = AudioRingBuffer(capacitySamples: 8)
        write([1, 2, 3], into: buf)
        var dummy: Float = 0
        let n = buf.read(into: &dummy, count: 0)
        XCTAssertEqual(n, 0)
        XCTAssertEqual(buf.availableToRead(), 3)
    }
}
