import XCTest
@testable import Kenwood_control

/// Tests for RadioState.handleFrame — verifying CAT response parsing without a live radio.
///
/// Each test feeds a raw CAT frame string directly into handleFrame() and asserts
/// that the corresponding @Published property is updated correctly.
final class RadioStateFrameParserTests: XCTestCase {

    var radio: RadioState!

    override func setUp() {
        super.setUp()
        radio = RadioState()
    }

    override func tearDown() {
        radio = nil
        super.tearDown()
    }

    // MARK: - VFO Frequency (FA / FB)

    func testParseFA_typicalHFFrequency() {
        radio.handleFrame("FA00014225000;")
        XCTAssertEqual(radio.vfoAFrequencyHz, 14_225_000)
    }

    func testParseFA_40mFrequency() {
        radio.handleFrame("FA00007074000;")
        XCTAssertEqual(radio.vfoAFrequencyHz, 7_074_000)
    }

    func testParseFB_typicalFrequency() {
        radio.handleFrame("FB00007200000;")
        XCTAssertEqual(radio.vfoBFrequencyHz, 7_200_000)
    }

    func testParseFA_zero() {
        radio.handleFrame("FA00000000000;")
        XCTAssertEqual(radio.vfoAFrequencyHz, 0)
    }

    // MARK: - Attenuator (RA) — regression tests for the RA00n bug fix

    func testParseRA_off() {
        radio.handleFrame("RA0;")
        XCTAssertEqual(radio.attenuatorLevel, .off)
    }

    func testParseRA_6dB() {
        radio.handleFrame("RA1;")
        XCTAssertEqual(radio.attenuatorLevel, .db6)
    }

    func testParseRA_12dB() {
        radio.handleFrame("RA2;")
        XCTAssertEqual(radio.attenuatorLevel, .db12)
    }

    func testParseRA_18dB() {
        radio.handleFrame("RA3;")
        XCTAssertEqual(radio.attenuatorLevel, .db18)
    }

    func testParseRA_cycleAllLevels() {
        // Simulate receiving each level in sequence
        for level in KenwoodCAT.AttenuatorLevel.allCases {
            radio.handleFrame(KenwoodCAT.setAttenuator(level))
            XCTAssertEqual(radio.attenuatorLevel, level,
                           "Expected \(level) after sending \(KenwoodCAT.setAttenuator(level))")
        }
    }

    func testParseRA_outOfRangeIgnored() {
        radio.handleFrame("RA1;")                 // set a known value first
        XCTAssertEqual(radio.attenuatorLevel, .db6)
        radio.handleFrame("RA9;")                 // 9 is not a valid level
        XCTAssertEqual(radio.attenuatorLevel, .db6, "Out-of-range value should leave level unchanged")
    }

    func testParseRA_withoutSemicolon() {
        // handleFrame strips the trailing semicolon itself; raw frames without it should also parse
        radio.handleFrame("RA2")
        XCTAssertEqual(radio.attenuatorLevel, .db12)
    }

    // MARK: - AGC (GC)

    func testParseGC_off() {
        radio.handleFrame("GC0;")
        XCTAssertEqual(radio.agcMode, .off)
    }

    func testParseGC_fast() {
        radio.handleFrame("GC1;")
        XCTAssertEqual(radio.agcMode, .fast)
    }

    func testParseGC_mid() {
        radio.handleFrame("GC2;")
        XCTAssertEqual(radio.agcMode, .mid)
    }

    func testParseGC_slow() {
        radio.handleFrame("GC3;")
        XCTAssertEqual(radio.agcMode, .slow)
    }

    func testParseGC_outOfRangeIgnored() {
        radio.handleFrame("GC2;")
        XCTAssertEqual(radio.agcMode, .mid)
        radio.handleFrame("GC9;")
        XCTAssertEqual(radio.agcMode, .mid, "Out-of-range AGC value should leave mode unchanged")
    }

    // MARK: - Preamp (PA)

    func testParsePA_on() {
        radio.handleFrame("PA1;")
        XCTAssertEqual(radio.preampEnabled, true)
    }

    func testParsePA_off() {
        radio.handleFrame("PA1;")
        radio.handleFrame("PA0;")
        XCTAssertEqual(radio.preampEnabled, false)
    }

    // MARK: - Noise Blanker (NB)

    func testParseNB_on() {
        radio.handleFrame("NB1;")
        XCTAssertEqual(radio.noiseBlankerEnabled, true)
    }

    func testParseNB_off() {
        radio.handleFrame("NB1;")
        radio.handleFrame("NB0;")
        XCTAssertEqual(radio.noiseBlankerEnabled, false)
    }

    // MARK: - TX Power (PC)

    func testParsePC_100W() {
        radio.handleFrame("PC100;")
        XCTAssertEqual(radio.outputPowerWatts, 100)
    }

    func testParsePC_5W() {
        radio.handleFrame("PC005;")
        XCTAssertEqual(radio.outputPowerWatts, 5)
    }

    // MARK: - Operating Mode (OM)

    func testParseOM_usb() {
        radio.handleFrame("OM02;")
        XCTAssertEqual(radio.operatingMode, .usb)
    }

    func testParseOM_lsb() {
        radio.handleFrame("OM01;")
        XCTAssertEqual(radio.operatingMode, .lsb)
    }

    func testParseOM_cw() {
        radio.handleFrame("OM03;")
        XCTAssertEqual(radio.operatingMode, .cw)
    }

    func testParseOM_fm() {
        radio.handleFrame("OM04;")
        XCTAssertEqual(radio.operatingMode, .fm)
    }

    // MARK: - RIT / XIT enabled

    func testParseRT_enabled() {
        radio.handleFrame("RT1;")
        XCTAssertEqual(radio.ritEnabled, true)
    }

    func testParseRT_disabled() {
        radio.handleFrame("RT1;")
        radio.handleFrame("RT0;")
        XCTAssertEqual(radio.ritEnabled, false)
    }

    func testParseXT_enabled() {
        radio.handleFrame("XT1;")
        XCTAssertEqual(radio.xitEnabled, true)
    }

    // MARK: - RIT/XIT Offset (RF)

    func testParseRF_positive500Hz() {
        // RF format: direction(0=positive,1=negative) + 4-digit Hz
        radio.handleFrame("RF00500;")
        XCTAssertEqual(radio.ritXitOffsetHz, 500)
    }

    func testParseRF_negative500Hz() {
        radio.handleFrame("RF10500;")
        XCTAssertEqual(radio.ritXitOffsetHz, -500)
    }

    // MARK: - RX Filter Shift (IS)

    func testParseIS_positive() {
        radio.handleFrame("IS+0300;")
        XCTAssertEqual(radio.rxFilterShiftHz, 300)
    }

    func testParseIS_negative() {
        radio.handleFrame("IS-0300;")
        XCTAssertEqual(radio.rxFilterShiftHz, -300)
    }

    func testParseIS_zero() {
        radio.handleFrame("IS+0000;")
        XCTAssertEqual(radio.rxFilterShiftHz, 0)
    }

    // MARK: - RF Gain (RG)

    func testParseRG_max() {
        radio.handleFrame("RG255;")
        XCTAssertEqual(radio.rfGain, 255)
    }

    func testParseRG_zero() {
        radio.handleFrame("RG000;")
        XCTAssertEqual(radio.rfGain, 0)
    }

    // MARK: - Unknown / malformed frames

    func testUnknownFrameDoesNotCrash() {
        XCTAssertNoThrow(radio.handleFrame("ZZ99;"))
        XCTAssertNoThrow(radio.handleFrame(""))
        XCTAssertNoThrow(radio.handleFrame(";"))
        XCTAssertNoThrow(radio.handleFrame("?;"))
    }

    func testRAFrameTooShort_doesNotCrash() {
        // A bare "RA" with no digit should not crash or change existing state
        radio.handleFrame("RA1;")
        XCTAssertEqual(radio.attenuatorLevel, .db6)
        XCTAssertNoThrow(radio.handleFrame("RA;"))  // query echo, not a set response
    }
}
