import XCTest
@testable import Kenwood_control

/// Tests for RadioState TX audio source management.
///
/// No live radio or TCP connection is needed. RadioState.send() appends
/// every command to DiagnosticsStore.shared.txLog synchronously, so we
/// can inspect exactly which CAT commands were sent and in what order.
final class RadioStateTXAudioTests: XCTestCase {

    var radio: RadioState!

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

    private var sentCommands: [String] { DiagnosticsStore.shared.txLog }

    // MARK: - Initial state

    func testTXAudioSource_defaultsToHardware() {
        XCTAssertEqual(radio.txAudioSource, .hardware,
                       "TX audio source should default to .hardware (front panel mic)")
    }

    func testIsTXPassthroughRunning_defaultsFalse() {
        XCTAssertFalse(radio.isTXPassthroughRunning,
                       "TX passthrough should not be running at init")
    }

    func testTXPassthroughError_defaultsNil() {
        XCTAssertNil(radio.txPassthroughError,
                     "TX passthrough error should be nil at init")
    }

    func testSelectedTXMicInputUID_defaultsEmpty() {
        XCTAssertEqual(radio.selectedTXMicInputUID, "",
                       "selectedTXMicInputUID should default to empty string")
    }

    func testSelectedTXCodecOutputUID_defaultsEmpty() {
        XCTAssertEqual(radio.selectedTXCodecOutputUID, "",
                       "selectedTXCodecOutputUID should default to empty string")
    }

    // MARK: - setTXAudioSource(.hardware)

    func testSetHardware_updatesTXAudioSource() {
        radio.setTXAudioSource(.usbPassthrough)
        DiagnosticsStore.shared.txLog = []

        radio.setTXAudioSource(.hardware)
        XCTAssertEqual(radio.txAudioSource, .hardware)
    }

    func testSetHardware_sendsMS001() {
        radio.setTXAudioSource(.hardware)
        XCTAssertTrue(sentCommands.contains("MS001;"),
                      "Switching to hardware mic must send MS001;, got \(sentCommands)")
    }

    func testSetHardware_doesNotSendMS002() {
        radio.setTXAudioSource(.hardware)
        XCTAssertFalse(sentCommands.contains("MS002;"),
                       "Switching to hardware mic must not send MS002;, got \(sentCommands)")
    }

    func testSetHardware_stopsTXPassthrough() {
        // Passthrough won't actually start without devices, but the running
        // flag should not be set after switching back to hardware.
        radio.setTXAudioSource(.hardware)
        XCTAssertFalse(radio.isTXPassthroughRunning,
                       "isTXPassthroughRunning should be false after switching to hardware")
    }

    // MARK: - setTXAudioSource(.usbPassthrough)

    func testSetUSBPassthrough_updatesTXAudioSource() {
        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertEqual(radio.txAudioSource, .usbPassthrough)
    }

    func testSetUSBPassthrough_sendsMS002() {
        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "Switching to USB passthrough must send MS002;, got \(sentCommands)")
    }

    func testSetUSBPassthrough_doesNotSendMS001() {
        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertFalse(sentCommands.contains("MS001;"),
                       "Switching to USB passthrough must not send MS001;, got \(sentCommands)")
    }

    func testSetUSBPassthrough_MS002SentBeforeAttemptingStart() {
        // MS002 must reach the radio before any passthrough starts, so it
        // must appear in the command log even if start fails (no devices).
        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "MS002; must be sent regardless of whether audio devices are available")
    }

    // MARK: - Hardware → passthrough → hardware round-trip

    func testRoundTrip_hardwareToPassthroughToHardware_sourceTracksCorrectly() {
        XCTAssertEqual(radio.txAudioSource, .hardware)

        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertEqual(radio.txAudioSource, .usbPassthrough)

        radio.setTXAudioSource(.hardware)
        XCTAssertEqual(radio.txAudioSource, .hardware)
    }

    func testRoundTrip_commandSequence() {
        radio.setTXAudioSource(.usbPassthrough)
        radio.setTXAudioSource(.hardware)

        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "MS002; should appear in round-trip command log")
        XCTAssertTrue(sentCommands.contains("MS001;"),
                      "MS001; should appear in round-trip command log")

        // MS002 before MS001 — passthrough was activated before revert
        guard let ms002idx = sentCommands.firstIndex(of: "MS002;"),
              let ms001idx = sentCommands.firstIndex(of: "MS001;") else {
            XCTFail("Both MS002; and MS001; must be in the command log")
            return
        }
        XCTAssertLessThan(ms002idx, ms001idx,
                          "MS002; (USB audio on) should appear before MS001; (mic restore)")
    }

    // MARK: - stopTXPassthrough idempotency

    func testStopTXPassthrough_whenAlreadyStopped_doesNotCrash() {
        // Should be safe to call stop when nothing is running.
        XCTAssertNoThrow(radio.stopTXPassthrough())
        XCTAssertFalse(radio.isTXPassthroughRunning)
    }

    func testStopTXPassthrough_calledTwice_doesNotCrash() {
        radio.stopTXPassthrough()
        radio.stopTXPassthrough()
        XCTAssertFalse(radio.isTXPassthroughRunning)
    }

    // MARK: - startTXPassthrough without devices

    func testStartTXPassthrough_withNoDeviceUID_setsErrorAndDoesNotStart() {
        // With empty selectedTXMicInputUID and selectedTXCodecOutputUID,
        // startTXPassthrough must set an error and leave passthrough stopped.
        // Explicit UIDs are required — no fallback to system defaults.
        radio.setTXAudioSource(.usbPassthrough)  // sets source without starting (UIDs empty)
        radio.startTXPassthrough()
        XCTAssertFalse(radio.isTXPassthroughRunning,
                       "Passthrough must not start without explicit device UIDs")
        XCTAssertNotNil(radio.txPassthroughError,
                        "An error message must be set when device UIDs are not configured")
    }

    func testStartTXPassthrough_whenSourceIsHardware_doesNotStart() {
        // startTXPassthrough() is a no-op if txAudioSource == .hardware.
        radio.setTXAudioSource(.hardware)
        DiagnosticsStore.shared.txLog = []

        radio.startTXPassthrough()
        XCTAssertFalse(radio.isTXPassthroughRunning,
                       "Passthrough must not start when source is .hardware")
        XCTAssertFalse(sentCommands.contains("MS002;"),
                       "No MS002; should be sent by startTXPassthrough when source is .hardware")
    }

    // MARK: - CAT command constant regression guards

    func testMS001_isCorrectCATCommand() {
        // MS: P1=0 (SEND/PTT), P2=1 (Front=Microphone), P3=0 (Rear=OFF)
        radio.setTXAudioSource(.hardware)
        XCTAssertTrue(sentCommands.contains("MS001;"),
                      "Front panel mic command must be MS001; per TS-890S command reference")
    }

    func testMS002_isCorrectCATCommand() {
        // MS: P1=0 (SEND/PTT), P2=0 (Front=OFF), P3=2 (Rear=USB Audio)
        radio.setTXAudioSource(.usbPassthrough)
        XCTAssertTrue(sentCommands.contains("MS002;"),
                      "USB audio command must be MS002; per TS-890S command reference")
    }
}
