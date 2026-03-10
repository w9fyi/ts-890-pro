import XCTest
@testable import Kenwood_control

// MARK: - FT8 slot-parity tests

/// Verifies that `oppositeParityFor` always returns the parity OPPOSITE to the slot
/// the decoded station occupied, regardless of early/late decode timing.
///
/// FT8 slots within each UTC minute:
///   Slot 0 (even):  0 – 14 s  → decode fires at ~15.6 s
///   Slot 1 (odd):  15 – 29 s  → decode fires at ~30.6 s
///   Slot 2 (even): 30 – 44 s  → decode fires at ~45.6 s
///   Slot 3 (odd):  45 – 59 s  → decode fires at ~60.6 s
///
/// We use T_min = 1735689600 (2025-01-01 00:00:00 UTC), which is divisible by 60,
/// as the reference minute boundary.
final class FT8ParityTests: XCTestCase {

    // T_min is divisible by 60 so all slot offsets are unambiguous.
    private let tMin: TimeInterval = 1_735_689_600

    private func msg(offset: TimeInterval) -> FT8ViewModel.DecodedMessage {
        FT8ViewModel.DecodedMessage(
            receivedAt: Date(timeIntervalSince1970: tMin + offset),
            raw: "TEST", caller: "W1AW", to: "AI5OS",
            payload: "-10", isDirectedToMe: true
        )
    }

    private let vm = FT8ViewModel()

    // Slot 0 (even) decode fires 0.6 s after slot ends (T+15.6)
    func testSlot0Even_returnsOdd() {
        let result = vm.oppositeParityFor(msg(offset: 15.6))
        XCTAssertEqual(result, .odd, "Caller in slot 0 (even) → we should reply on odd")
    }

    // Slot 1 (odd) decode fires at T+30.6
    func testSlot1Odd_returnsEven() {
        let result = vm.oppositeParityFor(msg(offset: 30.6))
        XCTAssertEqual(result, .even, "Caller in slot 1 (odd) → we should reply on even")
    }

    // Slot 2 (even) decode fires at T+45.6
    func testSlot2Even_returnsOdd() {
        let result = vm.oppositeParityFor(msg(offset: 45.6))
        XCTAssertEqual(result, .odd, "Caller in slot 2 (even) → we should reply on odd")
    }

    // Slot 3 (odd) decode fires at T+60.6 (just into the next minute)
    func testSlot3Odd_returnsEven() {
        let result = vm.oppositeParityFor(msg(offset: 60.6))
        XCTAssertEqual(result, .even, "Caller in slot 3 (odd) → we should reply on even")
    }

    // Decode fires "late" — 1.5 s after slot end (still in the same slot with -7.5 offset)
    func testSlot0Even_lateDecodeStillReturnsOdd() {
        let result = vm.oppositeParityFor(msg(offset: 16.5))
        XCTAssertEqual(result, .odd, "Late slot-0 decode should still attribute to slot 0")
    }

    // Decode fires right at the slot boundary (0.01 s after end) — edge case
    func testSlot1Odd_earlyDecodeReturnsEven() {
        let result = vm.oppositeParityFor(msg(offset: 30.01))
        XCTAssertEqual(result, .even, "Early slot-1 decode should still attribute to slot 1")
    }
}

// MARK: - NR state machine tests

/// Verifies the unified NR button state machine:
///   - hardware mode cycles NR0 → NR1 → NR2 → NR0 via CAT
///   - software mode cycles Off → ANR → EMNR → Off in-app (no hardware NR CAT)
///   - backend switch preserves isNoiseReductionEnabled
///   - nrButtonLabel / nrButtonIsActive reflect state correctly
final class NRStateMachineTests: XCTestCase {

    var radio: RadioState!
    private var sent: [String] { DiagnosticsStore.shared.txLog }

    override func setUp() {
        super.setUp()
        radio = RadioState()
        DiagnosticsStore.shared.txLog = []
    }

    override func tearDown() {
        radio = nil
        DiagnosticsStore.shared.txLog = []
        super.tearDown()
    }

    // MARK: Default state

    func testDefaultMode_isHardware() {
        XCTAssertEqual(radio.nrButtonMode, .hardware)
    }

    func testDefaultLabel_isNROff() {
        XCTAssertEqual(radio.nrButtonLabel, "NR: Off")
    }

    func testDefaultActive_isFalse() {
        XCTAssertFalse(radio.nrButtonIsActive)
    }

    // MARK: Hardware mode cycling

    func testHardwareCycle_offToNR1() {
        radio.transceiverNRMode = .off
        radio.cycleNRFrontPanel()
        XCTAssertTrue(sent.contains("NR1;"), "First cycle should send NR1")
    }

    func testHardwareCycle_NR1ToNR2() {
        radio.transceiverNRMode = .nr1
        radio.cycleNRFrontPanel()
        XCTAssertTrue(sent.contains("NR2;"), "Second cycle should send NR2")
    }

    func testHardwareCycle_NR2ToOff() {
        radio.transceiverNRMode = .nr2
        radio.cycleNRFrontPanel()
        XCTAssertTrue(sent.contains("NR0;"), "Third cycle should send NR0")
    }

    func testHardwareLabel_NR1() {
        radio.transceiverNRMode = .nr1
        XCTAssertEqual(radio.nrButtonLabel, "NR1")
        XCTAssertTrue(radio.nrButtonIsActive)
    }

    func testHardwareLabel_NR2() {
        radio.transceiverNRMode = .nr2
        XCTAssertEqual(radio.nrButtonLabel, "NR2")
        XCTAssertTrue(radio.nrButtonIsActive)
    }

    // MARK: Software mode cycling

    func testSoftwareCycle_offToANR() {
        radio.nrButtonMode = .software
        radio.softwareNRState = .off
        radio.cycleNRFrontPanel()
        XCTAssertEqual(radio.softwareNRState, .anr)
        XCTAssertEqual(radio.nrButtonLabel, "ANR")
        XCTAssertTrue(radio.nrButtonIsActive)
    }

    func testSoftwareCycle_ANRToEMNR() {
        radio.nrButtonMode = .software
        radio.softwareNRState = .anr
        radio.cycleNRFrontPanel()
        XCTAssertEqual(radio.softwareNRState, .emnr)
        XCTAssertEqual(radio.nrButtonLabel, "EMNR")
    }

    func testSoftwareCycle_EMNRToOff() {
        radio.nrButtonMode = .software
        radio.softwareNRState = .emnr
        radio.cycleNRFrontPanel()
        XCTAssertEqual(radio.softwareNRState, .off)
        XCTAssertEqual(radio.nrButtonLabel, "NR: Off")
        XCTAssertFalse(radio.nrButtonIsActive)
    }

    func testSoftwareMode_doesNotSendHardwareNRCommands() {
        radio.nrButtonMode = .software
        radio.softwareNRState = .off
        radio.cycleNRFrontPanel()  // → ANR
        XCTAssertFalse(sent.contains("NR1;"), "Software NR cycle must not send hardware NR1")
        XCTAssertFalse(sent.contains("NR2;"), "Software NR cycle must not send hardware NR2")
    }

    // MARK: Backend switch preserves enabled state

    func testBackendSwitch_preservesEnabledTrue() {
        radio.setNoiseReduction(enabled: true)
        XCTAssertTrue(radio.isNoiseReductionEnabled)
        radio.setNoiseReductionBackend("WDSP EMNR")
        XCTAssertTrue(radio.isNoiseReductionEnabled,
                      "Backend switch must not silently disable NR when it was on")
    }

    func testBackendSwitch_preservesEnabledFalse() {
        radio.setNoiseReduction(enabled: false)
        radio.setNoiseReductionBackend("WDSP ANR")
        XCTAssertFalse(radio.isNoiseReductionEnabled,
                       "Backend switch must not silently enable NR when it was off")
    }
}

// MARK: - Filter slot restore tests

/// Verifies per-slot filter state:
///   - setFilterSlot sends FL0n;
///   - When a slot is in .ifShift mode, switching to it sends the stored IS value
///   - When a slot is in .hiLoCut mode, no IS command is sent
///   - filterSlotIFShiftHz is independently stored per slot
final class FilterSlotRestoreTests: XCTestCase {

    var radio: RadioState!
    private var sent: [String] { DiagnosticsStore.shared.txLog }

    override func setUp() {
        super.setUp()
        radio = RadioState()
        DiagnosticsStore.shared.txLog = []
    }

    override func tearDown() {
        radio = nil
        DiagnosticsStore.shared.txLog = []
        super.tearDown()
    }

    // MARK: Basic slot switching

    func testSetFilterSlot_A_sendsFL00() {
        radio.setFilterSlot(.a)
        XCTAssertTrue(sent.contains("FL00;"), "Selecting slot A should send FL00;")
    }

    func testSetFilterSlot_B_sendsFL01() {
        radio.setFilterSlot(.b)
        XCTAssertTrue(sent.contains("FL01;"), "Selecting slot B should send FL01;")
    }

    func testSetFilterSlot_C_sendsFL02() {
        radio.setFilterSlot(.c)
        XCTAssertTrue(sent.contains("FL02;"), "Selecting slot C should send FL02;")
    }

    // MARK: IS restore on slot switch

    func testIFShiftRestored_whenSlotIsInIFShiftMode() {
        // Configure slot B (.ifShift, +500 Hz)
        radio.filterSlotDisplayModes = [.hiLoCut, .ifShift, .hiLoCut]
        radio.filterSlotIFShiftHz    = [0, 500, 0]

        radio.setFilterSlot(.b)

        let isCmd = sent.first(where: { $0.hasPrefix("IS") })
        XCTAssertNotNil(isCmd, "Switching to slot B in ifShift mode must send an IS command")
        XCTAssertEqual(isCmd, "IS+0500;", "IS value should be +500 Hz for slot B")
    }

    func testIFShiftRestored_negativeHz() {
        radio.filterSlotDisplayModes = [.hiLoCut, .hiLoCut, .ifShift]
        radio.filterSlotIFShiftHz    = [0, 0, -200]

        radio.setFilterSlot(.c)

        let isCmd = sent.first(where: { $0.hasPrefix("IS") })
        XCTAssertEqual(isCmd, "IS-0200;", "IS value should be -200 Hz for slot C")
    }

    func testNoIFShiftSent_whenSlotIsInHiLoCutMode() {
        radio.filterSlotDisplayModes = [.hiLoCut, .hiLoCut, .hiLoCut]
        radio.filterSlotIFShiftHz    = [0, 400, 0]

        radio.setFilterSlot(.b)

        let isCmd = sent.first(where: { $0.hasPrefix("IS") })
        XCTAssertNil(isCmd, "Switching to a hiLoCut slot must NOT send an IS command")
    }

    // MARK: Per-slot independence

    func testFilterSlotIFShiftHz_isIndependentPerSlot() {
        radio.filterSlotIFShiftHz = [100, 200, 300]
        XCTAssertEqual(radio.filterSlotIFShiftHz[0], 100, "Slot A stored Hz should be 100")
        XCTAssertEqual(radio.filterSlotIFShiftHz[1], 200, "Slot B stored Hz should be 200")
        XCTAssertEqual(radio.filterSlotIFShiftHz[2], 300, "Slot C stored Hz should be 300")
    }

    func testFilterSlotDisplayModes_isIndependentPerSlot() {
        radio.filterSlotDisplayModes = [.ifShift, .hiLoCut, .ifShift]
        XCTAssertEqual(radio.filterSlotDisplayModes[0], .ifShift)
        XCTAssertEqual(radio.filterSlotDisplayModes[1], .hiLoCut)
        XCTAssertEqual(radio.filterSlotDisplayModes[2], .ifShift)
    }

    // MARK: Default state

    func testDefaultDisplayModes_areAllHiLoCut() {
        XCTAssertEqual(radio.filterSlotDisplayModes, [.hiLoCut, .hiLoCut, .hiLoCut])
    }

    func testDefaultIFShiftHz_areAllZero() {
        XCTAssertEqual(radio.filterSlotIFShiftHz, [0, 0, 0])
    }
}
