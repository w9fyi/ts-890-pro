import XCTest
@testable import Kenwood_control

// MARK: - Helpers

private let kNRFrameSize = 480  // 10 ms at 48 kHz; matches rnnoise_get_frame_size()

/// Deterministic multi-tone signal covering low, mid, and high audio frequencies.
private func testFrame(size: Int = kNRFrameSize) -> [Float] {
    (0..<size).map { i in
        let t = Float(i) / 48000.0
        return  0.5  * sin(2 * .pi * 440  * t)   // A4
             + 0.25 * sin(2 * .pi * 1500 * t)   // mid
             + 0.15 * sin(2 * .pi * 7000 * t)   // high
    }
}

/// Returns the max absolute sample-wise difference between two frames.
private func maxDiff(_ a: [Float], _ b: [Float]) -> Float {
    zip(a, b).map { abs($0 - $1) }.max() ?? 0
}

// MARK: - PassthroughNoiseReduction

final class PassthroughNRTests: XCTestCase {

    nonisolated deinit {}

    private let proc = PassthroughNoiseReduction()

    func testPassthrough_isAvailable_isFalse() {
        XCTAssertFalse(proc.isAvailable)
    }

    func testPassthrough_disabled_returnsInputUnchanged() {
        proc.isEnabled = false
        let frame = testFrame()
        XCTAssertEqual(proc.processFrame48kMono(frame), frame)
    }

    func testPassthrough_enabled_returnsInputUnchanged() {
        // PassthroughNoiseReduction is always a no-op regardless of isEnabled.
        proc.isEnabled = true
        let frame = testFrame()
        XCTAssertEqual(proc.processFrame48kMono(frame), frame)
    }

    func testPassthrough_outputLength_equalsInputLength() {
        let frame = testFrame()
        XCTAssertEqual(proc.processFrame48kMono(frame).count, frame.count)
    }

    func testPassthrough_inPlace_doesNotModifyFrame() {
        var frame = testFrame()
        let original = frame
        proc.processFrame48kMonoInPlace(&frame)
        XCTAssertEqual(frame, original)
    }
}

// MARK: - WDSPNoiseReductionProcessor

final class WDSPNRTests: XCTestCase {

    nonisolated deinit {}

    // MARK: Init / availability

    func testEMNR_init_succeeds() throws {
        guard WDSPNoiseReductionProcessor(mode: .emnr) != nil else {
            throw XCTSkip("FFTW3 not available in this environment")
        }
    }

    func testANR_init_succeeds() throws {
        guard WDSPNoiseReductionProcessor(mode: .anr) != nil else {
            throw XCTSkip("FFTW3 not available in this environment")
        }
    }

    func testEMNR_isAvailable_isTrue() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        XCTAssertTrue(proc.isAvailable)
    }

    func testANR_isAvailable_isTrue() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        XCTAssertTrue(proc.isAvailable)
    }

    // MARK: Disabled == bit-exact passthrough

    func testEMNR_disabled_outputEqualsInput() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = false
        let frame = testFrame()
        XCTAssertEqual(proc.processFrame48kMono(frame), frame,
                       "Disabled WDSP EMNR must be a bit-exact passthrough")
    }

    func testANR_disabled_outputEqualsInput() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = false
        let frame = testFrame()
        XCTAssertEqual(proc.processFrame48kMono(frame), frame,
                       "Disabled WDSP ANR must be a bit-exact passthrough")
    }

    // MARK: Output-length invariant

    func testEMNR_enabled_outputLengthEqualsInputLength() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        XCTAssertEqual(proc.processFrame48kMono(testFrame()).count, kNRFrameSize)
    }

    func testANR_enabled_outputLengthEqualsInputLength() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        XCTAssertEqual(proc.processFrame48kMono(testFrame()).count, kNRFrameSize)
    }

    // MARK: Enabled actually modifies the signal

    func testEMNR_enabled_modifiesOutputAfterWarmup() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }   // warm-up
        let out = proc.processFrame48kMono(frame)
        XCTAssertGreaterThan(maxDiff(frame, out), 1e-6,
            "Enabled WDSP EMNR must alter the signal; got identical output after 20 warm-up frames")
    }

    func testANR_enabled_modifiesOutputAfterWarmup() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }
        let out = proc.processFrame48kMono(frame)
        XCTAssertGreaterThan(maxDiff(frame, out), 1e-6,
            "Enabled WDSP ANR must alter the signal after 20 warm-up frames")
    }

    // MARK: Output is not silent

    func testEMNR_enabled_outputIsNotSilent() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        var out = [Float](repeating: 0, count: kNRFrameSize)
        for _ in 0..<20 { out = proc.processFrame48kMono(testFrame()) }
        let rms = sqrt(out.map { $0 * $0 }.reduce(0, +) / Float(kNRFrameSize))
        XCTAssertGreaterThan(rms, 0,
            "WDSP EMNR must not produce silent output for a non-silent input")
    }

    // MARK: Toggle enabled / disabled mid-stream

    func testEMNR_toggleEnabled_doesNotCrash() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        let frame = testFrame()
        proc.isEnabled = true;  for _ in 0..<10 { _ = proc.processFrame48kMono(frame) }
        proc.isEnabled = false; for _ in 0..<10 { _ = proc.processFrame48kMono(frame) }
        proc.isEnabled = true;  for _ in 0..<10 { _ = proc.processFrame48kMono(frame) }
        // Reaching this point without a crash is the assertion.
    }

    func testEMNR_disableAfterWarmup_resumesPassthrough() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }   // warm-up
        proc.isEnabled = false
        XCTAssertEqual(proc.processFrame48kMono(frame), frame,
            "After disabling WDSP EMNR mid-stream the output must revert to passthrough")
    }

    func testANR_disableAfterWarmup_resumesPassthrough() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }
        proc.isEnabled = false
        XCTAssertEqual(proc.processFrame48kMono(frame), frame,
            "After disabling WDSP ANR mid-stream the output must revert to passthrough")
    }

    // MARK: processFrame48kMonoInPlace matches processFrame48kMono

    func testEMNR_inPlace_producesIdenticalResultToReturnCopy() throws {
        guard let p1 = WDSPNoiseReductionProcessor(mode: .emnr),
              let p2 = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        p1.isEnabled = true; p2.isEnabled = true
        let frame = testFrame()
        // Warm both processors identically so their internal state matches.
        for _ in 0..<20 {
            _ = p1.processFrame48kMono(frame)
            var tmp = frame; p2.processFrame48kMonoInPlace(&tmp)
        }
        let outCopy = p1.processFrame48kMono(frame)
        var outInPlace = frame; p2.processFrame48kMonoInPlace(&outInPlace)
        XCTAssertEqual(outCopy, outInPlace,
            "processFrame48kMono and processFrame48kMonoInPlace must produce identical output")
    }

    // MARK: 100-frame stress (crash detection)

    func testEMNR_100Frames_doesNotCrash() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        for _ in 0..<100 { _ = proc.processFrame48kMono(testFrame()) }
    }

    func testANR_100Frames_doesNotCrash() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        for _ in 0..<100 { _ = proc.processFrame48kMono(testFrame()) }
    }
}

// MARK: - RNNoiseProcessor

final class RNNoiseNRTests: XCTestCase {

    nonisolated deinit {}

    private func makeProc() throws -> RNNoiseProcessor {
        guard let p = RNNoiseProcessor() else {
            throw XCTSkip("RNNoise C not built or rnnoise_create() returned nil")
        }
        return p
    }

    // MARK: Init / availability

    func testRNNoise_init_succeeds() throws { _ = try makeProc() }

    func testRNNoise_isAvailable_isTrue() throws {
        XCTAssertTrue(try makeProc().isAvailable)
    }

    // MARK: Frame size

    func testRNNoise_frameSize_is480() throws {
        // The standard RNNoise model always uses 480-sample (10 ms) frames.
        _ = try makeProc()  // confirm library is available
        XCTAssertEqual(Int(rnnoise_get_frame_size()), kNRFrameSize,
                       "RNNoise frame size must be 480 samples (10 ms at 48 kHz)")
    }

    // MARK: Disabled == bit-exact passthrough

    func testRNNoise_disabled_outputEqualsInput() throws {
        let p = try makeProc()
        p.isEnabled = false
        let frame = testFrame()
        XCTAssertEqual(p.processFrame48kMono(frame), frame,
                       "Disabled RNNoise must be a bit-exact passthrough")
    }

    // MARK: Output-length invariant

    func testRNNoise_enabled_outputLengthEqualsInputLength() throws {
        let p = try makeProc()
        p.isEnabled = true
        XCTAssertEqual(p.processFrame48kMono(testFrame()).count, kNRFrameSize)
    }

    // MARK: Enabled actually modifies the signal

    func testRNNoise_enabled_modifiesOutputAfterWarmup() throws {
        let p = try makeProc()
        p.isEnabled = true
        let frame = testFrame()
        for _ in 0..<10 { _ = p.processFrame48kMono(frame) }   // warm-up DNN
        let out = p.processFrame48kMono(frame)
        XCTAssertGreaterThan(maxDiff(frame, out), 1e-6,
            "Enabled RNNoise must alter the signal after warm-up")
    }

    // MARK: Output is not silent

    func testRNNoise_enabled_outputIsNotSilent() throws {
        let p = try makeProc()
        p.isEnabled = true
        var out = [Float](repeating: 0, count: kNRFrameSize)
        for _ in 0..<10 { out = p.processFrame48kMono(testFrame()) }
        let rms = sqrt(out.map { $0 * $0 }.reduce(0, +) / Float(kNRFrameSize))
        XCTAssertGreaterThan(rms, 0,
            "Enabled RNNoise must not produce silence for a non-silent input")
    }

    // MARK: Toggle enabled / disabled mid-stream

    func testRNNoise_toggleEnabled_doesNotCrash() throws {
        let p = try makeProc()
        let frame = testFrame()
        p.isEnabled = true;  for _ in 0..<10 { _ = p.processFrame48kMono(frame) }
        p.isEnabled = false; for _ in 0..<10 { _ = p.processFrame48kMono(frame) }
        p.isEnabled = true;  for _ in 0..<10 { _ = p.processFrame48kMono(frame) }
    }

    func testRNNoise_disableAfterWarmup_resumesPassthrough() throws {
        let p = try makeProc()
        p.isEnabled = true
        let frame = testFrame()
        for _ in 0..<10 { _ = p.processFrame48kMono(frame) }
        p.isEnabled = false
        XCTAssertEqual(p.processFrame48kMono(frame), frame,
            "After disabling RNNoise mid-stream the output must revert to passthrough")
    }

    // MARK: 100-frame stress (crash detection)

    func testRNNoise_100Frames_doesNotCrash() throws {
        let p = try makeProc()
        p.isEnabled = true
        for _ in 0..<100 { _ = p.processFrame48kMono(testFrame()) }
    }
}

// MARK: - NoiseReductionProcessorProxy

final class NRProxyTests: XCTestCase {

    nonisolated deinit {}

    // MARK: Delegation — availability and enabled

    func testProxy_isAvailable_delegatesToInner() {
        let inner = PassthroughNoiseReduction()
        XCTAssertEqual(NoiseReductionProcessorProxy(inner: inner).isAvailable,
                       inner.isAvailable)
    }

    func testProxy_isEnabled_readDelegatesToInner() {
        let inner = PassthroughNoiseReduction()
        inner.isEnabled = true
        XCTAssertTrue(NoiseReductionProcessorProxy(inner: inner).isEnabled)
    }

    func testProxy_isEnabled_writePropagatestoInner() {
        let inner = PassthroughNoiseReduction()
        let proxy = NoiseReductionProcessorProxy(inner: inner)
        proxy.isEnabled = true
        XCTAssertTrue(inner.isEnabled,
                      "Writing proxy.isEnabled must propagate to inner processor")
    }

    // MARK: Delegation — processing

    func testProxy_processFrame_delegatesToInner_passthrough() {
        let proxy = NoiseReductionProcessorProxy(inner: PassthroughNoiseReduction())
        let frame = testFrame()
        XCTAssertEqual(proxy.processFrame48kMono(frame), frame)
    }

    func testProxy_inPlace_delegatesToInner_passthrough() {
        let proxy = NoiseReductionProcessorProxy(inner: PassthroughNoiseReduction())
        var frame = testFrame()
        let original = frame
        proxy.processFrame48kMonoInPlace(&frame)
        XCTAssertEqual(frame, original)
    }

    // MARK: Backend swap

    func testProxy_swapToEMNR_isAvailableBecomesTrue() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        let proxy = NoiseReductionProcessorProxy(inner: PassthroughNoiseReduction())
        XCTAssertFalse(proxy.isAvailable)
        proxy.inner = emnr
        XCTAssertTrue(proxy.isAvailable,
                      "After swapping inner to EMNR, proxy.isAvailable must reflect the new inner")
    }

    func testProxy_swapToPassthrough_isAvailableBecomesFalse() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        let proxy = NoiseReductionProcessorProxy(inner: emnr)
        XCTAssertTrue(proxy.isAvailable)
        proxy.inner = PassthroughNoiseReduction()
        XCTAssertFalse(proxy.isAvailable,
                       "After swapping inner to passthrough, proxy.isAvailable must be false")
    }

    func testProxy_swapMidStream_doesNotCrash() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr),
              let anr  = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        emnr.isEnabled = true; anr.isEnabled = true
        let proxy = NoiseReductionProcessorProxy(inner: emnr)
        let frame = testFrame()
        for _ in 0..<10 { _ = proxy.processFrame48kMono(frame) }
        proxy.inner = anr                                           // EMNR → ANR
        for _ in 0..<10 { _ = proxy.processFrame48kMono(frame) }
        proxy.inner = PassthroughNoiseReduction()                   // ANR → passthrough
        XCTAssertEqual(proxy.processFrame48kMono(frame), frame,
            "After swapping inner to passthrough mid-stream, output must equal input")
    }

    func testProxy_swapInner_enabledStateTransfersCorrectly() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        emnr.isEnabled = true
        let proxy = NoiseReductionProcessorProxy(inner: PassthroughNoiseReduction())
        proxy.isEnabled = false
        proxy.inner = emnr
        // After swap the proxy reads from the new inner, which has isEnabled = true.
        XCTAssertTrue(proxy.isEnabled,
            "proxy.isEnabled must reflect the new inner's isEnabled after a swap")
    }
}

// MARK: - RadioState.isNoiseReductionAvailable observation fix

/// Verifies that `RadioState.isNoiseReductionAvailable` is a stored property that updates
/// whenever `setNoiseReductionBackend` is called, so SwiftUI `.disabled` bindings
/// always reflect the current backend (fixes the Cmd-Shift-N "nothing happened" bug).
final class RadioStateNRAvailabilityTests: XCTestCase {

    nonisolated deinit {}

    func testAvailableOnInit_whenWDSPPresent() throws {
        guard WDSPNoiseReductionProcessor(mode: .emnr) != nil else {
            throw XCTSkip("FFTW3 not available")
        }
        let radio = RadioState()
        XCTAssertTrue(radio.isNoiseReductionAvailable,
            "isNoiseReductionAvailable must be true after init when WDSP EMNR is the default backend")
    }

    func testSwitchToPassthrough_makesUnavailable() throws {
        guard WDSPNoiseReductionProcessor(mode: .emnr) != nil else {
            throw XCTSkip("FFTW3 not available")
        }
        let radio = RadioState()
        XCTAssertTrue(radio.isNoiseReductionAvailable)
        radio.setNoiseReductionBackend("Passthrough (disabled)")
        XCTAssertFalse(radio.isNoiseReductionAvailable,
            "Switching to Passthrough must set isNoiseReductionAvailable = false immediately")
    }

    func testRoundTrip_passthroughThenWDSP_restoresAvailable() throws {
        guard WDSPNoiseReductionProcessor(mode: .emnr) != nil else {
            throw XCTSkip("FFTW3 not available")
        }
        let radio = RadioState()
        radio.setNoiseReductionBackend("Passthrough (disabled)")
        XCTAssertFalse(radio.isNoiseReductionAvailable)
        radio.setNoiseReductionBackend("WDSP EMNR")
        XCTAssertTrue(radio.isNoiseReductionAvailable,
            "After cycling Passthrough → WDSP EMNR, isNoiseReductionAvailable must be true again (Cmd-Shift-N fix)")
    }

    func testSetNoiseReduction_worksAfterRoundTrip() throws {
        guard WDSPNoiseReductionProcessor(mode: .emnr) != nil else {
            throw XCTSkip("FFTW3 not available")
        }
        let radio = RadioState()
        radio.setNoiseReductionBackend("Passthrough (disabled)")
        radio.setNoiseReductionBackend("WDSP EMNR")
        XCTAssertFalse(radio.isNoiseReductionEnabled)
        radio.setNoiseReduction(enabled: true)
        XCTAssertTrue(radio.isNoiseReductionEnabled,
            "setNoiseReduction must work after cycling through Passthrough and back")
    }

    func testSwitchToANR_staysAvailable() throws {
        guard WDSPNoiseReductionProcessor(mode: .anr) != nil else {
            throw XCTSkip("FFTW3 not available")
        }
        let radio = RadioState()
        radio.setNoiseReductionBackend("WDSP ANR")
        XCTAssertTrue(radio.isNoiseReductionAvailable,
            "isNoiseReductionAvailable must remain true when switching to WDSP ANR")
    }
}
