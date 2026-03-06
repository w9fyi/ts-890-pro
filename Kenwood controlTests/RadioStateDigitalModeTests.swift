import XCTest
import Combine
@testable import Kenwood_control

/// Tests for RadioState digital mode configure / revert behaviour.
///
/// No live radio or TCP connection is needed. RadioState.send() sets
/// `lastTXFrame` synchronously before dispatching to the transport,
/// so we can observe the CAT commands that would be sent by subscribing
/// to `$lastTXFrame` via Combine.
final class RadioStateDigitalModeTests: XCTestCase {

    var radio: RadioState!
    var sentCommands: [String] = []
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        radio = RadioState()
        sentCommands = []
        // $lastTXFrame emits the current value immediately on subscribe (dropFirst skips it),
        // then emits synchronously on each subsequent assignment in send().
        radio.$lastTXFrame
            .dropFirst()
            .filter { !$0.isEmpty }
            .sink { [weak self] cmd in self?.sentCommands.append(cmd) }
            .store(in: &cancellables)
    }

    override func tearDown() {
        cancellables.removeAll()
        radio = nil
        sentCommands = []
        super.tearDown()
    }

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
        sentCommands.removeAll()

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS001;"),
                      "Expected MS001; (Front=Microphone) in revert commands, got \(sentCommands)")
    }

    func testRevert_withNoPreviousMode_defaultsToUSB() {
        // operatingMode is nil at startup — revert should default to USB (OM02;)
        radio.configureForDigitalMode()
        sentCommands.removeAll()

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM02;"),
                      "Expected OM02; (USB mode default) in revert commands, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_FM() {
        radio.handleFrame("OM04;")   // FM mode
        XCTAssertEqual(radio.operatingMode, .fm)

        radio.configureForDigitalMode()
        sentCommands.removeAll()

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM04;"),
                      "Expected OM04; (FM) restored after revert, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_LSB() {
        radio.handleFrame("OM01;")   // LSB
        radio.configureForDigitalMode()
        sentCommands.removeAll()

        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("OM01;"),
                      "Expected OM01; (LSB) restored, got \(sentCommands)")
    }

    func testRevert_restoresPreviousOperatingMode_CW() {
        radio.handleFrame("OM03;")   // CW
        radio.configureForDigitalMode()
        sentCommands.removeAll()

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

        sentCommands.removeAll()
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

    func testRevertCATCommands_microphoneSourceIsMS001() {
        // MS: P1=0 (SEND/PTT), P2=1 (Front=Microphone), P3=0 (Rear=OFF)
        radio.configureForDigitalMode()
        sentCommands.removeAll()
        radio.revertFromDigitalMode()
        XCTAssertTrue(sentCommands.contains("MS001;"),
                      "Microphone source must be MS001 per TS-890S command reference")
    }
}
