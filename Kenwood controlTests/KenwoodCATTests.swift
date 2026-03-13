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
        XCTAssertEqual(KenwoodCAT.setPreamp(.pre1), "PA1;")
    }

    func testSetPreamp_off() {
        XCTAssertEqual(KenwoodCAT.setPreamp(.off), "PA0;")
    }

    func testSetPreamp_pre2() {
        XCTAssertEqual(KenwoodCAT.setPreamp(.pre2), "PA2;")
    }

    // MARK: - AGC (GC)

    func testGetAGC() {
        XCTAssertEqual(KenwoodCAT.getAGC(), "GC;")
    }

    func testSetAGC_allModes() {
        // GC values per manual: 0=OFF, 1=SLOW, 2=MID, 3=FAST
        XCTAssertEqual(KenwoodCAT.setAGC(.off),  "GC0;")
        XCTAssertEqual(KenwoodCAT.setAGC(.slow), "GC1;")
        XCTAssertEqual(KenwoodCAT.setAGC(.mid),  "GC2;")
        XCTAssertEqual(KenwoodCAT.setAGC(.fast), "GC3;")
    }

    func testAGCMode_nextCyclesFourValues() {
        XCTAssertEqual(KenwoodCAT.AGCMode.off.next,  .slow)
        XCTAssertEqual(KenwoodCAT.AGCMode.slow.next, .mid)
        XCTAssertEqual(KenwoodCAT.AGCMode.mid.next,  .fast)
        XCTAssertEqual(KenwoodCAT.AGCMode.fast.next, .off)
    }

    // MARK: - Noise Blanker (NB)

    func testGetNoiseBlanker() {
        XCTAssertEqual(KenwoodCAT.getNoiseBlanker(), "NB1;")
    }

    func testSetNoiseBlanker_on() {
        XCTAssertEqual(KenwoodCAT.setNoiseBlanker(enabled: true), "NB11;")
    }

    func testSetNoiseBlanker_off() {
        XCTAssertEqual(KenwoodCAT.setNoiseBlanker(enabled: false), "NB10;")
    }

    // MARK: - Beat Cancel (BC)

    func testSetBeatCancel_on() {
        XCTAssertEqual(KenwoodCAT.setBeatCancel(.bc1), "BC1;")
    }

    func testSetBeatCancel_off() {
        XCTAssertEqual(KenwoodCAT.setBeatCancel(.off), "BC0;")
    }

    func testSetBeatCancel_bc2() {
        XCTAssertEqual(KenwoodCAT.setBeatCancel(.bc2), "BC2;")
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
        XCTAssertEqual(KenwoodCAT.setCWSpeed(60), "KS060;")
    }

    func testSetCWSpeed_clampsBelow4() {
        XCTAssertEqual(KenwoodCAT.setCWSpeed(0), "KS004;")
        XCTAssertEqual(KenwoodCAT.setCWSpeed(3), "KS004;")
    }

    func testSetCWSpeed_clampsAbove60() {
        XCTAssertEqual(KenwoodCAT.setCWSpeed(61),  "KS060;")  // manual max is 60 WPM
        XCTAssertEqual(KenwoodCAT.setCWSpeed(100), "KS060;")
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

    // MARK: - Built-in EQ band encoding (UT/UR)

    func testEncodeBands_flat() {
        // 0 dB → raw 6 → "06" × 18
        let flat = Array(repeating: 0, count: 18)
        XCTAssertEqual(KenwoodCAT.encodeBands(flat), String(repeating: "06", count: 18))
    }

    func testEncodeBands_maxGain() {
        // +6 dB → raw 0 → "00" × 18
        let max = Array(repeating: 6, count: 18)
        XCTAssertEqual(KenwoodCAT.encodeBands(max), String(repeating: "00", count: 18))
    }

    func testEncodeBands_maxCut() {
        // −24 dB → raw 30 → "30" × 18
        let cut = Array(repeating: -24, count: 18)
        XCTAssertEqual(KenwoodCAT.encodeBands(cut), String(repeating: "30", count: 18))
    }

    func testDecodeBands_roundTrip() {
        let original = [6, 3, 0, -3, -6, -12, -24, 6, 0, -6, 3, -3, 0, 6, -24, 0, 0, 0]
        XCTAssertEqual(KenwoodCAT.decodeBands(KenwoodCAT.encodeBands(original)), original)
    }

    func testDecodeBands_invalidLength_returnsNil() {
        XCTAssertNil(KenwoodCAT.decodeBands("0606"))
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

    // MARK: - Auto Information (AI)

    func testSetAutoInformation_allModes() {
        XCTAssertEqual(KenwoodCAT.setAutoInformation(.off),            "AI0;")
        XCTAssertEqual(KenwoodCAT.setAutoInformation(.onNonPersistent),"AI2;")
        XCTAssertEqual(KenwoodCAT.setAutoInformation(.onPersistent),   "AI4;")
    }

    // MARK: - VoIP Levels (##KN3)

    func testGetVoipInputLevel() {
        XCTAssertEqual(KenwoodCAT.getVoipInputLevel(),  "##KN30;")
    }

    func testGetVoipOutputLevel() {
        XCTAssertEqual(KenwoodCAT.getVoipOutputLevel(), "##KN31;")
    }

    func testSetVoipInputLevel_typical() {
        XCTAssertEqual(KenwoodCAT.setVoipInputLevel(50),  "##KN30050;")
        XCTAssertEqual(KenwoodCAT.setVoipInputLevel(0),   "##KN30000;")
        XCTAssertEqual(KenwoodCAT.setVoipInputLevel(100), "##KN30100;")
    }

    func testSetVoipInputLevel_clamping() {
        XCTAssertEqual(KenwoodCAT.setVoipInputLevel(-1),  "##KN30000;")
        XCTAssertEqual(KenwoodCAT.setVoipInputLevel(101), "##KN30100;")
    }

    func testSetVoipOutputLevel_typical() {
        XCTAssertEqual(KenwoodCAT.setVoipOutputLevel(75), "##KN31075;")
    }

    func testSetVoipOutputLevel_clamping() {
        XCTAssertEqual(KenwoodCAT.setVoipOutputLevel(-5),  "##KN31000;")
        XCTAssertEqual(KenwoodCAT.setVoipOutputLevel(200), "##KN31100;")
    }

    // MARK: - AF Gain query

    func testGetAFGain() {
        XCTAssertEqual(KenwoodCAT.getAFGain(), "AG;")
    }

    // MARK: - Noise Reduction (NR)

    func testGetNoiseReduction() {
        XCTAssertEqual(KenwoodCAT.getNoiseReduction(), "NR;")
    }

    func testSetNoiseReduction_allModes() {
        XCTAssertEqual(KenwoodCAT.setNoiseReduction(.off), "NR0;")
        XCTAssertEqual(KenwoodCAT.setNoiseReduction(.nr1), "NR1;")
        XCTAssertEqual(KenwoodCAT.setNoiseReduction(.nr2), "NR2;")
    }

    func testNoiseReductionMode_labels() {
        XCTAssertEqual(KenwoodCAT.NoiseReductionMode.off.label, "Off")
        XCTAssertEqual(KenwoodCAT.NoiseReductionMode.nr1.label, "NR1")
        XCTAssertEqual(KenwoodCAT.NoiseReductionMode.nr2.label, "NR2")
    }

    // MARK: - Notch (NT)

    func testGetNotch() {
        XCTAssertEqual(KenwoodCAT.getNotch(), "NT;")
    }

    func testSetNotch_on() {
        XCTAssertEqual(KenwoodCAT.setNotch(enabled: true),  "NT1;")
    }

    func testSetNotch_off() {
        XCTAssertEqual(KenwoodCAT.setNotch(enabled: false), "NT0;")
    }

    // MARK: - Squelch (SQ)

    func testGetSquelchLevel() {
        XCTAssertEqual(KenwoodCAT.getSquelchLevel(), "SQ;")
    }

    func testSetSquelchLevel_typical() {
        XCTAssertEqual(KenwoodCAT.setSquelchLevel(0),   "SQ000;")
        XCTAssertEqual(KenwoodCAT.setSquelchLevel(128), "SQ128;")
        XCTAssertEqual(KenwoodCAT.setSquelchLevel(255), "SQ255;")
    }

    func testSetSquelchLevel_clamping() {
        XCTAssertEqual(KenwoodCAT.setSquelchLevel(-1),  "SQ000;")
        XCTAssertEqual(KenwoodCAT.setSquelchLevel(256), "SQ255;")
    }

    // MARK: - S-Meter query

    func testGetSMeter() {
        XCTAssertEqual(KenwoodCAT.getSMeter(), "SM;")
    }

    func testGetMeterValue_smeter() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.smeter),      "SM;")
    }

    func testGetMeterValue_compression() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.compression), "SM;")
    }

    func testGetMeterValue_alc() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.alc),         "SM;")
    }

    func testGetMeterValue_swr() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.swr),         "SM;")
    }

    func testGetMeterValue_power() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.power),       "SM;")
    }

    func testGetMeterValue_none_returnsEmpty() {
        XCTAssertEqual(KenwoodCAT.getMeterValue(.none_), "")
    }

    func testMeterType_alc_formatValue() {
        XCTAssertEqual(KenwoodCAT.MeterType.alc.formatValue(0),  "0%")
        XCTAssertEqual(KenwoodCAT.MeterType.alc.formatValue(30), "100%")
    }

    func testMeterType_compression_formatValue() {
        XCTAssertEqual(KenwoodCAT.MeterType.compression.formatValue(10), "10 dB")
    }

    // MARK: - RF Gain query

    func testGetRFGain() {
        XCTAssertEqual(KenwoodCAT.getRFGain(), "RG;")
    }

    // MARK: - VFO Selection (FR / FT)

    func testGetReceiverVFO() {
        XCTAssertEqual(KenwoodCAT.getReceiverVFO(), "FR;")
    }

    func testSetReceiverVFO() {
        XCTAssertEqual(KenwoodCAT.setReceiverVFO(.a), "FR0;")
        XCTAssertEqual(KenwoodCAT.setReceiverVFO(.b), "FR1;")
    }

    func testGetTransmitterVFO() {
        XCTAssertEqual(KenwoodCAT.getTransmitterVFO(), "FT;")
    }

    func testSetTransmitterVFO() {
        XCTAssertEqual(KenwoodCAT.setTransmitterVFO(.a), "FT0;")
        XCTAssertEqual(KenwoodCAT.setTransmitterVFO(.b), "FT1;")
    }

    func testVFO_labels() {
        XCTAssertEqual(KenwoodCAT.VFO.a.label, "VFO A")
        XCTAssertEqual(KenwoodCAT.VFO.b.label, "VFO B")
    }

    // MARK: - RIT / XIT state commands

    func testRitGetState() {
        XCTAssertEqual(KenwoodCAT.ritGetState(), "RT;")
    }

    func testRitSetEnabled() {
        XCTAssertEqual(KenwoodCAT.ritSetEnabled(true),  "RT1;")
        XCTAssertEqual(KenwoodCAT.ritSetEnabled(false), "RT0;")
    }

    func testXitGetState() {
        XCTAssertEqual(KenwoodCAT.xitGetState(), "XT;")
    }

    func testXitSetEnabled() {
        XCTAssertEqual(KenwoodCAT.xitSetEnabled(true),  "XT1;")
        XCTAssertEqual(KenwoodCAT.xitSetEnabled(false), "XT0;")
    }

    func testRitXitClearOffset() {
        XCTAssertEqual(KenwoodCAT.ritXitClearOffset(), "RC;")
    }

    func testRitXitGetOffset() {
        XCTAssertEqual(KenwoodCAT.ritXitGetOffset(), "RF;")
    }

    func testRitXitStepUp() {
        XCTAssertEqual(KenwoodCAT.ritXitStepUp(), "RU;")
    }

    func testRitXitStepDown() {
        XCTAssertEqual(KenwoodCAT.ritXitStepDown(), "RD;")
    }

    // MARK: - RX Filter Low/High Cut (SL / SH)

    func testGetReceiveFilterLowCutSettingID() {
        XCTAssertEqual(KenwoodCAT.getReceiveFilterLowCutSettingID(), "SL0;")
    }

    func testSetReceiveFilterLowCutSettingID_typical() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterLowCutSettingID(5),  "SL005;")
        XCTAssertEqual(KenwoodCAT.setReceiveFilterLowCutSettingID(0),  "SL000;")
        XCTAssertEqual(KenwoodCAT.setReceiveFilterLowCutSettingID(99), "SL099;")
    }

    func testSetReceiveFilterLowCutSettingID_clamping() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterLowCutSettingID(-1),  "SL000;")
        XCTAssertEqual(KenwoodCAT.setReceiveFilterLowCutSettingID(100), "SL099;")
    }

    func testGetReceiveFilterHighCutSettingID() {
        XCTAssertEqual(KenwoodCAT.getReceiveFilterHighCutSettingID(), "SH0;")
    }

    func testSetReceiveFilterHighCutSettingID_typical() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterHighCutSettingID(10),  "SH0010;")
        XCTAssertEqual(KenwoodCAT.setReceiveFilterHighCutSettingID(999), "SH0999;")
    }

    func testSetReceiveFilterHighCutSettingID_clamping() {
        XCTAssertEqual(KenwoodCAT.setReceiveFilterHighCutSettingID(-1),   "SH0000;")
        XCTAssertEqual(KenwoodCAT.setReceiveFilterHighCutSettingID(1000), "SH0999;")
    }

    func testGetReceiveFilterShift() {
        XCTAssertEqual(KenwoodCAT.getReceiveFilterShift(), "IS;")
    }

    // MARK: - Antenna Tuner (AC)

    func testGetAntennaTuner() {
        XCTAssertEqual(KenwoodCAT.getAntennaTuner(), "AC;")
    }

    func testSetAntennaTuner_txEnabled() {
        XCTAssertEqual(KenwoodCAT.setAntennaTuner(txEnabled: true),  "AC110;")
    }

    func testSetAntennaTuner_txDisabled() {
        XCTAssertEqual(KenwoodCAT.setAntennaTuner(txEnabled: false), "AC100;")
    }

    func testStartAntennaTuning() {
        XCTAssertEqual(KenwoodCAT.startAntennaTuning(), "AC111;")
    }

    func testStopAntennaTuning_txEnabled() {
        XCTAssertEqual(KenwoodCAT.stopAntennaTuning(txEnabled: true),  "AC110;")
    }

    func testStopAntennaTuning_txDisabled() {
        XCTAssertEqual(KenwoodCAT.stopAntennaTuning(txEnabled: false), "AC100;")
    }

    // MARK: - Split Offset (SP)

    func testGetSplitOffsetSettingState() {
        XCTAssertEqual(KenwoodCAT.getSplitOffsetSettingState(), "SP;")
    }

    func testStartSplitOffsetSetting() {
        XCTAssertEqual(KenwoodCAT.startSplitOffsetSetting(), "SP1;")
    }

    func testCancelSplitOffsetSetting() {
        XCTAssertEqual(KenwoodCAT.cancelSplitOffsetSetting(), "SP2;")
    }

    func testSetSplitOffset_plus() {
        XCTAssertEqual(KenwoodCAT.setSplitOffset(plus: true,  khz: 5), "SP005;")
    }

    func testSetSplitOffset_minus() {
        XCTAssertEqual(KenwoodCAT.setSplitOffset(plus: false, khz: 3), "SP013;")
    }

    func testSetSplitOffset_clampsKhz() {
        XCTAssertEqual(KenwoodCAT.setSplitOffset(plus: true, khz: 0), "SP001;")  // min 1
        XCTAssertEqual(KenwoodCAT.setSplitOffset(plus: true, khz: 99), "SP009;") // max 9
    }

    // MARK: - Memory Mode (MV)

    func testGetMemoryMode() {
        XCTAssertEqual(KenwoodCAT.getMemoryMode(), "MV;")
    }

    func testSetMemoryMode_enabled() {
        XCTAssertEqual(KenwoodCAT.setMemoryMode(true),  "MV1;")
    }

    func testSetMemoryMode_disabled() {
        XCTAssertEqual(KenwoodCAT.setMemoryMode(false), "MV0;")
    }

    // MARK: - Memory Channel (MN / MA)

    func testGetMemoryChannelNumber() {
        XCTAssertEqual(KenwoodCAT.getMemoryChannelNumber(), "MN;")
    }

    func testGetMemoryChannelConfiguration_typical() {
        XCTAssertEqual(KenwoodCAT.getMemoryChannelConfiguration(5),   "MA0005;")
        XCTAssertEqual(KenwoodCAT.getMemoryChannelConfiguration(119), "MA0119;")
    }

    func testGetMemoryChannelConfiguration_clamping() {
        XCTAssertEqual(KenwoodCAT.getMemoryChannelConfiguration(-1),  "MA0000;")
        XCTAssertEqual(KenwoodCAT.getMemoryChannelConfiguration(120), "MA0119;")
    }

    func testSetMemoryChannelDirectWriteFrequencyHz_usb() {
        let cmd = KenwoodCAT.setMemoryChannelDirectWriteFrequencyHz(14_225_000, mode: .usb, fmNarrow: false)
        XCTAssertEqual(cmd, "MA10001422500020;")
    }

    func testSetMemoryChannelDirectWriteFrequencyHz_fmNarrow() {
        let cmd = KenwoodCAT.setMemoryChannelDirectWriteFrequencyHz(146_520_000, mode: .fm, fmNarrow: true)
        XCTAssertEqual(cmd, "MA10014652000041;")
    }

    // MARK: - Extended Menu (EX)

    func testGetMenuValue() {
        XCTAssertEqual(KenwoodCAT.getMenuValue(30), "EX00030;")
        XCTAssertEqual(KenwoodCAT.getMenuValue(62), "EX00062;")
    }

    func testSetMenuValue() {
        XCTAssertEqual(KenwoodCAT.setMenuValue(30, value: 5), "EX00030 005;")
    }

    // MARK: - UT/UR EQ commands

    func testGetTXEQ_command() {
        XCTAssertEqual(KenwoodCAT.getTXEQ(), "UT;")
    }

    func testGetRXEQ_command() {
        XCTAssertEqual(KenwoodCAT.getRXEQ(), "UR;")
    }

    func testSetTXEQ_producesCorrectFormat() {
        let flat = Array(repeating: 0, count: 18)
        let cmd = KenwoodCAT.setTXEQ(flat)
        XCTAssertTrue(cmd.hasPrefix("UT"), "TX EQ set command must start with UT")
        XCTAssertTrue(cmd.hasSuffix(";"))
        XCTAssertEqual(cmd.count, 39, "UT + 36 digits + semicolon")
    }

    func testSetRXEQ_producesCorrectFormat() {
        let flat = Array(repeating: 0, count: 18)
        let cmd = KenwoodCAT.setRXEQ(flat)
        XCTAssertTrue(cmd.hasPrefix("UR"), "RX EQ set command must start with UR")
        XCTAssertEqual(cmd.count, 39)
    }

    func testGetTXEQPreset_command() {
        XCTAssertEqual(KenwoodCAT.getTXEQPreset(), "EQT1;")
    }

    func testGetRXEQPreset_command() {
        XCTAssertEqual(KenwoodCAT.getRXEQPreset(), "EQR1;")
    }

    func testSetTXEQPreset_command() {
        XCTAssertEqual(KenwoodCAT.setTXEQPreset(.highBoost1),   "EQT10;")
        XCTAssertEqual(KenwoodCAT.setTXEQPreset(.conventional), "EQT15;")
        XCTAssertEqual(KenwoodCAT.setTXEQPreset(.user1),        "EQT16;")
    }

    func testSetRXEQPreset_command() {
        XCTAssertEqual(KenwoodCAT.setRXEQPreset(.formantPass), "EQR12;")
        XCTAssertEqual(KenwoodCAT.setRXEQPreset(.user3),       "EQR18;")
    }

    func testEQPreset_isFactory() {
        XCTAssertTrue(KenwoodCAT.EQPreset.highBoost1.isFactory)
        XCTAssertTrue(KenwoodCAT.EQPreset.conventional.isFactory)
        XCTAssertFalse(KenwoodCAT.EQPreset.user1.isFactory)
        XCTAssertFalse(KenwoodCAT.EQPreset.user3.isFactory)
    }

    // MARK: - Beat Cancel query

    func testGetBeatCancel() {
        XCTAssertEqual(KenwoodCAT.getBeatCancel(), "BC;")
    }

    // MARK: - Mic Gain (MG)

    func testGetMicGain() {
        XCTAssertEqual(KenwoodCAT.getMicGain(), "MG;")
    }

    func testSetMicGain_typical() {
        XCTAssertEqual(KenwoodCAT.setMicGain(50),  "MG050;")
        XCTAssertEqual(KenwoodCAT.setMicGain(0),   "MG000;")
        XCTAssertEqual(KenwoodCAT.setMicGain(100), "MG100;")
    }

    func testSetMicGain_clamping() {
        XCTAssertEqual(KenwoodCAT.setMicGain(-1),  "MG000;")
        XCTAssertEqual(KenwoodCAT.setMicGain(101), "MG100;")
    }

    // MARK: - VOX (VX)

    func testGetVOX() {
        XCTAssertEqual(KenwoodCAT.getVOX(), "VX;")
    }

    func testSetVOX_on() {
        XCTAssertEqual(KenwoodCAT.setVOX(enabled: true),  "VX1;")
    }

    func testSetVOX_off() {
        XCTAssertEqual(KenwoodCAT.setVOX(enabled: false), "VX0;")
    }

    // MARK: - Monitor Level (ML)

    func testGetMonitorLevel() {
        XCTAssertEqual(KenwoodCAT.getMonitorLevel(), "ML;")
    }

    func testSetMonitorLevel_typical() {
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(0),  "ML000;")
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(10), "ML010;")
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(20), "ML020;")
    }

    func testSetMonitorLevel_clamping() {
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(-1), "ML000;")
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(21), "ML020;")  // manual max is 20
        XCTAssertEqual(KenwoodCAT.setMonitorLevel(100), "ML020;")
    }

    // MARK: - Speech Processor (PR)

    func testGetSpeechProc() {
        XCTAssertEqual(KenwoodCAT.getSpeechProc(), "PR0;")
    }

    func testSetSpeechProc_on() {
        XCTAssertEqual(KenwoodCAT.setSpeechProc(enabled: true),  "PR01;")
    }

    func testSetSpeechProc_off() {
        XCTAssertEqual(KenwoodCAT.setSpeechProc(enabled: false), "PR00;")
    }

    // MARK: - CW Break-in (BI)

    func testGetCWBreakIn() {
        XCTAssertEqual(KenwoodCAT.getCWBreakIn(), "BI;")
    }

    func testSetCWBreakIn_allModes() {
        // BI2 returns ?; on hardware — only 0=OFF and 1=ON are valid (confirmed 2026-03-12).
        XCTAssertEqual(KenwoodCAT.setCWBreakIn(.off), "BI0;")
        XCTAssertEqual(KenwoodCAT.setCWBreakIn(.on),  "BI1;")
    }

    func testCWBreakInMode_nextCycles() {
        XCTAssertEqual(KenwoodCAT.CWBreakInMode.off.next, .on)
        XCTAssertEqual(KenwoodCAT.CWBreakInMode.on.next,  .off)
    }

    func testCWBreakInMode_labels() {
        XCTAssertEqual(KenwoodCAT.CWBreakInMode.off.label, "Off")
        XCTAssertEqual(KenwoodCAT.CWBreakInMode.on.label,  "On")
    }

    // MARK: - CW Speed query

    func testGetCWSpeed() {
        XCTAssertEqual(KenwoodCAT.getCWSpeed(), "KS;")
    }

    // MARK: - FreeDV mode configuration

    func testConfigureForFreeDVLan() {
        XCTAssertEqual(KenwoodCAT.configureForFreeDVLan(), ["OM0D;", "MS003;"])
    }

    func testConfigureForFreeDVUsb() {
        XCTAssertEqual(KenwoodCAT.configureForFreeDVUsb(), ["OM0D;", "MS002;"])
    }

    func testRevertFromFreeDV_defaultMode() {
        XCTAssertEqual(KenwoodCAT.revertFromFreeDV(), ["OM02;", "MS010;"])
    }

    func testRevertFromFreeDV_customPreviousMode() {
        XCTAssertEqual(KenwoodCAT.revertFromFreeDV(previousMode: "OM03;"), ["OM03;", "MS010;"])
    }

    // MARK: - MD / DA commands

    func testGetModeMD() {
        XCTAssertEqual(KenwoodCAT.getModeMD(), "MD;")
    }

    func testSetModeMD() {
        XCTAssertEqual(KenwoodCAT.setModeMD(2), "MD2;")
        XCTAssertEqual(KenwoodCAT.setModeMD(0), "MD0;")
    }

    func testGetDataMode() {
        XCTAssertEqual(KenwoodCAT.getDataMode(), "DA;")
    }

    func testSetDataMode() {
        XCTAssertEqual(KenwoodCAT.setDataMode(enabled: true),  "DA1;")
        XCTAssertEqual(KenwoodCAT.setDataMode(enabled: false), "DA0;")
    }
}
