import XCTest
@testable import Kenwood_control

/// Tests for RadioState digital mode configure / revert behaviour.
///
/// No live radio or TCP connection is needed. RadioState.send() appends
/// every command to DiagnosticsStore.shared.txLog synchronously, so we
/// can inspect exactly which CAT commands were sent and in what order.
final class RadioStateDigitalModeTests: XCTestCase {

    var radio: RadioState!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "tx_audio_source")
        radio = RadioState()
        DiagnosticsStore.shared.txLog = []
    }

    override func tearDown() {
        radio = nil
        DiagnosticsStore.shared.txLog = []
        super.tearDown()
    }

    private var sentCommands: [String] { DiagnosticsStore.shared.txLog }

    // MARK: - Initial state

    func testIsConfiguredForDigitalMode_startsAsFalse() {
        XCTAssertFalse(radio.isConfiguredForDigitalMode)
    }

    // MARK: - configureForDigitalMode

    func testConfigure_setsIsConfiguredForDigitalModeTrue() {
        radio.configureForDigitalMode()
        XCTAssertTrue(radio.isConfiguredForDigitalMode)
    }

    func testConfigure_sendsUsbDataModeCommand() {
        radio.configureForDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM0D;"),
                      "Expected OM0D; (USB-DATA mode) in sent commands, got \(sentCommands)")
    }

    func testConfigure_sendsUsbAudioSourceCommand() {
        radio.configureForDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "Expected MS002; (Rear=USB Audio) in sent commands, got \(sentCommands)")
    }

    func testConfigure_sendsUsbDataBeforeUsbAudio() {
        radio.configureForDigitalMode()
        guard let omIndex = sentCommands.firstIndex(of: "OM0D;"),
              let msIndex = sentCommands.firstIndex(of: "MS002;") else {
            XCTFail("Expected both OM0D; and MS002; in sent commands, got \(sentCommands)")
            return
        }
        XCTAssertLessThan(omIndex, msIndex, "OM0D; should be sent before MS002;")
    }

    // MARK: - revertFromDigitalMode

    func testRevert_clearsIsConfiguredForDigitalMode() {
        radio.configureForDigitalMode()
        radio.revertFromDigitalMode()
        XCTAssertFalse(radio.isConfiguredForDigitalMode)
    }

    func testRevert_sendsMicrophoneSourceCommand() {
        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS010;"),
                      "Expected MS010; (Front=Microphone) in revert commands, got \(sentCommands)")
    }

    func testRevert_withNoPreviousMode_defaultsToUSB() {
        // operatingMode is nil at startup — revert should default to USB (OM02;)
        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM02;"),
                      "Expected OM02; (USB mode default) in revert commands, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_FM() {
        radio.handleFrame("OM04;")   // FM mode
        XCTAssertEqual(radio.operatingMode, .fm)

        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM04;"),
                      "Expected OM04; (FM) restored after revert, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_LSB() {
        radio.handleFrame("OM01;")   // LSB
        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM01;"),
                      "Expected OM01; (LSB) restored, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_CW() {
        radio.handleFrame("OM03;")   // CW
        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM03;"),
                      "Expected OM03; (CW) restored, got \(sentCommands)")
    }

    // MARK: - Configure → revert → configure cycle

    func testConfigureRevertCycle_canBeCalledMultipleTimes() {
        radio.handleFrame("OM02;")   // USB

        radio.configureForDigitalMode()
        XCTAssertTrue(radio.isConfiguredForDigitalMode)

        radio.revertFromDigitalMode()
        XCTAssertFalse(radio.isConfiguredForDigitalMode)

        // Second cycle with a different mode
        radio.handleFrame("OM04;")
        radio.configureForDigitalMode()
        XCTAssertTrue(radio.isConfiguredForDigitalMode)

        DiagnosticsStore.shared.txLog = []
        radio.revertFromDigitalMode()
        XCTAssertFalse(radio.isConfiguredForDigitalMode)
        XCTAssertTrue(sentCommands.contains("OM04;"),
                      "Second revert should restore FM, got \(sentCommands)")
    }

    // MARK: - Digital mode CAT command constants (regression guards)

    func testDigitalModeCATCommands_usbDataModeIsD() {
        // P2=D is USB-DATA per the TS-890S PC Command Reference (page 51).
        radio.configureForDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM0D;"),
                      "USB-DATA mode must use P2=D per TS-890S command reference")
    }

    func testDigitalModeCATCommands_usbAudioSourceIsMS002() {
        // MS: P1=0 (SEND/PTT), P2=0 (Front=OFF), P3=2 (Rear=USB Audio)
        radio.configureForDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "USB audio source must be MS002 per TS-890S command reference")
    }

    func testRevertCATCommands_microphoneSourceIsMS010() {
        // MS: P1=0 (SEND/PTT), P2=1 (Front=Microphone), P3=0 (Rear=OFF)
        radio.configureForDigitalMode()
        DiagnosticsStore.shared.txLog = []
        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS010;"),
                      "Microphone source must be MS010 per TS-890S command reference")
    }
}

// MARK: - User-interaction CAT command tests

/// Tests that verify the correct CAT commands are sent when user-initiated
/// actions (button presses, cycle controls) are invoked on RadioState.
final class RadioStateUserActionTests: XCTestCase {

    var radio: RadioState!
    private var sentCommands: [String] { DiagnosticsStore.shared.txLog }

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

    // MARK: - Preamp cycle (PRE button)

    func testCyclePreamp_fromOff_sendsPRE1() {
        radio.handleFrame("PA0;")  // radio reports off
        DiagnosticsStore.shared.txLog = []
        radio.cyclePreampLevel()
        XCTAssertTrue(sentCommands.contains("PA1;"), "Cycle from Off should send PA1; (PRE1), got \(sentCommands)")
    }

    func testCyclePreamp_fromPRE1_sendsPRE2() {
        radio.handleFrame("PA1;")  // radio reports PRE1
        DiagnosticsStore.shared.txLog = []
        radio.cyclePreampLevel()
        XCTAssertTrue(sentCommands.contains("PA2;"), "Cycle from PRE1 should send PA2; (PRE2), got \(sentCommands)")
    }

    func testCyclePreamp_fromPRE2_sendsOff() {
        radio.handleFrame("PA2;")  // radio reports PRE2
        DiagnosticsStore.shared.txLog = []
        radio.cyclePreampLevel()
        XCTAssertTrue(sentCommands.contains("PA0;"), "Cycle from PRE2 should send PA0; (Off), got \(sentCommands)")
    }

    func testCyclePreamp_updatesLocalStateImmediately() {
        radio.handleFrame("PA0;")
        radio.cyclePreampLevel()
        XCTAssertEqual(radio.preampLevel, .pre1, "preampLevel should update optimistically before radio confirms")
    }

    // MARK: - Beat cancel cycle (BC button)

    func testCycleBC_fromOff_sendsBC1() {
        radio.handleFrame("BC0;")
        DiagnosticsStore.shared.txLog = []
        radio.cycleBeatCancelMode()
        XCTAssertTrue(sentCommands.contains("BC1;"), "Cycle from Off should send BC1;, got \(sentCommands)")
    }

    func testCycleBC_fromBC1_sendsBC2() {
        radio.handleFrame("BC1;")
        DiagnosticsStore.shared.txLog = []
        radio.cycleBeatCancelMode()
        XCTAssertTrue(sentCommands.contains("BC2;"), "Cycle from BC1 should send BC2;, got \(sentCommands)")
    }

    func testCycleBC_fromBC2_sendsOff() {
        radio.handleFrame("BC2;")
        DiagnosticsStore.shared.txLog = []
        radio.cycleBeatCancelMode()
        XCTAssertTrue(sentCommands.contains("BC0;"), "Cycle from BC2 should send BC0; (Off), got \(sentCommands)")
    }

    func testCycleBC_updatesLocalStateImmediately() {
        radio.handleFrame("BC0;")
        radio.cycleBeatCancelMode()
        XCTAssertEqual(radio.beatCancelMode, .bc1, "beatCancelMode should update optimistically before radio confirms")
    }

    // MARK: - Attenuator cycle (ATT button — regression guard)

    func testCycleATT_fromOff_sends6dB() {
        radio.handleFrame("RA0;")
        DiagnosticsStore.shared.txLog = []
        radio.cycleAttenuatorLevel()
        XCTAssertTrue(sentCommands.contains("RA1;"), "Cycle ATT from Off should send RA1; (6dB), got \(sentCommands)")
    }

    func testCycleATT_from18dB_sendsOff() {
        radio.handleFrame("RA3;")
        DiagnosticsStore.shared.txLog = []
        radio.cycleAttenuatorLevel()
        XCTAssertTrue(sentCommands.contains("RA0;"), "Cycle ATT from 18dB should send RA0; (Off), got \(sentCommands)")
    }

    // MARK: - setPreampLevel direct set (context menu / right-click)

    func testSetPreampLevel_directlyToPRE2_sendsPRE2() {
        radio.setPreampLevel(.pre2)
        XCTAssertTrue(sentCommands.contains("PA2;"), "Direct set to PRE2 should send PA2;, got \(sentCommands)")
        XCTAssertEqual(radio.preampLevel, .pre2)
    }

    func testSetBeatCancelMode_directlyToBC2_sendsBC2() {
        radio.setBeatCancelMode(.bc2)
        XCTAssertTrue(sentCommands.contains("BC2;"), "Direct set to BC2 should send BC2;, got \(sentCommands)")
        XCTAssertEqual(radio.beatCancelMode, .bc2)
    }
}
