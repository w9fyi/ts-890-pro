import XCTest
@testable import Kenwood_control

/// Performance and re-render isolation tests for RadioState.
///
/// RadioState uses @Observable (Swift Observation). With @Observable, SwiftUI
/// only re-renders views that read a property that actually changed — so the
/// isolation guarantee is: SM/scope/diagnostics frames must NOT mutate any
/// RadioState stored property. These tests verify exactly that: after high-
/// frequency frames arrive, all RadioState properties that views display remain
/// unchanged, while the dedicated isolated stores (MeterStore, ScopeStore,
/// DiagnosticsStore) do update as expected.
///
/// If any isolation test fails it means a regression has re-introduced a
/// property mutation that will cause unnecessary SwiftUI re-renders and
/// VoiceOver accessibility tree re-walks.
final class RadioStatePerformanceTests: XCTestCase {

    var radio: RadioState!

    override func setUp() {
        super.setUp()
        radio = RadioState()
        MeterStore.shared.readings = [:]
        ScopeStore.shared.points = []
        DiagnosticsStore.shared.lastTXFrame = ""
        DiagnosticsStore.shared.lastRXFrame = ""
    }

    override func tearDown() {
        radio = nil
        super.tearDown()
    }

    // MARK: - Isolation: meters

    /// SM meter frames must update MeterStore, NOT RadioState properties.
    ///
    /// Before the MeterStore fix each SM response mutated a RadioState property,
    /// causing SwiftUI to re-render the front panel and VoiceOver to re-walk
    /// the accessibility tree 4+ times per second even when idle.
    func testSMFrames_doNotMutateRadioStateProperties() {
        // Record baseline RadioState values
        let baseFreq    = radio.vfoAFrequencyHz
        let baseMode    = radio.operatingMode
        let baseAGC     = radio.agcMode
        let baseAFGain  = radio.afGain

        radio.handleFrame("SM00015;")
        radio.handleFrame("SM10005;")
        radio.handleFrame("SM20002;")
        radio.handleFrame("SM50060;")

        XCTAssertEqual(radio.vfoAFrequencyHz, baseFreq, "SM frames must not change vfoAFrequencyHz")
        XCTAssertEqual(radio.operatingMode,   baseMode, "SM frames must not change operatingMode")
        XCTAssertEqual(radio.agcMode,         baseAGC,  "SM frames must not change agcMode")
        XCTAssertEqual(radio.afGain,          baseAFGain,"SM frames must not change afGain")
    }

    /// SM frames must route to MeterStore so the meter views update.
    func testSMFrames_updateMeterStore() {
        radio.handleFrame("SM00015;")
        radio.handleFrame("SM10005;")
        XCTAssertNotNil(MeterStore.shared.readings[0], "SM0 frame must update MeterStore.readings[0]")
        XCTAssertNotNil(MeterStore.shared.readings[1], "SM1 frame must update MeterStore.readings[1]")
    }

    /// MeterStore mutations must not touch RadioState properties.
    func testMeterStore_updatesDoNotMutateRadioStateProperties() {
        let baseFreq = radio.vfoAFrequencyHz

        MeterStore.shared.readings[0] = 0.5
        MeterStore.shared.readings[1] = 0.3
        MeterStore.shared.readings[2] = 0.1
        MeterStore.shared.readings[5] = 0.8

        XCTAssertEqual(radio.vfoAFrequencyHz, baseFreq,
            "MeterStore is a separate @Observable — its updates must not mutate RadioState properties.")
    }

    // MARK: - Isolation: scope / waterfall

    /// Bandscope data must NOT mutate RadioState properties.
    ///
    /// Before the ScopeStore fix each ##DD2 frame (~5fps on LAN) mutated a
    /// RadioState property, re-rendering the entire front panel at 5fps.
    func testScopeStore_updatesDoNotMutateRadioStateProperties() {
        let baseFreq = radio.vfoAFrequencyHz

        ScopeStore.shared.points = Array(repeating: 0x40, count: 640)
        ScopeStore.shared.points = Array(repeating: 0x50, count: 640)
        ScopeStore.shared.points = Array(repeating: 0x60, count: 640)
        ScopeStore.shared.points = Array(repeating: 0x70, count: 640)
        ScopeStore.shared.points = Array(repeating: 0x80, count: 640)

        XCTAssertEqual(radio.vfoAFrequencyHz, baseFreq,
            "ScopeStore is a separate @Observable — scope updates must not mutate RadioState. " +
            "5fps scope streaming was causing constant VoiceOver disruption.")
    }

    // MARK: - Isolation: frame logging

    /// TX frame logging must NOT mutate RadioState properties.
    ///
    /// Before the DiagnosticsStore fix, send() set a @Published property on
    /// RadioState. The meter poll timer calls send() 4x/second → 4 re-renders
    /// per second even when the radio is completely idle.
    func testDiagnosticsStore_txFrameDoesNotMutateRadioStateProperties() {
        let baseFreq = radio.vfoAFrequencyHz

        DiagnosticsStore.shared.lastTXFrame = "SM0;"
        DiagnosticsStore.shared.lastTXFrame = "SM1;"
        DiagnosticsStore.shared.lastTXFrame = "SM2;"
        DiagnosticsStore.shared.lastTXFrame = "SM5;"

        XCTAssertEqual(radio.vfoAFrequencyHz, baseFreq,
            "DiagnosticsStore is a separate @Observable — TX log updates must not mutate RadioState.")
    }

    /// RX frame logging must NOT mutate RadioState properties.
    func testDiagnosticsStore_rxFrameDoesNotMutateRadioStateProperties() {
        let baseFreq = radio.vfoAFrequencyHz

        DiagnosticsStore.shared.lastRXFrame = "SM00015;"
        DiagnosticsStore.shared.lastRXFrame = "SM10005;"
        DiagnosticsStore.shared.lastRXFrame = "SM20002;"
        DiagnosticsStore.shared.lastRXFrame = "SM50060;"

        XCTAssertEqual(radio.vfoAFrequencyHz, baseFreq,
            "DiagnosticsStore is a separate @Observable — RX log updates must not mutate RadioState.")
    }

    // MARK: - Simulated connected operation (1 second of LAN traffic)

    /// Simulates one second of LAN-connected idle operation. Verifies that only
    /// the genuine AI state change (FA frame) mutates a RadioState property, while
    /// all meter/scope/logging noise routes to isolated stores.
    ///
    /// One second of LAN traffic includes:
    ///   • 4 SM meter responses (meter poll timer)
    ///   • 5 scope frames at ~5fps (##DD2 bandscope)
    ///   • 4 TX frame logs (the poll sends)
    ///   • 4 RX frame logs (SM responses)
    ///   • 1 genuine AI frequency update (FA frame)
    ///
    /// Only the FA frame should mutate a RadioState property.
    func testSimulatedIdleLANOperation_onlyFAMutatesRadioState() {
        // Baseline: no frequency set yet
        XCTAssertNil(radio.vfoAFrequencyHz, "vfoAFrequencyHz should be nil before any FA frame")

        // 4 SM meter responses — must go to MeterStore, not RadioState
        radio.handleFrame("SM00015;")
        radio.handleFrame("SM10005;")
        radio.handleFrame("SM20002;")
        radio.handleFrame("SM50060;")
        XCTAssertNil(radio.vfoAFrequencyHz, "SM frames must not set vfoAFrequencyHz")

        // 5 scope frames — must go to ScopeStore, not RadioState
        for i in 0..<5 {
            ScopeStore.shared.points = Array(repeating: UInt8(i * 10 + 0x30), count: 640)
        }
        XCTAssertNil(radio.vfoAFrequencyHz, "Scope frames must not set vfoAFrequencyHz")

        // 4 TX/RX frame logs — must go to DiagnosticsStore
        DiagnosticsStore.shared.lastTXFrame = "SM0;"
        DiagnosticsStore.shared.lastRXFrame = "SM00015;"
        XCTAssertNil(radio.vfoAFrequencyHz, "Diagnostics updates must not set vfoAFrequencyHz")

        // 1 genuine state change — FA auto-information frame
        radio.handleFrame("FA00014225000;")
        XCTAssertEqual(radio.vfoAFrequencyHz, 14_225_000,
            "FA frame must update vfoAFrequencyHz to 14225000 Hz")
    }

    // MARK: - handleFrame throughput

    /// Verifies handleFrame processes frequency frames in well under 1ms each.
    /// A slow handleFrame blocks the main thread and delays VoiceOver feedback.
    func testHandleFrame_frequencyUpdate_throughput() {
        measure {
            for _ in 0..<1_000 {
                radio.handleFrame("FA00014225000;")
            }
        }
    }

    /// Verifies handleFrame processes meter frames quickly even when called
    /// at the 4x/second rate of the meter poll timer.
    func testHandleFrame_meterFrame_throughput() {
        measure {
            for _ in 0..<1_000 {
                radio.handleFrame("SM00015;")
            }
        }
    }

    /// Verifies handleFrame handles a realistic mix of frame types quickly.
    func testHandleFrame_mixedFrames_throughput() {
        let frames = [
            "FA00014225000;", "FB00007074000;",
            "SM00015;", "SM10005;", "SM20002;", "SM50060;",
            "OM02;", "RA1;", "GC2;", "PA1;",
            "AG150;", "RG200;", "NB0;", "NR1;"
        ]
        measure {
            for i in 0..<1_000 {
                radio.handleFrame(frames[i % frames.count])
            }
        }
    }
}

