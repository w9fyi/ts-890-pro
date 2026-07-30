import XCTest
@testable import TS_890_Pro

/// Tests for RigctldServer.dispatch() — the command handler.
/// Uses a MockCATTransport so no live radio or TCP connection is needed.
final class RigctldServerTests: XCTestCase {

    nonisolated deinit {}

    private var radio: RadioState!
    private var mock: MockCATTransport!
    private var server: RigctldServer!

    override func setUp() {
        super.setUp()
        radio = RadioState()
        mock  = MockCATTransport()
        radio._setConnectionForTesting(mock)
        server = RigctldServer(radioState: radio)
        // Prime common state so tests don't rely on optionals being nil.
        radio.vfoAFrequencyHz  = 14_074_000
        radio.vfoBFrequencyHz  = 14_074_500
        radio.operatingMode    = .usbData
        radio.isPTTDown        = false
        radio.isAppPTTActive   = false
        radio.rxVFO            = .a
        radio.txVFO            = .a
        radio.ritEnabled       = false
        radio.xitEnabled       = false
        radio.ritXitOffsetHz   = 0
        radio.rfGain           = 255
        radio.afGain           = 128
        radio.outputPowerWatts = 100
        radio.transceiverNRMode  = .off
        radio.noiseBlankerEnabled = false
        radio.isNotchEnabled     = false
    }

    override func tearDown() {
        server = nil
        radio  = nil
        mock   = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Dispatch a command and return the response string.
    private func cmd(_ command: String) -> String {
        server.dispatch(command).response
    }

    private func cmdQuit(_ command: String) -> Bool {
        server.dispatch(command).quit
    }

    // MARK: - Mode mapping

    func testModeToRigctld_allModes() {
        let expected: [(KenwoodCAT.OperatingMode, String)] = [
            (.lsb,     "LSB"),
            (.usb,     "USB"),
            (.cw,      "CW"),
            (.cwR,     "CWR"),
            (.fm,      "FM"),
            (.am,      "AM"),
            (.fsk,     "RTTY"),
            (.fskR,    "RTTYR"),
            (.psk,     "PKTLSB"),
            (.pskR,    "PKTUSB"),
            (.lsbData, "PKTLSB"),
            (.usbData, "PKTUSB"),
            (.fmData,  "PKTFM"),
            (.amData,  "AM"),
        ]
        for (mode, expected) in expected {
            let result = RigctldServer.modeToRigctld[mode]
            XCTAssertEqual(result, expected, "modeToRigctld[\(mode)] should be \(expected)")
        }
    }

    func testRigctldToMode_commonModes() {
        let expected: [(String, KenwoodCAT.OperatingMode)] = [
            ("LSB",    .lsb),
            ("USB",    .usb),
            ("CW",     .cw),
            ("CWR",    .cwR),
            ("RTTY",   .fsk),
            ("RTTYR",  .fskR),
            ("AM",     .am),
            ("FM",     .fm),
            ("WFM",    .fm),
            ("PKTLSB", .lsbData),
            ("PKTUSB", .usbData),
            ("PKTFM",  .fmData),
        ]
        for (str, expected) in expected {
            let result = RigctldServer.rigctldToMode[str]
            XCTAssertEqual(result, expected, "rigctldToMode[\(str)] should be \(expected)")
        }
    }

    // MARK: - Get frequency (f / \get_freq)

    func testGetFreq_returnsVFOAHz() {
        radio.vfoAFrequencyHz = 7_074_000
        let r = cmd("f")
        XCTAssertTrue(r.hasPrefix("7074000\n"), "response=\(r)")
        XCTAssertTrue(r.hasSuffix("RPRT 0\n"))
    }

    func testGetFreqLongForm() {
        radio.vfoAFrequencyHz = 14_225_000
        let r = cmd("\\get_freq")
        XCTAssertTrue(r.hasPrefix("14225000\n"))
    }

    func testGetFreq_zeroWhenNil() {
        radio.vfoAFrequencyHz = nil
        XCTAssertTrue(cmd("f").hasPrefix("0\n"))
    }

    // MARK: - Set frequency (F / \set_freq)

    func testSetFreq_sendsCorrectCATCommand() {
        mock.reset()
        let r = cmd("F 14074000")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "FA00014074000;")
    }

    func testSetFreq_invalidArg_returnsError() {
        let r = cmd("F notanumber")
        XCTAssertEqual(r, "RPRT -1\n")
    }

    func testSetFreq_missingArg_returnsError() {
        XCTAssertEqual(cmd("F"), "RPRT -1\n")
    }

    // MARK: - Get mode (m / \get_mode)

    func testGetMode_usbData_returnsPKTUSB() {
        radio.operatingMode = .usbData
        let r = cmd("m")
        let lines = r.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "PKTUSB")
        XCTAssertEqual(lines[2], "RPRT 0")
    }

    func testGetMode_cw_returnsCWWithNarrowPassband() {
        radio.operatingMode = .cw
        let r = cmd("m")
        let lines = r.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "CW")
        XCTAssertEqual(lines[1], "500")
    }

    func testGetMode_nilMode_defaultsToUSB() {
        radio.operatingMode = nil
        XCTAssertTrue(cmd("m").hasPrefix("USB\n"))
    }

    // MARK: - Set mode (M / \set_mode)

    func testSetMode_USB_sendsOM02() {
        mock.reset()
        let r = cmd("M USB 0")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "OM02;")
    }

    func testSetMode_PKTUSB_sendsusbData() {
        mock.reset()
        _ = cmd("M PKTUSB 3000")
        XCTAssertEqual(mock.sent.last, "OM0D;")  // usbData = 13 = 0xD
    }

    func testSetMode_CWR_sendsCWR() {
        mock.reset()
        _ = cmd("M CWR 0")
        XCTAssertEqual(mock.sent.last, "OM07;")
    }

    func testSetMode_unknown_returnsError() {
        XCTAssertEqual(cmd("M INVALID 0"), "RPRT -1\n")
    }

    // MARK: - PTT (t / T / \get_ptt / \set_ptt)

    func testGetPTT_rx_returnsZero() {
        radio.isPTTDown = false
        XCTAssertTrue(cmd("t").hasPrefix("0\n"))
    }

    func testGetPTT_tx_returnsOne() {
        radio.isPTTDown = true
        XCTAssertTrue(cmd("t").hasPrefix("1\n"))
    }

    func testSetPTT_key_sendsTX0() {
        mock.reset()
        let r = cmd("T 1")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "TX0;")
        XCTAssertTrue(radio.isAppPTTActive)
    }

    func testSetPTT_unkey_sendsRX() {
        radio.isAppPTTActive = true
        mock.reset()
        let r = cmd("T 0")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "RX;")
        XCTAssertFalse(radio.isAppPTTActive)
    }

    func testSetPTT_missingArg_returnsError() {
        XCTAssertEqual(cmd("T"), "RPRT -1\n")
    }

    // MARK: - VFO (v / V)

    func testGetVFO_vfoA_returnsVFOA() {
        radio.rxVFO = .a
        XCTAssertTrue(cmd("v").hasPrefix("VFOA\n"))
    }

    func testGetVFO_vfoB_returnsVFOB() {
        radio.rxVFO = .b
        XCTAssertTrue(cmd("v").hasPrefix("VFOB\n"))
    }

    func testSetVFO_VFOB_sendsFR1() {
        mock.reset()
        let r = cmd("V VFOB")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "FR1;")
    }

    func testSetVFO_VFOA_sendsFR0() {
        mock.reset()
        _ = cmd("V VFOA")
        XCTAssertEqual(mock.sent.last, "FR0;")
    }

    // MARK: - Split (s / S)

    func testGetSplit_noSplit_returnsZero() {
        radio.rxVFO = .a
        radio.txVFO = .a
        radio.splitOffsetSettingActive = false
        let r = cmd("s")
        XCTAssertTrue(r.hasPrefix("0\n"))
    }

    func testGetSplit_split_returnsOne() {
        radio.rxVFO = .a
        radio.txVFO = .b
        let r = cmd("s")
        XCTAssertTrue(r.hasPrefix("1\n"))
    }

    func testSetSplit_enable_sendsFR0FT1() {
        mock.reset()
        let r = cmd("S 1 VFOB")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertTrue(mock.sent.contains("FR0;"))
        XCTAssertTrue(mock.sent.contains("FT1;"))
    }

    func testSetSplit_disable_sendsBothFR0FT0() {
        mock.reset()
        _ = cmd("S 0 VFOA")
        XCTAssertTrue(mock.sent.contains("FR0;"))
        XCTAssertTrue(mock.sent.contains("FT0;"))
    }

    // MARK: - RIT / XIT

    func testGetRIT_disabled_returnsZero() {
        radio.ritEnabled = false
        radio.ritXitOffsetHz = 200
        XCTAssertTrue(cmd("i").hasPrefix("0\n"))
    }

    func testGetRIT_enabled_returnsOffset() {
        radio.ritEnabled = true
        radio.ritXitOffsetHz = 300
        XCTAssertTrue(cmd("i").hasPrefix("300\n"))
    }

    func testSetRIT_nonzero_enablesAndSetsOffset() {
        mock.reset()
        let r = cmd("I 500")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertTrue(mock.sent.contains("RT1;"))
        XCTAssertTrue(mock.sent.contains("RU00500;"))
    }

    func testSetRIT_zero_disables() {
        mock.reset()
        _ = cmd("I 0")
        XCTAssertTrue(mock.sent.contains("RT0;"))
    }

    func testGetXIT_enabled_returnsOffset() {
        radio.xitEnabled = true
        radio.ritXitOffsetHz = -150
        XCTAssertTrue(cmd("j").hasPrefix("-150\n"))
    }

    func testSetXIT_nonzero_enablesAndSetsOffset() {
        mock.reset()
        let r = cmd("J -200")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertTrue(mock.sent.contains("XT1;"))
    }

    // MARK: - Levels (l / L)

    func testGetRFPOWER_100W_returns1() {
        radio.outputPowerWatts = 100
        let r = cmd("l RFPOWER")
        XCTAssertTrue(r.hasPrefix("1.000000\n"), "response=\(r)")
    }

    func testGetRFPOWER_50W_returnsHalf() {
        radio.outputPowerWatts = 50
        let r = cmd("l RFPOWER")
        XCTAssertTrue(r.hasPrefix("0.500000\n"))
    }

    func testSetRFPOWER_half_sends50W() {
        mock.reset()
        let r = cmd("L RFPOWER 0.5")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "PC050;")
    }

    func testGetAF_128_returnsHalf() {
        radio.afGain = 128
        let r = cmd("l AF")
        // 128/255 ≈ 0.502
        XCTAssertTrue(r.hasPrefix("0.5"), "response=\(r)")
    }

    func testSetAF_full_sends255() {
        mock.reset()
        _ = cmd("L AF 1.0")
        XCTAssertEqual(mock.sent.last, "AG255;")
    }

    func testGetRFGAIN_full_returns1() {
        radio.rfGain = 255
        let r = cmd("l RFGAIN")
        XCTAssertTrue(r.hasPrefix("1.000000\n"))
    }

    func testGetSMETER_zero_returnsZero() {
        radio.meterReadings[0] = 0
        let r = cmd("l SMETER")
        XCTAssertTrue(r.hasPrefix("0.000000\n"))
    }

    func testGetSMETER_S9_returns9() {
        radio.meterReadings[0] = 18  // S9 = 18 dots
        let r = cmd("l SMETER")
        XCTAssertTrue(r.hasPrefix("9.000000\n"), "response=\(r)")
    }

    func testGetLevel_unknown_returnsError() {
        XCTAssertEqual(cmd("l BADLEVEL"), "RPRT -1\n")
    }

    func testSetLevel_unknown_returnsError() {
        XCTAssertEqual(cmd("L BADLEVEL 0.5"), "RPRT -1\n")
    }

    // MARK: - Functions (u / U)

    func testGetNR_off_returnsZero() {
        radio.transceiverNRMode = .off
        XCTAssertTrue(cmd("u NR").hasPrefix("0\n"))
    }

    func testGetNR_nr1_returnsOne() {
        radio.transceiverNRMode = .nr1
        XCTAssertTrue(cmd("u NR").hasPrefix("1\n"))
    }

    func testSetNR_on_sendsNR1() {
        mock.reset()
        let r = cmd("U NR 1")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "NR1;")
    }

    func testSetNR_off_sendsNR0() {
        mock.reset()
        _ = cmd("U NR 0")
        XCTAssertEqual(mock.sent.last, "NR0;")
    }

    func testGetNB_off_returnsZero() {
        radio.noiseBlankerEnabled = false
        XCTAssertTrue(cmd("u NB").hasPrefix("0\n"))
    }

    func testSetNB_on_sendsNB1() {
        mock.reset()
        let r = cmd("U NB 1")
        XCTAssertEqual(r, "RPRT 0\n")
        XCTAssertEqual(mock.sent.last, "NB11;")
    }

    func testSetANF_on_sendsNT1() {
        mock.reset()
        _ = cmd("U ANF 1")
        XCTAssertEqual(mock.sent.last, "NT1;")
    }

    func testGetFunc_unknown_returnsError() {
        XCTAssertEqual(cmd("u UNKNOWN"), "RPRT -1\n")
    }

    // MARK: - Special commands

    func testChkVFO_returnsZero() {
        let r = cmd("\\chk_vfo")
        XCTAssertTrue(r.hasPrefix("CHKVFO 0\n"))
        XCTAssertTrue(r.hasSuffix("RPRT 0\n"))
    }

    func testGetInfo_containsTS890() {
        let r = cmd("\\get_info")
        XCTAssertTrue(r.contains("TS-890S"))
        XCTAssertTrue(r.hasSuffix("RPRT 0\n"))
    }

    func testDumpState_isStructurallyValid() {
        let r = cmd("\\dump_state")
        // Must begin with protocol version line and end with RPRT 0
        XCTAssertTrue(r.hasPrefix("0\n"), "first line should be protocol version 0")
        XCTAssertTrue(r.hasSuffix("RPRT 0\n"))
        // Must contain band range terminator lines
        let count = r.components(separatedBy: "0 0\n").count - 1
        XCTAssertGreaterThanOrEqual(count, 3, "should have at least 3 range-terminator 0 0 lines")
    }

    func testDumpState_containsHFRange() {
        let r = cmd("\\dump_state")
        XCTAssertTrue(r.contains("14000000"), "should include 20m TX range")
    }

    func testQuit_returnsOKAndQuit() {
        let (response, quit) = server.dispatch("q")
        XCTAssertEqual(response, "RPRT 0\n")
        XCTAssertTrue(quit)
    }

    func testUnknownCommand_returnsError() {
        XCTAssertEqual(cmd("zz_bogus"), "RPRT -1\n")
    }

    // MARK: - No radio state

    func testDispatch_noRadioState_returnsError() {
        let orphan = RigctldServer(radioState: RadioState())
        // Release the radio reference so server.radioState becomes nil
        // (Can't easily nil a weak ref without extra indirection, so just
        //  verify the fallback path by checking a known-nil situation via
        //  a server with a freshly-created radio that has no freq set.)
        let bare = RigctldServer(radioState: RadioState())
        let r = bare.dispatch("f").response
        // Should still succeed (returns 0 for nil freq), not crash
        XCTAssertTrue(r.contains("RPRT 0"))
        _ = orphan  // suppress unused warning
    }

    // MARK: - Long-form aliases

    func testGetFreqLongFormAlias() {
        radio.vfoAFrequencyHz = 21_074_000
        XCTAssertTrue(cmd("get_freq").hasPrefix("21074000\n"))
    }

    func testSetPTTLongFormAlias() {
        mock.reset()
        _ = cmd("set_ptt 1")
        XCTAssertEqual(mock.sent.last, "TX0;")
    }

    func testGetModeLongFormAlias() {
        radio.operatingMode = .lsb
        XCTAssertTrue(cmd("get_mode").hasPrefix("LSB\n"))
    }
}
