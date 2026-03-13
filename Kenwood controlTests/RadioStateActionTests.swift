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

    // MARK: - Batch 1: VFO swap / copy

    func testSwapVFOs_sendsEC() {
        radio.swapVFOs()
        XCTAssertEqual(mock.sent.last, "EC;")
    }

    func testCopyVFOAtoB_sendsVV() {
        radio.copyVFOAtoB()
        XCTAssertEqual(mock.sent.last, "VV;")
    }

    // MARK: - Batch 1: Lock / Mute

    func testSetLocked_true()  { radio.setLocked(true);  XCTAssertEqual(mock.sent.last, "LK1;") }
    func testSetLocked_false() { radio.setLocked(false); XCTAssertEqual(mock.sent.last, "LK0;") }

    func testSetMuted_true()   { radio.setMuted(true);   XCTAssertEqual(mock.sent.last, "MU1;") }
    func testSetMuted_false()  { radio.setMuted(false);  XCTAssertEqual(mock.sent.last, "MU0;") }

    func testSetSpeakerMuted_true()  { radio.setSpeakerMuted(true);  XCTAssertEqual(mock.sent.last, "QS1;") }
    func testSetSpeakerMuted_false() { radio.setSpeakerMuted(false); XCTAssertEqual(mock.sent.last, "QS0;") }

    // local state updated
    func testSetLocked_updatesProperty() {
        radio.setLocked(true)
        XCTAssertEqual(radio.isLocked, true)
    }

    // MARK: - Batch 1: Monitor ON/OFF

    func testSetTXMonitorEnabled_on()  { radio.setTXMonitorEnabled(true);  XCTAssertEqual(mock.sent.last, "MO01;") }
    func testSetTXMonitorEnabled_off() { radio.setTXMonitorEnabled(false); XCTAssertEqual(mock.sent.last, "MO00;") }

    func testSetRXMonitorEnabled_on()  { radio.setRXMonitorEnabled(true);  XCTAssertEqual(mock.sent.last, "MO11;") }
    func testSetRXMonitorEnabled_off() { radio.setRXMonitorEnabled(false); XCTAssertEqual(mock.sent.last, "MO10;") }

    func testSetDSPMonitorEnabled_on()  { radio.setDSPMonitorEnabled(true);  XCTAssertEqual(mock.sent.last, "MO21;") }
    func testSetDSPMonitorEnabled_off() { radio.setDSPMonitorEnabled(false); XCTAssertEqual(mock.sent.last, "MO20;") }

    // MARK: - Batch 1: CW extended

    func testSetCWAutotuneActive_on()  { radio.setCWAutotuneActive(true);  XCTAssertEqual(mock.sent.last, "CA1;") }
    func testSetCWAutotuneActive_off() { radio.setCWAutotuneActive(false); XCTAssertEqual(mock.sent.last, "CA0;") }

    func testSetCWPitchHz_700() {
        radio.setCWPitchHz(700)
        XCTAssertEqual(mock.sent.last, "PT080;")
        XCTAssertEqual(radio.cwPitchHz, 700)
    }

    func testSetCWPitchHz_clampsLow() {
        radio.setCWPitchHz(0)
        XCTAssertEqual(mock.sent.last, "PT000;")
        XCTAssertEqual(radio.cwPitchHz, 300)
    }

    func testSetCWPitchHz_clampsHigh() {
        radio.setCWPitchHz(9999)
        XCTAssertEqual(mock.sent.last, "PT160;")
        XCTAssertEqual(radio.cwPitchHz, 1100)
    }

    func testSetCWBreakInDelayMs_500() {
        radio.setCWBreakInDelayMs(500)
        XCTAssertEqual(mock.sent.last, "SD0500;")
        XCTAssertEqual(radio.cwBreakInDelayMs, 500)
    }

    func testSetCWBreakInDelayMs_clampsHigh() {
        radio.setCWBreakInDelayMs(9999)
        XCTAssertEqual(mock.sent.last, "SD1000;")
        XCTAssertEqual(radio.cwBreakInDelayMs, 1000)
    }

    // MARK: - Batch 1: NB2 suite

    func testSetNoiseBlanker2Enabled_on()  { radio.setNoiseBlanker2Enabled(true);  XCTAssertEqual(mock.sent.last, "NB21;") }
    func testSetNoiseBlanker2Enabled_off() { radio.setNoiseBlanker2Enabled(false); XCTAssertEqual(mock.sent.last, "NB20;") }

    func testSetNoiseBlanker2Type_typeA() {
        radio.setNoiseBlanker2Type(.typeA)
        XCTAssertEqual(mock.sent.last, "NBT0;")
        XCTAssertEqual(radio.noiseBlanker2Type, .typeA)
    }

    func testSetNoiseBlanker2Type_typeB() {
        radio.setNoiseBlanker2Type(.typeB)
        XCTAssertEqual(mock.sent.last, "NBT1;")
    }

    func testSetNoiseBlanker1Level_10() {
        radio.setNoiseBlanker1Level(10)
        XCTAssertEqual(mock.sent.last, "NL1010;")
        XCTAssertEqual(radio.noiseBlanker1Level, 10)
    }

    func testSetNoiseBlanker1Level_clampsLow() {
        radio.setNoiseBlanker1Level(0)
        XCTAssertEqual(mock.sent.last, "NL1001;")
    }

    func testSetNoiseBlanker1Level_clampsHigh() {
        radio.setNoiseBlanker1Level(99)
        XCTAssertEqual(mock.sent.last, "NL1020;")
    }

    func testSetNoiseBlanker2Level_5() {
        radio.setNoiseBlanker2Level(5)
        XCTAssertEqual(mock.sent.last, "NL2005;")
        XCTAssertEqual(radio.noiseBlanker2Level, 5)
    }

    func testSetNoiseBlanker2Level_clampsHigh() {
        radio.setNoiseBlanker2Level(99)
        XCTAssertEqual(mock.sent.last, "NL2010;")
    }

    func testSetNoiseBlanker2Depth_10() {
        radio.setNoiseBlanker2Depth(10)
        XCTAssertEqual(mock.sent.last, "NBD010;")
        XCTAssertEqual(radio.noiseBlanker2Depth, 10)
    }

    func testSetNoiseBlanker2Width_5() {
        radio.setNoiseBlanker2Width(5)
        XCTAssertEqual(mock.sent.last, "NBW005;")
        XCTAssertEqual(radio.noiseBlanker2Width, 5)
    }

    // MARK: - Batch 1: Notch extended

    func testSetNotchFrequency_128() {
        radio.setNotchFrequency(128)
        XCTAssertEqual(mock.sent.last, "BP128;")
        XCTAssertEqual(radio.notchFrequency, 128)
    }

    func testSetNotchFrequency_clampsHigh() {
        radio.setNotchFrequency(999)
        XCTAssertEqual(mock.sent.last, "BP255;")
        XCTAssertEqual(radio.notchFrequency, 255)
    }

    func testSetNotchBandwidth_normal() {
        radio.setNotchBandwidth(.normal)
        XCTAssertEqual(mock.sent.last, "NW0;")
        XCTAssertEqual(radio.notchBandwidth, .normal)
    }

    func testSetNotchBandwidth_wide() {
        radio.setNotchBandwidth(.wide)
        XCTAssertEqual(mock.sent.last, "NW2;")
    }

    // MARK: - Batch 1: NR level tuning

    func testSetNRLevel_5() {
        radio.setNRLevel(5)
        XCTAssertEqual(mock.sent.last, "RL105;")
        XCTAssertEqual(radio.nrLevel, 5)
    }

    func testSetNRLevel_clampsLow()  { radio.setNRLevel(0);  XCTAssertEqual(mock.sent.last, "RL101;") }
    func testSetNRLevel_clampsHigh() { radio.setNRLevel(99); XCTAssertEqual(mock.sent.last, "RL110;") }

    func testSetNR2TimeConstant_4() {
        radio.setNR2TimeConstant(4)
        XCTAssertEqual(mock.sent.last, "RL204;")
        XCTAssertEqual(radio.nr2TimeConstant, 4)
    }

    func testSetNR2TimeConstant_clampsHigh() { radio.setNR2TimeConstant(99); XCTAssertEqual(mock.sent.last, "RL209;") }

    // MARK: - Batch 1: DATA VOX

    func testSetDataVOXMode_off()      { radio.setDataVOXMode(.off);      XCTAssertEqual(mock.sent.last, "DV0;") }
    func testSetDataVOXMode_acc2()     { radio.setDataVOXMode(.acc2);     XCTAssertEqual(mock.sent.last, "DV1;") }
    func testSetDataVOXMode_usbAudio() { radio.setDataVOXMode(.usbAudio); XCTAssertEqual(mock.sent.last, "DV2;") }
    func testSetDataVOXMode_lan()      { radio.setDataVOXMode(.lan);      XCTAssertEqual(mock.sent.last, "DV3;") }

    func testSetDataVOXMode_updatesProperty() {
        radio.setDataVOXMode(.usbAudio)
        XCTAssertEqual(radio.dataVOXMode, .usbAudio)
    }

    // MARK: - Batch 1: VOX per-input parameters

    func testSetVOXDelay_mic() {
        radio.setVOXDelay(inputType: 0, value: 10)
        XCTAssertEqual(mock.sent.last, "VD0010;")
        XCTAssertEqual(radio.voxDelay[0], 10)
    }

    func testSetVOXDelay_lan_clampsHigh() {
        radio.setVOXDelay(inputType: 3, value: 99)
        XCTAssertEqual(mock.sent.last, "VD3020;")
        XCTAssertEqual(radio.voxDelay[3], 20)
    }

    func testSetVOXGain_mic() {
        radio.setVOXGain(inputType: 0, gain: 15)
        XCTAssertEqual(mock.sent.last, "VG00015;")
        XCTAssertEqual(radio.voxGain[0], 15)
    }

    func testSetVOXGain_usb() {
        radio.setVOXGain(inputType: 2, gain: 10)
        XCTAssertEqual(mock.sent.last, "VG02010;")
    }

    func testSetAntiVOXLevel_mic() {
        radio.setAntiVOXLevel(inputType: 0, level: 8)
        XCTAssertEqual(mock.sent.last, "VG10008;")
        XCTAssertEqual(radio.antiVOXLevel[0], 8)
    }

    func testSetAntiVOXLevel_acc2() {
        radio.setAntiVOXLevel(inputType: 1, level: 12)
        XCTAssertEqual(mock.sent.last, "VG11012;")
    }
}
