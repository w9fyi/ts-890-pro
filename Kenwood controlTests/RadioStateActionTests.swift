import XCTest
@testable import Kenwood_control

/// Tests that RadioState action methods send the correct CAT wire strings.
///
/// These tests use MockCATTransport to capture every string passed to
/// RadioState.send() without a live radio connection.  They verify the
/// full call chain: action method → KenwoodCAT builder → transport.send().
///
/// setUp() installs the mock transport and calls reset() before each test
/// so the sent log is always clean.
final class RadioStateActionTests: XCTestCase {
    nonisolated deinit {}

    var radio: RadioState!
    var mock: MockCATTransport!

    override func setUp() {
        super.setUp()
        radio = RadioState()
        mock  = MockCATTransport()
        radio._setConnectionForTesting(mock)
        mock.reset()   // discard any sends from RadioState.init
    }

    override func tearDown() {
        radio = nil
        mock  = nil
        super.tearDown()
    }

    // MARK: - Noise Blanker (existing action methods)

    func testSetNoiseBlankerEnabled_true() {
        radio.setNoiseBlankerEnabled(true)
        XCTAssertEqual(mock.sent.last, "NB11;")
    }

    func testSetNoiseBlankerEnabled_false() {
        radio.setNoiseBlankerEnabled(false)
        XCTAssertEqual(mock.sent.last, "NB10;")
    }

    // MARK: - Beat Cancel

    func testSetBeatCancelMode_bc1() {
        radio.setBeatCancelMode(.bc1)
        XCTAssertEqual(mock.sent.last, "BC1;")
    }

    func testSetBeatCancelMode_off() {
        radio.setBeatCancelMode(.off)
        XCTAssertEqual(mock.sent.last, "BC0;")
    }

    func testCycleBeatCancelMode_fromOff_sendBC1() {
        radio.beatCancelMode = .off
        radio.cycleBeatCancelMode()
        XCTAssertEqual(mock.sent.last, "BC1;")
    }

    // MARK: - Mic Gain

    func testSetMicGain_50() {
        radio.setMicGain(50)
        XCTAssertEqual(mock.sent.last, "MG050;")
    }

    func testSetMicGain_clampsAbove100() {
        radio.setMicGain(200)
        XCTAssertEqual(mock.sent.last, "MG100;")
    }

    func testSetMicGain_clampsBelow0() {
        radio.setMicGain(-5)
        XCTAssertEqual(mock.sent.last, "MG000;")
    }

    // MARK: - CW Break-in mode

    func testSetCWBreakInMode_on() {
        radio.setCWBreakInMode(.on)
        XCTAssertEqual(mock.sent.last, "BI1;")
    }

    func testSetCWBreakInMode_off() {
        radio.setCWBreakInMode(.off)
        XCTAssertEqual(mock.sent.last, "BI0;")
    }

    // MARK: - Notch enable (existing)

    func testSetNotchEnabled_true() {
        radio.setNotchEnabled(true)
        // setNotchEnabled sends set + immediate readback: ["NT1;", "NT;"]
        XCTAssertEqual(mock.sent.suffix(2).first, "NT1;")
        XCTAssertEqual(mock.sent.last, "NT;")
    }

    func testSetNotchEnabled_false() {
        radio.setNotchEnabled(false)
        XCTAssertEqual(mock.sent.suffix(2).first, "NT0;")
        XCTAssertEqual(mock.sent.last, "NT;")
    }

    // MARK: - MockCATTransport round-trip (injectFrame → handleFrame → property)

    func testMockInjectFrame_updatesProperty() {
        // Verify injectFrame drives handleFrame correctly so future round-trip
        // tests can rely on this infrastructure.
        mock.onFrame = { [weak radio] frame in
            radio?.handleFrame(frame)
        }
        mock.injectFrame("NB20")
        XCTAssertEqual(radio.noiseBlanker2Enabled, false)
        mock.injectFrame("NB21")
        XCTAssertEqual(radio.noiseBlanker2Enabled, true)
    }

    // MARK: - send() captures in order

    func testSentLog_capturesMultipleSends() {
        radio.setNoiseBlankerEnabled(true)
        radio.setBeatCancelMode(.bc2)
        XCTAssertEqual(mock.sent.suffix(2), ["NB11;", "BC2;"])
    }

    func testMockReset_clearsLog() {
        radio.setNoiseBlankerEnabled(true)
        mock.reset()
        XCTAssertTrue(mock.sent.isEmpty)
    }
}
