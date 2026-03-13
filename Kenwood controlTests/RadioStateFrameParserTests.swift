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
        radio.handleFrame("GC3;")
        XCTAssertEqual(radio.agcMode, .fast)
    }

    func testParseGC_mid() {
        radio.handleFrame("GC2;")
        XCTAssertEqual(radio.agcMode, .mid)
    }

    func testParseGC_slow() {
        radio.handleFrame("GC1;")
        XCTAssertEqual(radio.agcMode, .slow)
    }

    func testParseGC_outOfRangeIgnored() {
        radio.handleFrame("GC2;")
        XCTAssertEqual(radio.agcMode, .mid)
        radio.handleFrame("GC9;")
        XCTAssertEqual(radio.agcMode, .mid, "Out-of-range AGC value should leave mode unchanged")
    }

    // MARK: - Preamp (PA)

    func testParsePA_off() {
        radio.handleFrame("PA0;")
        XCTAssertEqual(radio.preampLevel, .off)
    }

    func testParsePA_pre1() {
        radio.handleFrame("PA1;")
        XCTAssertEqual(radio.preampLevel, .pre1)
    }

    func testParsePA_pre2() {
        radio.handleFrame("PA2;")
        XCTAssertEqual(radio.preampLevel, .pre2)
    }

    // MARK: - Noise Blanker (NB)

    func testParseNB_on() {
        radio.handleFrame("NB11;")
        XCTAssertEqual(radio.noiseBlankerEnabled, true)
    }

    func testParseNB_off() {
        radio.handleFrame("NB11;")
        radio.handleFrame("NB10;")
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

    func testParseOM_fskR() {
        radio.handleFrame("OM09;")
        XCTAssertEqual(radio.operatingMode, .fskR)
    }

    func testParseOM_usbData() {
        radio.handleFrame("OM0D;")
        XCTAssertEqual(radio.operatingMode, .usbData)
    }

    func testParseOM_lsbData() {
        radio.handleFrame("OM0C;")
        XCTAssertEqual(radio.operatingMode, .lsbData)
    }

    func testParseOM_psk() {
        radio.handleFrame("OM0A;")
        XCTAssertEqual(radio.operatingMode, .psk)
    }

    // MARK: - Beat Cancel (BC)

    func testParseBC_off() {
        radio.handleFrame("BC0;")
        XCTAssertEqual(radio.beatCancelMode, .off)
    }

    func testParseBC_bc1() {
        radio.handleFrame("BC1;")
        XCTAssertEqual(radio.beatCancelMode, .bc1)
    }

    func testParseBC_bc2() {
        radio.handleFrame("BC2;")
        XCTAssertEqual(radio.beatCancelMode, .bc2)
    }

    func testParseBC_doesNotCorruptNB() {
        radio.handleFrame("NB11;")   // NB on
        radio.handleFrame("BC1;")    // BC response — must NOT corrupt noiseBlankerEnabled
        XCTAssertEqual(radio.noiseBlankerEnabled, true)
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

    // MARK: - AF Gain (AG)

    func testParseAG_typical() {
        radio.handleFrame("AG150;")
        XCTAssertEqual(radio.afGain, 150)
    }

    func testParseAG_zero() {
        radio.handleFrame("AG000;")
        XCTAssertEqual(radio.afGain, 0)
    }

    func testParseAG_max() {
        radio.handleFrame("AG255;")
        XCTAssertEqual(radio.afGain, 255)
    }

    // MARK: - Data Mode (DA)

    func testParseDA_enabled() {
        radio.handleFrame("DA1;")
        XCTAssertEqual(radio.dataModeEnabled, true)
    }

    func testParseDA_disabled() {
        radio.handleFrame("DA1;")
        radio.handleFrame("DA0;")
        XCTAssertEqual(radio.dataModeEnabled, false)
    }

    // MARK: - MD mode

    func testParseMD_setsValue() {
        radio.handleFrame("MD2;")
        XCTAssertEqual(radio.mdMode, 2)
    }

    func testParseMD_zero() {
        radio.handleFrame("MD0;")
        XCTAssertEqual(radio.mdMode, 0)
    }

    // MARK: - RX / TX VFO (FR / FT)

    func testParseFR_vfoA() {
        radio.handleFrame("FR0;")
        XCTAssertEqual(radio.rxVFO, .a)
    }

    func testParseFR_vfoB() {
        radio.handleFrame("FR1;")
        XCTAssertEqual(radio.rxVFO, .b)
    }

    func testParseFT_vfoA() {
        radio.handleFrame("FT0;")
        XCTAssertEqual(radio.txVFO, .a)
    }

    func testParseFT_vfoB() {
        radio.handleFrame("FT1;")
        XCTAssertEqual(radio.txVFO, .b)
    }

    // MARK: - Transceiver Noise Reduction (NR)

    func testParseNR_off() {
        radio.handleFrame("NR0;")
        XCTAssertEqual(radio.transceiverNRMode, .off)
    }

    func testParseNR_nr1() {
        radio.handleFrame("NR1;")
        XCTAssertEqual(radio.transceiverNRMode, .nr1)
    }

    func testParseNR_nr2() {
        radio.handleFrame("NR2;")
        XCTAssertEqual(radio.transceiverNRMode, .nr2)
    }

    // MARK: - RX Filter Width (SL / SH)

    func testParseSL_type0_setsLowCutID() {
        radio.handleFrame("SL005;")
        XCTAssertEqual(radio.rxFilterLowCutID, 5)
    }

    func testParseSL_type1_ignored() {
        radio.handleFrame("SL005;")
        radio.handleFrame("SL112;")  // type=1, should be ignored
        XCTAssertEqual(radio.rxFilterLowCutID, 5)
    }

    func testParseSH_type0_setsHighCutID() {
        radio.handleFrame("SH0010;")
        XCTAssertEqual(radio.rxFilterHighCutID, 10)
    }

    func testParseSH_type1_ignored() {
        radio.handleFrame("SH0010;")
        radio.handleFrame("SH1005;")  // type=1, should be ignored
        XCTAssertEqual(radio.rxFilterHighCutID, 10)
    }

    // MARK: - Memory Mode (MV)

    func testParseMV_memoryMode() {
        radio.handleFrame("MV1;")
        XCTAssertEqual(radio.isMemoryMode, true)
    }

    func testParseMV_vfoMode() {
        radio.handleFrame("MV1;")
        radio.handleFrame("MV0;")
        XCTAssertEqual(radio.isMemoryMode, false)
    }

    // MARK: - Memory Channel Number (MN)

    func testParseMN_typical() {
        radio.handleFrame("MN005;")
        XCTAssertEqual(radio.memoryChannelNumber, 5)
    }

    func testParseMN_max() {
        radio.handleFrame("MN099;")
        XCTAssertEqual(radio.memoryChannelNumber, 99)
    }

    // MARK: - ATU (AC)

    func testParseAC_txEnabled_tuneInactive() {
        radio.handleFrame("AC010;")
        XCTAssertEqual(radio.atuTxEnabled, true)
        XCTAssertEqual(radio.atuTuningActive, false)
    }

    func testParseAC_txDisabled_tuneActive() {
        radio.handleFrame("AC001;")
        XCTAssertEqual(radio.atuTxEnabled, false)
        XCTAssertEqual(radio.atuTuningActive, true)
    }

    func testParseAC_allOff() {
        radio.handleFrame("AC010;")
        radio.handleFrame("AC000;")
        XCTAssertEqual(radio.atuTxEnabled, false)
        XCTAssertEqual(radio.atuTuningActive, false)
    }

    // MARK: - Split (SP)

    func testParseSP_on() {
        radio.handleFrame("SP1;")
        XCTAssertEqual(radio.splitOffsetSettingActive, true)
    }

    func testParseSP_off() {
        radio.handleFrame("SP1;")
        radio.handleFrame("SP0;")
        XCTAssertEqual(radio.splitOffsetSettingActive, false)
    }

    // MARK: - VoIP Levels (##KN3)

    func testParseKN3_inputLevel() {
        radio.handleFrame("##KN30100;")
        XCTAssertEqual(radio.voipInputLevel, 100)
    }

    func testParseKN3_outputLevel() {
        radio.handleFrame("##KN31075;")
        XCTAssertEqual(radio.voipOutputLevel, 75)
    }

    func testParseKN3_inputAndOutput_independent() {
        radio.handleFrame("##KN30050;")
        radio.handleFrame("##KN31200;")
        XCTAssertEqual(radio.voipInputLevel, 50)
        XCTAssertEqual(radio.voipOutputLevel, 200)
    }

    // MARK: - Scope Span (BS4)

    func testParseBS4_span0_is5kHz() {
        radio.handleFrame("BS40;")
        XCTAssertEqual(radio.scopeSpanKHz, 5)
    }

    func testParseBS4_span3_is50kHz() {
        radio.handleFrame("BS43;")
        XCTAssertEqual(radio.scopeSpanKHz, 50)
    }

    func testParseBS4_span6_is500kHz() {
        radio.handleFrame("BS46;")
        XCTAssertEqual(radio.scopeSpanKHz, 500)
    }

    func testParseBS4_outOfRange_ignored() {
        radio.handleFrame("BS43;")
        radio.handleFrame("BS49;")  // 9 is out of range
        XCTAssertEqual(radio.scopeSpanKHz, 50)
    }

    // MARK: - Notch (NT)

    func testParseNT_enabled() {
        radio.handleFrame("NT1;")
        XCTAssertEqual(radio.isNotchEnabled, true)
    }

    func testParseNT_disabled() {
        radio.handleFrame("NT1;")
        radio.handleFrame("NT0;")
        XCTAssertEqual(radio.isNotchEnabled, false)
    }

    // MARK: - EQ band values (UT / UR)

    func testParseUT_flatResponse_setsAllBandsZero() {
        let payload = String(repeating: "06", count: 18)   // raw 6 → 0 dB for every band
        radio.handleFrame("UT\(payload);")
        XCTAssertEqual(radio.txEQBands, Array(repeating: 0, count: 18))
    }

    func testParseUT_mixedValues_decodeCorrectly() {
        // band 0: raw 00 → +6 dB;  band 1: raw 12 → −6 dB;  rest: raw 06 → 0 dB
        let payload = "00" + "12" + String(repeating: "06", count: 16)
        radio.handleFrame("UT\(payload);")
        XCTAssertEqual(radio.txEQBands[0],  6)
        XCTAssertEqual(radio.txEQBands[1], -6)
        XCTAssertEqual(radio.txEQBands[2],  0)
    }

    func testParseUR_setsRXBands() {
        let payload = String(repeating: "00", count: 18)   // +6 dB across all bands
        radio.handleFrame("UR\(payload);")
        XCTAssertEqual(radio.rxEQBands, Array(repeating: 6, count: 18))
    }

    func testParseUT_wrongLength_ignored() {
        radio.handleFrame("UT\(String(repeating: "06", count: 18));")  // set a known value
        let before = radio.txEQBands
        radio.handleFrame("UT0606;")                                    // too short → ignored
        XCTAssertEqual(radio.txEQBands, before)
    }

    // MARK: - EQ preset responses (EQT0 / EQR0)

    func testParseEQT0_setsPreset() {
        radio.handleFrame("EQT02;")  // preset 2 = Formant Pass
        XCTAssertEqual(radio.txEQPreset, .formantPass)
    }

    func testParseEQT0_user1() {
        radio.handleFrame("EQT06;")  // preset 6 = User 1
        XCTAssertEqual(radio.txEQPreset, .user1)
    }

    func testParseEQR0_setsPreset() {
        radio.handleFrame("EQR05;")  // preset 5 = Conventional (RX: Flat)
        XCTAssertEqual(radio.rxEQPreset, .conventional)
    }

    func testParseEQT0_outOfRange_ignored() {
        radio.handleFrame("EQT06;")
        radio.handleFrame("EQT09;")  // 9 is out of range 0–8
        XCTAssertEqual(radio.txEQPreset, .user1)  // still user1 from previous frame
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

    // MARK: - Filter Slot (FL)

    func testParseFL0_slotA() {
        radio.handleFrame("FL00;")
        XCTAssertEqual(radio.filterSlot, .a)
    }

    func testParseFL0_slotB() {
        radio.handleFrame("FL01;")
        XCTAssertEqual(radio.filterSlot, .b)
    }

    func testParseFL0_slotC() {
        radio.handleFrame("FL02;")
        XCTAssertEqual(radio.filterSlot, .c)
    }

    func testParseFL0_outOfRange_ignored() {
        radio.handleFrame("FL01;")  // set to B first
        radio.handleFrame("FL03;")  // 3 is out of range — should not crash or change state
        XCTAssertEqual(radio.filterSlot, .b)
    }

    func testParseFL0_tooShort_doesNotCrash() {
        XCTAssertNoThrow(radio.handleFrame("FL0;"))
        XCTAssertNil(radio.filterSlot)
    }

    // MARK: - cycleFilterSlot from nil

    func testCycleFilterSlot_fromNil_defaultsToB() {
        XCTAssertNil(radio.filterSlot)
        radio.cycleFilterSlot()
        // nil defaults to .a, next is .b
        XCTAssertEqual(radio.filterSlot, .b)
    }

    func testCycleFilterSlot_wrapsC_backToA() {
        radio.handleFrame("FL02;")  // set to C
        radio.cycleFilterSlot()
        XCTAssertEqual(radio.filterSlot, .a)
    }

    // MARK: - Scan State (SC)

    func testParseSC_scanning() {
        radio.handleFrame("SC1;")
        XCTAssertTrue(radio.scanActive)
    }

    func testParseSC_stopped() {
        radio.handleFrame("SC1;")
        radio.handleFrame("SC0;")
        XCTAssertFalse(radio.scanActive)
    }

    func testParseSC_unknownValue_doesNotCrash() {
        XCTAssertNoThrow(radio.handleFrame("SC9;"))
        XCTAssertFalse(radio.scanActive)
    }

    func testParseSC_tooShort_doesNotCrash() {
        XCTAssertNoThrow(radio.handleFrame("SC;"))
        XCTAssertFalse(radio.scanActive)
    }

    // MARK: - sendCWKeyer

    func testSendCWKeyer_normal() {
        radio.sendCWKeyer(text: "cq cq de ai5os")
        let last = DiagnosticsStore.shared.txLog.last
        XCTAssertEqual(last, "KY CQ CQ DE AI5OS;")
    }

    func testSendCWKeyer_truncatesAt24Chars() {
        radio.sendCWKeyer(text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")  // 26 chars
        let last = DiagnosticsStore.shared.txLog.last
        XCTAssertEqual(last, "KY ABCDEFGHIJKLMNOPQRSTUVWX;")  // 24 chars of payload (A–X)
    }

    func testSendCWKeyer_emptyString_doesNotSend() {
        let countBefore = DiagnosticsStore.shared.txLog.count
        radio.sendCWKeyer(text: "")
        XCTAssertEqual(DiagnosticsStore.shared.txLog.count, countBefore)
    }

    func testSendCWKeyer_whitespaceOnly_doesNotSend() {
        let countBefore = DiagnosticsStore.shared.txLog.count
        radio.sendCWKeyer(text: "   ")
        XCTAssertEqual(DiagnosticsStore.shared.txLog.count, countBefore)
    }

    func testSendCWKeyer_uppercasesInput() {
        radio.sendCWKeyer(text: "de ai5os k")
        let last = DiagnosticsStore.shared.txLog.last
        XCTAssertEqual(last, "KY DE AI5OS K;")
    }
}
