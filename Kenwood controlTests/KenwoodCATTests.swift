import XCTest
@testable import Kenwood_control

final class KenwoodCATTests: XCTestCase {

    // MARK: - VFO Frequency

    func testGetVFOAFrequency() {
        XCTAssertEqual(KenwoodCAT.getVFOAFrequency(), "FA;")
    }

    func testGetVFOBFrequency() {
        XCTAssertEqual(KenwoodCAT.getVFOBFrequency(), "FB;")
    }

    func testSetVFOAFrequency_typical() {
        XCTAssertEqual(KenwoodCAT.setVFOAFrequencyHz(14_225_000), "FA00014225000;")
    }

    func testSetVFOAFrequency_zero() {
        XCTAssertEqual(KenwoodCAT.setVFOAFrequencyHz(0), "FA00000000000;")
    }

    func testSetVFOAFrequency_clampsNegative() {
        XCTAssertEqual(KenwoodCAT.setVFOAFrequencyHz(-1), "FA00000000000;")
    }

    func testSetVFOAFrequency_clampsOverMax() {
        XCTAssertEqual(KenwoodCAT.setVFOAFrequencyHz(1_000_000_000), "FA00999999999;")
    }

    func testSetVFOBFrequency_typical() {
        XCTAssertEqual(KenwoodCAT.setVFOBFrequencyHz(7_074_000), "FB00007074000;")
    }

    // MARK: - Attenuator (RA) — regression test for the RA00n bug

    func testGetAttenuator() {
        XCTAssertEqual(KenwoodCAT.getAttenuator(), "RA;")
    }

    func testSetAttenuator_off() {
        XCTAssertEqual(KenwoodCAT.setAttenuator(.off), "RA0;")
    }

    func testSetAttenuator_6dB() {
        XCTAssertEqual(KenwoodCAT.setAttenuator(.db6), "RA1;")
    }

    func testSetAttenuator_12dB() {
        XCTAssertEqual(KenwoodCAT.setAttenuator(.db12), "RA2;")
    }

    func testSetAttenuator_18dB() {
        XCTAssertEqual(KenwoodCAT.setAttenuator(.db18), "RA3;")
    }

    func testAttenuatorLevel_nextCyclesAllFourValues() {
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.off.next,  .db6)
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db6.next,  .db12)
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db12.next, .db18)
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db18.next, .off)   // wraps back to off
    }

    func testAttenuatorLevel_labels() {
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.off.label,  "Off")
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db6.label,  "6 dB")
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db12.label, "12 dB")
        XCTAssertEqual(KenwoodCAT.AttenuatorLevel.db18.label, "18 dB")
    }

    // MARK: - Preamp (PA)

    func testGetPreamp() {
        XCTAssertEqual(KenwoodCAT.getPreamp(), "PA;")
    }

    func testSetPreamp_on() {
        XCTAssertEqual(KenwoodCAT.setPreamp(enabled: true), "PA1;")
    }

    func testSetPreamp_off() {
        XCTAssertEqual(KenwoodCAT.setPreamp(enabled: false), "PA0;")
    }

    // MARK: - AGC (GC)

    func testGetAGC() {
        XCTAssertEqual(KenwoodCAT.getAGC(), "GC;")
    }

    func testSetAGC_allModes() {
        XCTAssertEqual(KenwoodCAT.setAGC(.off),  "GC0;")
        XCTAssertEqual(KenwoodCAT.setAGC(.fast), "GC1;")
        XCTAssertEqual(KenwoodCAT.setAGC(.mid),  "GC2;")
        XCTAssertEqual(KenwoodCAT.setAGC(.slow), "GC3;")
    }

    func testAGCMode_nextCyclesFourValues() {
        XCTAssertEqual(KenwoodCAT.AGCMode.off.next,  .fast)
        XCTAssertEqual(KenwoodCAT.AGCMode.fast.next, .mid)
        XCTAssertEqual(KenwoodCAT.AGCMode.mid.next,  .slow)
        XCTAssertEqual(KenwoodCAT.AGCMode.slow.next, .off)
    }

    // MARK: - Noise Blanker (NB)

    func testGetNoiseBlanker() {
        XCTAssertEqual(KenwoodCAT.getNoiseBlanker(), "NB;")
    }

    func testSetNoiseBlanker_on() {
        XCTAssertEqual(KenwoodCAT.setNoiseBlanker(enabled: true), "NB1;")
    }

    func testSetNoiseBlanker_off() {
        XCTAssertEqual(KenwoodCAT.setNoiseBlanker(enabled: false), "NB0;")
    }

    // MARK: - Beat Cancel (BC)

    func testSetBeatCancel_on() {
        XCTAssertEqual(KenwoodCAT.setBeatCancel(enabled: true), "BC1;")
    }

    func testSetBeatCancel_off() {
        XCTAssertEqual(KenwoodCAT.setBeatCancel(enabled: false), "BC0;")
    }

    // MARK: - TX Power (PC)

    func testGetOutputPower() {
        XCTAssertEqual(KenwoodCAT.getOutputPower(), "PC;")
    }

    func testSetOutputPower_typical() {
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(100), "PC100;")
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(50),  "PC050;")
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(5),   "PC005;")
    }

    func testSetOutputPower_clampsBelow5() {
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(0), "PC005;")
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(-10), "PC005;")
    }

    func testSetOutputPower_clampsAbove100() {
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(101), "PC100;")
        XCTAssertEqual(KenwoodCAT.setOutputPowerWatts(999), "PC100;")
    }

    // MARK: - RF Gain (RG)

    func testSetRFGain_typical() {
        XCTAssertEqual(KenwoodCAT.setRFGain(128), "RG128;")
        XCTAssertEqual(KenwoodCAT.setRFGain(0),   "RG000;")
        XCTAssertEqual(KenwoodCAT.setRFGain(255), "RG255;")
    }

    func testSetRFGain_clamping() {
        XCTAssertEqual(KenwoodCAT.setRFGain(-1),  "RG000;")
        XCTAssertEqual(KenwoodCAT.setRFGain(256), "RG255;")
    }

    // MARK: - AF Gain (AG)

    func testSetAFGain_typical() {
        XCTAssertEqual(KenwoodCAT.setAFGain(100), "AG100;")
        XCTAssertEqual(KenwoodCAT.setAFGain(0),   "AG000;")
        XCTAssertEqual(KenwoodCAT.setAFGain(255), "AG255;")
    }

    func testSetAFGain_clamping() {
        XCTAssertEqual(KenwoodCAT.setAFGain(-1),  "AG000;")
        XCTAssertEqual(KenwoodCAT.setAFGain(256), "AG255;")
    }

    // MARK: - CW Speed (KS)

    func testSetCWSpeed_typical() {
        XCTAssertEqual(KenwoodCAT.setCWSpeed(25), "KS025;")
        XCTAssertEqual(KenwoodCAT.setCWSpeed(4),  "KS004;")
        XCTAssertEqual(KenwoodCAT.setCWSpeed(100),"KS100;")
    }

    func testSetCWSpeed_clampsBelow4() {
        XCTAssertEqual(KenwoodCAT.setCWSpeed(0), "KS004;")
        XCTAssertEqual(KenwoodCAT.setCWSpeed(3), "KS004;")
    }

    func testSetCWSpeed_clampsAbove100() {
        XCTAssertEqual(KenwoodCAT.setCWSpeed(101), "KS100;")
    }

    // MARK: - RIT/XIT Offset

    func testRitXitOffset_positiveHz() {
        XCTAssertEqual(KenwoodCAT.ritXitSetOffsetHz(500), "RU00500;")
    }

    func testRitXitOffset_negativeHz() {
        XCTAssertEqual(KenwoodCAT.ritXitSetOffsetHz(-500), "RD00500;")
    }

    func testRitXitOffset_zero() {
        XCTAssertEqual(KenwoodCAT.ritXitSetOffsetHz(0), "RU00000;")
    }

    func testRitXitOffset_clampsAboveMax() {
        XCTAssertEqual(KenwoodCAT.ritXitSetOffsetHz(99_999), "RU09999;")
    }

    // MARK: - RX Filter Shift (IS)

    func testSetReceiveFilterShift_positive() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterShiftHz(300), "IS+0300;")
    }

    func testSetReceiveFilterShift_negative() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterShiftHz(-300), "IS-0300;")
    }

    func testSetReceiveFilterShift_zero() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterShiftHz(0), "IS+0000;")
    }

    // MARK: - EQ Gain (EX)

    func testSetEQGain_positive() {
        XCTAssertEqual(KenwoodCAT.setEQGain(30, dB: 10), "EX030+10;")
        XCTAssertEqual(KenwoodCAT.setEQGain(30, dB: 0),  "EX030+00;")
    }

    func testSetEQGain_negative() {
        XCTAssertEqual(KenwoodCAT.setEQGain(60, dB: -20), "EX060-20;")
        XCTAssertEqual(KenwoodCAT.setEQGain(60, dB: -5),  "EX060-05;")
    }

    func testSetEQGain_clampsAbove10() {
        XCTAssertEqual(KenwoodCAT.setEQGain(30, dB: 11), "EX030+10;")
    }

    func testSetEQGain_clampsBelow20() {
        XCTAssertEqual(KenwoodCAT.setEQGain(30, dB: -21), "EX030-20;")
    }

    // MARK: - Memory Channel

    func testSetMemoryChannelNumber_typical() {
        XCTAssertEqual(KenwoodCAT.setMemoryChannelNumber(0),   "MN000;")
        XCTAssertEqual(KenwoodCAT.setMemoryChannelNumber(50),  "MN050;")
        XCTAssertEqual(KenwoodCAT.setMemoryChannelNumber(119), "MN119;")
    }

    func testSetMemoryChannelNumber_clampsAbove119() {
        XCTAssertEqual(KenwoodCAT.setMemoryChannelNumber(120), "MN119;")
    }

    func testSetMemoryChannelName_padsToTen() {
        let cmd = KenwoodCAT.setMemoryChannelName(0, name: "HI")
        XCTAssertEqual(cmd, "MA2000 HI        ;")
    }

    func testSetMemoryChannelName_truncatesAt10() {
        let cmd = KenwoodCAT.setMemoryChannelName(1, name: "ABCDEFGHIJK")
        XCTAssertEqual(cmd, "MA2001 ABCDEFGHIJ;")
    }

    // MARK: - MeterType formatting

    func testMeterType_smeter_belowS9() {
        XCTAssertEqual(KenwoodCAT.MeterType.smeter.formatValue(5), "S5")
    }

    func testMeterType_smeter_S9() {
        XCTAssertEqual(KenwoodCAT.MeterType.smeter.formatValue(9), "S9")
    }

    func testMeterType_smeter_overS9() {
        XCTAssertEqual(KenwoodCAT.MeterType.smeter.formatValue(10), "S9+10 dB")
        XCTAssertEqual(KenwoodCAT.MeterType.smeter.formatValue(19), "S9+100 dB")
    }

    func testMeterType_swr() {
        XCTAssertEqual(KenwoodCAT.MeterType.swr.formatValue(0),  "1.0:1")
        XCTAssertEqual(KenwoodCAT.MeterType.swr.formatValue(10), "2.0:1")
    }

    func testMeterType_power() {
        XCTAssertEqual(KenwoodCAT.MeterType.power.formatValue(100), "100 W")
    }

    func testMeterType_none_returnsTripleDash() {
        XCTAssertEqual(KenwoodCAT.MeterType.none_.formatValue(0), "---")
    }

    // MARK: - PTT

    func testPTT_down() {
        XCTAssertEqual(KenwoodCAT.pttDown(), "TX0;")
    }

    func testPTT_up() {
        XCTAssertEqual(KenwoodCAT.pttUp(), "RX;")
    }

    // MARK: - Operating Mode (OM)

    func testGetOperatingMode_defaultLeft() {
        XCTAssertEqual(KenwoodCAT.getOperatingMode(), "OM0;")
    }

    func testGetOperatingMode_right() {
        XCTAssertEqual(KenwoodCAT.getOperatingMode(.right), "OM1;")
    }

    func testSetOperatingMode_allModes() {
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.lsb), "OM01;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.usb), "OM02;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.cw),  "OM03;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.fm),  "OM04;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.am),  "OM05;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.fsk), "OM06;")
        XCTAssertEqual(KenwoodCAT.setOperatingMode(.cwR), "OM07;")
    }
}
