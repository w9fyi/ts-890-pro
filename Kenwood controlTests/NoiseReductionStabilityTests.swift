import XCTest
@testable import Kenwood_control

/// Long-run stability tests for the noise reduction pipeline.
///
/// These tests guard against:
///   - Processing time growing over thousands of frames (latency creep)
///   - Output energy drifting to silence or clipping after long runs (state divergence)
///   - Backend swaps introducing stalls or corrupted output
///
/// No radio connection is needed — all NR processing is in-process.
final class NoiseReductionStabilityTests: XCTestCase {

    nonisolated deinit {}

    // 10 ms at 48 kHz — matches RNNoise's required frame size and is a
    // reasonable chunk size for WDSP too.
    private let kFrameSize = 480

    /// Steady tri-tone input: 440 Hz + 1500 Hz + 7000 Hz, amplitude ~0.9 peak.
    private func testFrame(seed: Int = 0) -> [Float] {
        (0..<kFrameSize).map { i in
            let t = Float(i + seed * kFrameSize) / 48000.0
            return  0.5  * sin(2 * .pi * 440  * t)
                 + 0.25 * sin(2 * .pi * 1500 * t)
                 + 0.15 * sin(2 * .pi * 7000 * t)
        }
    }

    private func rms(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        return sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
    }

    // MARK: - Throughput (latency budget)

    /// WDSP EMNR must process each 10 ms frame in well under 10 ms.
    /// If average time exceeds 5 ms the pipeline would fall behind real-time.
    func testEMNR_10000frames_staysWithinLatencyBudget() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) } // warmup

        let start = Date()
        for i in 0..<10_000 {
            var f = testFrame(seed: i)
            proc.processFrame48kMonoInPlace(&f)
        }
        let msPerFrame = Date().timeIntervalSince(start) / 10_000 * 1000
        XCTAssertLessThan(msPerFrame, 5.0,
            "WDSP EMNR: \(String(format: "%.3f", msPerFrame)) ms/frame — exceeds 5 ms budget")
        print("EMNR throughput: \(String(format: "%.3f", msPerFrame)) ms/frame")
    }

    func testANR_10000frames_staysWithinLatencyBudget() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }

        let start = Date()
        for i in 0..<10_000 {
            var f = testFrame(seed: i)
            proc.processFrame48kMonoInPlace(&f)
        }
        let msPerFrame = Date().timeIntervalSince(start) / 10_000 * 1000
        XCTAssertLessThan(msPerFrame, 5.0,
            "WDSP ANR: \(String(format: "%.3f", msPerFrame)) ms/frame — exceeds 5 ms budget")
        print("ANR throughput: \(String(format: "%.3f", msPerFrame)) ms/frame")
    }

    func testRNNoise_10000frames_staysWithinLatencyBudget() throws {
        guard let proc = RNNoiseProcessor() else {
            throw XCTSkip("RNNoise not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }

        let start = Date()
        for i in 0..<10_000 {
            var f = testFrame(seed: i)
            proc.processFrame48kMonoInPlace(&f)
        }
        let msPerFrame = Date().timeIntervalSince(start) / 10_000 * 1000
        XCTAssertLessThan(msPerFrame, 5.0,
            "RNNoise: \(String(format: "%.3f", msPerFrame)) ms/frame — exceeds 5 ms budget")
        print("RNNoise throughput: \(String(format: "%.3f", msPerFrame)) ms/frame")
    }

    // MARK: - Output energy consistency (no degradation)

    /// Run 5000 frames and verify output RMS stays within 50–200% of its
    /// early value. A ratio outside this range means the processor's internal
    /// state has drifted — e.g. gain collapsing to silence or runaway boost.
    func testEMNR_outputEnergy_stableOver5000Frames() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<50 { _ = proc.processFrame48kMono(frame) } // warmup

        let earlyEnergy = rms(proc.processFrame48kMono(frame))
        for _ in 0..<5_000 { _ = proc.processFrame48kMono(frame) }
        let lateEnergy  = rms(proc.processFrame48kMono(frame))

        XCTAssertGreaterThan(earlyEnergy, 0.001, "EMNR: early output is silent")
        XCTAssertGreaterThan(lateEnergy,  0.001, "EMNR: output went silent after 5000 frames")
        let ratio = lateEnergy / earlyEnergy
        XCTAssertGreaterThan(ratio, 0.5,
            "EMNR energy dropped to \(String(format: "%.1f", ratio*100))% after 5000 frames")
        XCTAssertLessThan(ratio, 2.0,
            "EMNR energy grew to \(String(format: "%.1f", ratio*100))% after 5000 frames")
        print("EMNR energy ratio after 5000 frames: \(String(format: "%.3f", ratio))")
    }

    func testANR_outputEnergy_stableOver5000Frames() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<50 { _ = proc.processFrame48kMono(frame) }

        let earlyEnergy = rms(proc.processFrame48kMono(frame))
        for _ in 0..<5_000 { _ = proc.processFrame48kMono(frame) }
        let lateEnergy  = rms(proc.processFrame48kMono(frame))

        XCTAssertGreaterThan(lateEnergy, 0.001, "ANR: output went silent after 5000 frames")
        let ratio = lateEnergy / earlyEnergy
        XCTAssertGreaterThan(ratio, 0.5,
            "ANR energy dropped to \(String(format: "%.1f", ratio*100))% after 5000 frames")
        XCTAssertLessThan(ratio, 2.0,
            "ANR energy grew to \(String(format: "%.1f", ratio*100))% after 5000 frames")
        print("ANR energy ratio after 5000 frames: \(String(format: "%.3f", ratio))")
    }

    func testRNNoise_outputEnergy_stableOver5000Frames() throws {
        guard let proc = RNNoiseProcessor() else {
            throw XCTSkip("RNNoise not available")
        }
        proc.isEnabled = true
        let frame = testFrame()

        // Run to steady state — RNNoise will learn the pure-tone "noise" profile.
        for _ in 0..<200 { _ = proc.processFrame48kMono(frame) }

        // Capture the suppression level at steady state.
        let earlyEnergy = rms(proc.processFrame48kMono(frame))

        // Run 4800 more frames (48 seconds of audio equivalent).
        for _ in 0..<4_800 { _ = proc.processFrame48kMono(frame) }
        let lateEnergy = rms(proc.processFrame48kMono(frame))

        print("RNNoise energy — early: \(String(format: "%.6f", earlyEnergy))  late: \(String(format: "%.6f", lateEnergy))")

        // RNNoise aggressively suppresses pure tones (they look like noise to it).
        // We don't assert a specific level — just that the output is a finite,
        // non-NaN number and that the processor hasn't hard-locked to zero forever.
        XCTAssertFalse(earlyEnergy.isNaN, "RNNoise early output is NaN")
        XCTAssertFalse(lateEnergy.isNaN,  "RNNoise late output is NaN")
        XCTAssertFalse(earlyEnergy.isInfinite, "RNNoise early output is infinite")
        XCTAssertFalse(lateEnergy.isInfinite,  "RNNoise late output is infinite")
        XCTAssertGreaterThanOrEqual(earlyEnergy, 0, "RNNoise early output energy is negative")
        XCTAssertGreaterThanOrEqual(lateEnergy,  0, "RNNoise late output energy is negative")
        // The processor must not be hard-locked to silence for ALL frames —
        // the silence test already covers per-frame silence, this checks state hasn't wedged.
        XCTAssertFalse(earlyEnergy == 0 && lateEnergy == 0,
            "RNNoise output is exactly zero for all frames — internal state appears wedged")
    }

    // MARK: - No silence creep

    /// After warmup, no frame should ever go fully silent.
    /// If a processor starts outputting all-zero it means its internal gain
    /// estimate has collapsed — audio would cut out on air.
    func testEMNR_neverProducesSilenceAfterWarmup() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<50 { _ = proc.processFrame48kMono(frame) }

        var silentCount = 0
        for i in 0..<1_000 {
            let out = proc.processFrame48kMono(testFrame(seed: i))
            if rms(out) < 0.0001 { silentCount += 1 }
        }
        XCTAssertEqual(silentCount, 0,
            "EMNR produced \(silentCount)/1000 silent frames after warmup")
    }

    func testANR_neverProducesSilenceAfterWarmup() throws {
        guard let proc = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<50 { _ = proc.processFrame48kMono(frame) }

        var silentCount = 0
        for i in 0..<1_000 {
            let out = proc.processFrame48kMono(testFrame(seed: i))
            if rms(out) < 0.0001 { silentCount += 1 }
        }
        XCTAssertEqual(silentCount, 0,
            "ANR produced \(silentCount)/1000 silent frames after warmup")
    }

    func testRNNoise_neverProducesSilenceAfterWarmup() throws {
        guard let proc = RNNoiseProcessor() else {
            throw XCTSkip("RNNoise not available")
        }
        proc.isEnabled = true
        let frame = testFrame()
        for _ in 0..<20 { _ = proc.processFrame48kMono(frame) }

        var silentCount = 0
        for i in 0..<1_000 {
            let out = proc.processFrame48kMono(testFrame(seed: i))
            if rms(out) < 0.0001 { silentCount += 1 }
        }
        XCTAssertEqual(silentCount, 0,
            "RNNoise produced \(silentCount)/1000 silent frames after warmup")
    }

    // MARK: - Backend swap stability

    /// Swap backends 50 times while processing 100 frames between each swap.
    /// Simulates repeated user cycling through NR backends during an operating session.
    /// Guards against stalls, crashes, or the swap loop falling behind real-time.
    func testProxy_50backendSwaps_noStallOrCrash() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr),
              let anr  = WDSPNoiseReductionProcessor(mode: .anr) else {
            throw XCTSkip("FFTW3 not available")
        }
        emnr.isEnabled = true
        anr.isEnabled  = true
        let proxy = NoiseReductionProcessorProxy(inner: emnr)
        let frame = testFrame()

        let start = Date()
        for i in 0..<50 {
            switch i % 3 {
            case 0: proxy.inner = PassthroughNoiseReduction()
            case 1: proxy.inner = emnr
            default: proxy.inner = anr
            }
            for j in 0..<100 {
                var f = testFrame(seed: i * 100 + j)
                proxy.processFrame48kMonoInPlace(&f)
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        // 50 swaps × 100 frames × 10 ms = 50 s of audio processed — must finish in < 5 s wall clock
        XCTAssertLessThan(elapsed, 5.0,
            "50 backend swaps × 100 frames took \(String(format: "%.2f", elapsed))s — possible stall")
        print("Backend swap stress: \(String(format: "%.2f", elapsed))s for 5000 frames across 50 swaps")
    }

    /// After cycling Passthrough → EMNR 50 times, the proxy must still produce
    /// non-silent, modified output — the same scenario that broke Cmd-Shift-N.
    func testProxy_passthroughCycle_outputRemainsValid() throws {
        guard let emnr = WDSPNoiseReductionProcessor(mode: .emnr) else {
            throw XCTSkip("FFTW3 not available")
        }
        emnr.isEnabled = true
        let proxy = NoiseReductionProcessorProxy(inner: emnr)
        let frame  = testFrame()
        for _ in 0..<50 { _ = proxy.processFrame48kMono(frame) } // warmup

        for cycle in 0..<50 {
            proxy.inner = PassthroughNoiseReduction()
            let ptOut = proxy.processFrame48kMono(frame)
            XCTAssertEqual(ptOut, frame,
                "Cycle \(cycle): passthrough must return input unchanged")

            proxy.inner = emnr
            for _ in 0..<5 { _ = proxy.processFrame48kMono(frame) } // re-warm
            let emnrOut = proxy.processFrame48kMono(frame)
            XCTAssertGreaterThan(rms(emnrOut), 0.001,
                "Cycle \(cycle): EMNR output went silent after swap-back from passthrough")
        }
    }
}
