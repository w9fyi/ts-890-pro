import Foundation

enum KenwoodCAT {
    enum AutoInformationMode: Int {
        case off = 0
        /// AI ON (not backed up on radio power-off).
        case onNonPersistent = 2
        /// AI ON (backed up).
        case onPersistent = 4
    }

    static func getVFOAFrequency() -> String {
        "FA;"
    }

    static func setVFOAFrequencyHz(_ hz: Int) -> String {
        let clamped = max(0, min(hz, 999_999_999))
        return String(format: "FA%011d;", clamped)
    }

    static func getVFOBFrequency() -> String { "FB;" }

    static func setVFOBFrequencyHz(_ hz: Int) -> String {
        let clamped = max(0, min(hz, 999_999_999))
        return String(format: "FB%011d;", clamped)
    }

    static func setAutoInformation(_ mode: AutoInformationMode) -> String {
        "AI\(mode.rawValue);"
    }

    // MARK: - KNS VoIP Levels (requires administrator login for setting)

    static func getVoipInputLevel() -> String { "##KN30;" }
    static func getVoipOutputLevel() -> String { "##KN31;" }

    static func setVoipInputLevel(_ level: Int) -> String {
        let clamped = max(0, min(level, 100))
        return String(format: "##KN30%03d;", clamped)
    }

    static func setVoipOutputLevel(_ level: Int) -> String {
        let clamped = max(0, min(level, 100))
        return String(format: "##KN31%03d;", clamped)
    }

    // MARK: - AF Gain (Audio / Speaker Level)

    static func getAFGain() -> String { "AG;" }

    static func setAFGain(_ value: Int) -> String {
        let clamped = max(0, min(value, 255))
        return String(format: "AG%03d;", clamped)
    }

    // MARK: - Operating Mode (OM)

    enum FrequencyDisplayArea: Int {
        case left = 0
        case right = 1
    }

    enum OperatingMode: Int, CaseIterable {
        case lsb = 1
        case usb = 2
        case cw = 3
        case fm = 4
        case am = 5
        case fsk = 6
        case cwR = 7
        // 8 unused by TS-890S
        case fskR = 9
        case psk = 10
        case pskR = 11
        case lsbData = 12
        case usbData = 13
        case fmData = 14
        case amData = 15

        var label: String {
            switch self {
            case .lsb:     "LSB"
            case .usb:     "USB"
            case .cw:      "CW"
            case .fm:      "FM"
            case .am:      "AM"
            case .fsk:     "FSK"
            case .cwR:     "CW-R"
            case .fskR:    "FSK-R"
            case .psk:     "PSK"
            case .pskR:    "PSK-R"
            case .lsbData: "LSB-D"
            case .usbData: "USB-D"
            case .fmData:  "FM-D"
            case .amData:  "AM-D"
            }
        }
    }

    static func getOperatingMode(_ area: FrequencyDisplayArea = .left) -> String {
        "OM\(area.rawValue);"
    }

    static func setOperatingMode(_ mode: OperatingMode) -> String {
        // Kenwood notes P1 is ignored for setting; provide a placeholder.
        // Mode digit must be uppercase hex (A-F for data/PSK modes).
        String(format: "OM0%X;", mode.rawValue)
    }

    // MARK: - FreeDV mode configuration
    //
    // FreeDV HF modes use USB-DATA on the TS-890S (OM0D = USB-DATA, 0xD = 13).
    // MS001 = front panel mic, MS002 = USB audio codec, MS003 = LAN (KNS) audio.

    /// Commands to enter USB-DATA mode for FreeDV over LAN (KNS) audio.
    static func configureForFreeDVLan() -> [String] {
        ["OM0D;", "MS003;"]
    }

    /// Commands to enter USB-DATA mode for FreeDV over USB audio codec.
    static func configureForFreeDVUsb() -> [String] {
        ["OM0D;", "MS002;"]
    }

    /// Restore USB (plain) + front mic after FreeDV session.
    static func revertFromFreeDV(previousMode: String = "OM02;") -> [String] {
        [previousMode, "MS010;"]  // MS010 = P1=0(PTT), P2=1(Front Mic), P3=0(Rear OFF)
    }

    // MARK: - Mode / Data Mode (MD / DA)
    //
    // NOTE: Neither MD nor DA appear in the TS-890S PC Command Reference Rev.1.
    // MD is a legacy command from older Kenwood radios (TS-2000 etc.) not supported on TS-890S.
    // DA is absent from the TS-890S D-section entirely.
    // These functions are kept for response-parser compatibility only.
    // Do NOT call these as queries — the radio returns `?;`.
    static func getModeMD() -> String { "MD;" }
    static func setModeMD(_ value: Int) -> String { "MD\(value);" }

    static func getDataMode() -> String { "DA;" }
    static func setDataMode(enabled: Bool) -> String { "DA\(enabled ? 1 : 0);" }

    // MARK: - Noise Reduction / Notch

    enum NoiseReductionMode: Int {
        case off = 0
        case nr1 = 1
        case nr2 = 2

        var label: String {
            switch self {
            case .off: "Off"
            case .nr1: "NR1"
            case .nr2: "NR2"
            }
        }
    }

    static func getNoiseReduction() -> String { "NR;" }
    static func setNoiseReduction(_ mode: NoiseReductionMode) -> String { "NR\(mode.rawValue);" }

    static func getNotch() -> String { "NT;" }
    static func setNotch(enabled: Bool) -> String { "NT\(enabled ? 1 : 0);" }

    // MARK: - Squelch / Meter

    static func getSquelchLevel() -> String { "SQ;" }

    static func setSquelchLevel(_ level: Int) -> String {
        let clamped = max(0, min(level, 255))
        return String(format: "SQ%03d;", clamped)
    }

    static func getSMeter() -> String { "SM;" }

    // MARK: - RF Gain

    static func getRFGain() -> String { "RG;" }

    static func setRFGain(_ value: Int) -> String {
        // TS-890S PC Control command reference guide: 000..255
        let clamped = max(0, min(value, 255))
        return String(format: "RG%03d;", clamped)
    }

    // MARK: - PTT (TX/RX)

    static func pttDown() -> String {
        // "TX" starts transmission. Per command guide: TX0 = SEND/PTT.
        "TX0;"
    }

    static func pttUp() -> String {
        // "RX" returns to receive.
        "RX;"
    }

    // MARK: - VFO Selection / Split

    enum VFO: Int, CaseIterable {
        case a = 0
        case b = 1

        var label: String { self == .a ? "VFO A" : "VFO B" }
    }

    static func getReceiverVFO() -> String { "FR;" }
    static func setReceiverVFO(_ vfo: VFO) -> String { "FR\(vfo.rawValue);" }

    static func getTransmitterVFO() -> String { "FT;" }
    static func setTransmitterVFO(_ vfo: VFO) -> String { "FT\(vfo.rawValue);" }

    // MARK: - RIT / XIT

    static func ritGetState() -> String { "RT;" }
    static func ritSetEnabled(_ enabled: Bool) -> String { "RT\(enabled ? 1 : 0);" }

    static func xitGetState() -> String { "XT;" }
    static func xitSetEnabled(_ enabled: Bool) -> String { "XT\(enabled ? 1 : 0);" }

    static func ritXitClearOffset() -> String { "RC;" }
    static func ritXitGetOffset() -> String { "RF;" }

    static func ritXitStepUp() -> String { "RU;" }
    static func ritXitStepDown() -> String { "RD;" }

    static func ritXitSetOffsetHz(_ hz: Int) -> String {
        // RU is positive; RD is negative. P1 is 5 digits (0..9999).
        let absHz = max(0, min(abs(hz), 9_999))
        if hz >= 0 {
            return String(format: "RU%05d;", absHz)
        } else {
            return String(format: "RD%05d;", absHz)
        }
    }

    // MARK: - RX Filter Low/High Cut and Shift

    static func getReceiveFilterLowCutSettingID() -> String { "SL0;" }
    static func setReceiveFilterLowCutSettingID(_ id: Int) -> String {
        let clamped = max(0, min(id, 99))
        return String(format: "SL0%02d;", clamped)
    }

    static func getReceiveFilterHighCutSettingID() -> String { "SH0;" }
    static func setReceiveFilterHighCutSettingID(_ id: Int) -> String {
        let clamped = max(0, min(id, 999))
        return String(format: "SH0%03d;", clamped)
    }

    static func getReceiveFilterShift() -> String { "IS;" }

    static func setReceiveFilterShiftHz(_ hz: Int) -> String {
        // IS expects sign (+/-/space) and 4 digits. Radio clamps to legal ranges by mode.
        let clamped = max(-9_999, min(hz, 9_999))
        let sign = clamped < 0 ? "-" : "+"
        return String(format: "IS%@%04d;", sign, abs(clamped))
    }

    // MARK: - TX Power

    static func getOutputPower() -> String { "PC;" }
    static func setOutputPowerWatts(_ watts: Int) -> String {
        // HF/50: 5..100. (AM limits differ, but the radio will clamp/reject.)
        let clamped = max(5, min(watts, 100))
        return String(format: "PC%03d;", clamped)
    }

    // MARK: - Antenna Tuner (ATU)

    static func getAntennaTuner() -> String { "AC;" }

    static func setAntennaTuner(txEnabled: Bool) -> String {
        // Per PC Command guide notes: P1 is invalid for setting; enter 1.
        // P3: 0 stop tuning, 1 start tuning.
        return "AC1\(txEnabled ? 1 : 0)0;"
    }

    static func startAntennaTuning() -> String { "AC111;" }
    static func stopAntennaTuning(txEnabled: Bool) -> String { "AC1\(txEnabled ? 1 : 0)0;" }

    // MARK: - Split Offset Setting (kHz)

    static func getSplitOffsetSettingState() -> String { "SP;" }
    static func startSplitOffsetSetting() -> String { "SP1;" }
    static func cancelSplitOffsetSetting() -> String { "SP2;" }

    static func setSplitOffset(plus: Bool, khz: Int) -> String {
        let amount = max(1, min(khz, 9))
        let dir = plus ? 0 : 1
        // Setting 2: SP0 P2 P3;
        return "SP0\(dir)\(amount);"
    }

    // MARK: - Memory Channels

    static func getMemoryMode() -> String { "MV;" }

    static func setMemoryMode(_ enabled: Bool) -> String {
        // Single semicolon — the `；;` in the PDF reference is a fullwidth+halfwidth artifact.
        return "MV\(enabled ? 1 : 0);"
    }

    static func getMemoryChannelNumber() -> String { "MN;" }

    static func setMemoryChannelNumber(_ channel: Int) -> String {
        let clamped = max(0, min(channel, 119))
        return String(format: "MN%03d;", clamped)
    }

    static func getMemoryChannelConfiguration(_ channel: Int) -> String {
        let clamped = max(0, min(channel, 119))
        return String(format: "MA0%03d;", clamped)
    }

    static func setMemoryChannelDirectWriteFrequencyHz(_ hz: Int, mode: OperatingMode, fmNarrow: Bool) -> String {
        // MA1 writes to the currently selected memory channel (set with MN).
        // Format: MA1 + P1(11 digits Hz) + P2(mode) + P3(FM narrow) + ;
        let clamped = max(0, min(hz, 99_999_999_999))
        let narrow = fmNarrow ? 1 : 0
        return String(format: "MA1%011d%01d%01d;", clamped, mode.rawValue, narrow)
    }

    static func setMemoryChannelName(_ channel: Int, name: String) -> String {
        // MA2: MA2 + channel(3) + space + name(<=10) + ;
        let clamped = max(0, min(channel, 119))
        let safe = name.replacingOccurrences(of: ";", with: " ")
        let trimmed = String(safe.prefix(10))
        let padded = trimmed.padding(toLength: 10, withPad: " ", startingAt: 0)
        return String(format: "MA2%03d %@;", clamped, padded)
    }

    // MARK: - Extended Menu (EX) — menu settings, EQ, NB level, TX bandwidth, etc.
    //
    // TS-890S EX command format (5-digit parameter block):
    //   P1: Menu type — 0 = Regular Menu, 1 = Advanced Menu
    //   P2: Category number 00–99  (ignored / enter 00 for Advanced Menu)
    //   P3: Item number within category 00–99
    //   P4: Config mode — space = normal setting, 9 = reset to factory default
    //   P5: Value string (3-digit zero-padded for most; +/-nn for signed EQ dB)
    //
    // Read:  EX<P1><P2><P3>;           e.g.  EX00030;
    // Set:   EX<P1><P2><P3> <P5>;      e.g.  EX00030 005;   (note space = P4)
    // Response: EX<P1><P2><P3> <P5>;   e.g.  EX00030 005;
    //
    // menuNumber encoding used in this codebase:
    //   Regular menu  (P1=0):  menuNumber = P2*100 + P3
    //   Advanced menu (P1=1):  menuNumber = 10000 + P3   (P2 is always 00)
    //
    // Run Settings → Discover to scan all valid EX items from the radio and
    // confirm the correct P2/P3 for each function on your firmware version.

    static func getMenuValue(_ menuNumber: Int) -> String {
        if menuNumber >= 10000 {
            return String(format: "EX100%02d;", menuNumber - 10000)
        }
        return String(format: "EX0%02d%02d;", menuNumber / 100, menuNumber % 100)
    }

    /// Set a plain-integer menu value (0-padded to 3 digits, normal config P4=space).
    static func setMenuValue(_ menuNumber: Int, value: Int) -> String {
        if menuNumber >= 10000 {
            return String(format: "EX100%02d %03d;", menuNumber - 10000, value)
        }
        return String(format: "EX0%02d%02d %03d;", menuNumber / 100, menuNumber % 100, value)
    }

    // MARK: - Built-in Radio EQ (UT / UR — 18-band graphic EQ)
    //
    // TX EQ: UT<v01><v02>…<v18>;   each vN is a 2-digit zero-padded raw value 00–30
    // RX EQ: UR<v01><v02>…<v18>;   same encoding
    //
    // dB ↔ raw:  raw = 6 − dB  →  dB = 6 − raw
    // Range:  raw 00 = +6 dB,  raw 06 = 0 dB,  raw 30 = −24 dB
    //
    // Presets (TX: EQT, RX: EQR):
    //   Query current preset:  EQT0;  / EQR0;   → radio responds EQT0n; / EQR0n;
    //   Load preset n:         EQT1n; / EQR1n;  (follow with UT;/UR; to refresh bands)

    enum EQPreset: Int, CaseIterable, Identifiable {
        case highBoost1 = 0, highBoost2 = 1, formantPass = 2
        case bassBoost1 = 3, bassBoost2 = 4, conventional = 5
        case user1 = 6, user2 = 7, user3 = 8
        var id: Int { rawValue }
        var label: String {
            ["High Boost 1", "High Boost 2", "Formant Pass",
             "Bass Boost 1", "Bass Boost 2", "Conventional",
             "User 1", "User 2", "User 3"][rawValue]
        }
        /// RX label differs from TX at preset 5: EQR1 P1=5 = "Flat", EQT1 P1=5 = "Conventional".
        var rxLabel: String { rawValue == 5 ? "Flat" : label }
        /// Factory presets (0–5) cannot be permanently overwritten on the radio.
        var isFactory: Bool { rawValue < 6 }
    }

    /// Band center frequencies for the TS-890S 18-band EQ (UT/UR commands).
    /// Linear steps: P1 = 0 Hz, P2 = 300 Hz, … P18 = 5100 Hz (300 Hz spacing).
    /// Source: TS-890S PC Command Reference, UR/UT command parameter list.
    static let eqBandLabels: [String] = [
        "0 Hz", "300 Hz", "600 Hz", "900 Hz", "1200 Hz", "1500 Hz",
        "1800 Hz", "2100 Hz", "2400 Hz", "2700 Hz", "3000 Hz", "3300 Hz",
        "3600 Hz", "3900 Hz", "4200 Hz", "4500 Hz", "4800 Hz", "5100 Hz"
    ]

    /// Encode 18 dB values (clamped −24…+6) into the 36-character UT/UR wire payload.
    static func encodeBands(_ bands: [Int]) -> String {
        precondition(bands.count == 18)
        return bands.map { dB in
            let raw = max(0, min(30, 6 - dB))
            return String(format: "%02d", raw)
        }.joined()
    }

    /// Decode a 36-character UT/UR wire payload into 18 dB values, or nil on malformed input.
    static func decodeBands(_ payload: String) -> [Int]? {
        guard payload.count == 36 else { return nil }
        var result: [Int] = []
        var i = payload.startIndex
        while i < payload.endIndex {
            let end = payload.index(i, offsetBy: 2)
            guard let raw = Int(payload[i..<end]) else { return nil }
            result.append(6 - raw)
            i = end
        }
        return result.count == 18 ? result : nil
    }

    static func getTXEQ() -> String { "UT;" }
    static func setTXEQ(_ bands: [Int]) -> String { "UT\(encodeBands(bands));" }
    static func getRXEQ() -> String { "UR;" }
    static func setRXEQ(_ bands: [Int]) -> String { "UR\(encodeBands(bands));" }

    static func getTXEQPreset() -> String { "EQT1;" }  // EQT1 = TX effect preset selector (EQT0 = ON/OFF state — different command)
    static func setTXEQPreset(_ preset: EQPreset) -> String { "EQT1\(preset.rawValue);" }
    static func getRXEQPreset() -> String { "EQR1;" }  // EQR1 = RX effect preset selector (EQR0 = ON/OFF state — different command)
    static func setRXEQPreset(_ preset: EQPreset) -> String { "EQR1\(preset.rawValue);" }

    // MARK: - AGC (GC)

    enum AGCMode: Int, CaseIterable, Identifiable {
        // Raw values match the GC command: 0=OFF, 1=SLOW, 2=MID, 3=FAST (per PC Command Ref).
        case off = 0, slow = 1, mid = 2, fast = 3
        var id: Int { rawValue }
        var label: String { ["OFF", "SLOW", "MID", "FAST"][rawValue] }
        var next: AGCMode { AGCMode(rawValue: (rawValue + 1) % 4)! }
    }

    static func getAGC() -> String { "GC;" }
    static func setAGC(_ mode: AGCMode) -> String { "GC\(mode.rawValue);" }

    // MARK: - Attenuator (RA)
    // Format: RAn; where n = 0 (off), 1 (6 dB), 2 (12 dB), 3 (18 dB)

    enum AttenuatorLevel: Int, CaseIterable, Identifiable {
        case off = 0, db6 = 1, db12 = 2, db18 = 3
        var id: Int { rawValue }
        var label: String { ["Off", "6 dB", "12 dB", "18 dB"][rawValue] }
        var next: AttenuatorLevel { AttenuatorLevel(rawValue: (rawValue + 1) % 4)! }
    }

    static func getAttenuator() -> String { "RA;" }
    static func setAttenuator(_ level: AttenuatorLevel) -> String {
        "RA\(level.rawValue);"
    }

    // MARK: - Preamp (PA)

    enum PreampLevel: Int, CaseIterable, Identifiable {
        case off = 0, pre1 = 1, pre2 = 2
        var id: Int { rawValue }
        var label: String { ["Off", "PRE1", "PRE2"][rawValue] }
        var next: PreampLevel { PreampLevel(rawValue: (rawValue + 1) % 3)! }
    }

    static func getPreamp() -> String { "PA;" }
    static func setPreamp(_ level: PreampLevel) -> String { "PA\(level.rawValue);" }

    // MARK: - Filter Slot A/B/C (FL)
    // FL P1 P2; — P1=display area (0=left/main), P2=filter slot (0=A,1=B,2=C)
    // Read: FL0;  Set: FL0n; (e.g. FL01; = Filter B on main display)

    enum FilterSlot: Int, CaseIterable, Identifiable {
        case a = 0, b = 1, c = 2
        var id: Int { rawValue }
        var label: String { ["A", "B", "C"][rawValue] }
        var next: FilterSlot { FilterSlot(rawValue: (rawValue + 1) % 3)! }
    }

    static func getFilterSlot() -> String { "FL00;" }  // FL0P1; required — P1=0 queries slot A state
    static func setFilterSlot(_ slot: FilterSlot) -> String { "FL0\(slot.rawValue);" }

    // MARK: - Noise Blanker (NB1 / NB2)
    // TS-890S has two separate noise blankers. NB1 is the primary blanker.
    // Reference command names are NB1 and NB2 (not bare NB).

    static func getNoiseBlanker() -> String { "NB1;" }
    static func setNoiseBlanker(enabled: Bool) -> String { "NB1\(enabled ? 1 : 0);" }

    // MARK: - Beat Cancel (BC)

    enum BeatCancelMode: Int, CaseIterable, Identifiable {
        case off = 0, bc1 = 1, bc2 = 2
        var id: Int { rawValue }
        var label: String { ["Off", "BC1", "BC2"][rawValue] }
        var next: BeatCancelMode { BeatCancelMode(rawValue: (rawValue + 1) % 3)! }
    }

    static func getBeatCancel() -> String { "BC;" }
    static func setBeatCancel(_ mode: BeatCancelMode) -> String { "BC\(mode.rawValue);" }

    // MARK: - Mic Gain (MG)
    // Format: MG0nnn; where nnn = 000-100

    static func getMicGain() -> String { "MG;" }
    static func setMicGain(_ value: Int) -> String {
        let clamped = max(0, min(value, 100))
        return String(format: "MG%03d;", clamped)  // 3-digit, 000–100 per reference
    }

    // MARK: - VOX (VX)

    static func getVOX() -> String { "VX;" }
    static func setVOX(enabled: Bool) -> String { "VX\(enabled ? 1 : 0);" }

    // MARK: - Monitor Level (ML)
    // Format: MLnnn; where 000 = off, 001-100 = level

    static func getMonitorLevel() -> String { "ML;" }
    static func setMonitorLevel(_ level: Int) -> String {
        // Manual range: 000–020 (TS-890S PC Command Reference).
        let clamped = max(0, min(level, 20))
        return String(format: "ML%03d;", clamped)
    }

    // MARK: - Speech Processor (PR)

    static func getSpeechProc() -> String { "PR0;" }  // PR0 = ON/OFF command (bare PR; is invalid)
    static func setSpeechProc(enabled: Bool) -> String { "PR0\(enabled ? 1 : 0);" }  // PR00=off, PR01=on

    // MARK: - CW Key Speed (KS)
    // Format: KSnnn; where nnn = 004-100 WPM

    static func getCWSpeed() -> String { "KS;" }
    static func setCWSpeed(_ wpm: Int) -> String {
        // Manual range: 004–060 WPM (TS-890S PC Command Reference).
        let clamped = max(4, min(wpm, 60))
        return String(format: "KS%03d;", clamped)
    }

    // MARK: - CW Break-in (BI)

    enum CWBreakInMode: Int, CaseIterable, Identifiable {
        // BI only accepts P1=0 (OFF) or P1=1 (ON) — BI2 returns ?; on TS-890S firmware.
        // Semi/full delay timing is configured via the EX menu, not BI.
        case off = 0, on = 1
        var id: Int { rawValue }
        var label: String { ["Off", "On"][rawValue] }
        var next: CWBreakInMode { self == .off ? .on : .off }
    }

    static func getCWBreakIn() -> String { "BI;" }
    static func setCWBreakIn(_ mode: CWBreakInMode) -> String { "BI\(mode.rawValue);" }

    // MARK: - Meters (SM)
    // SM0 = S-meter (0-30), SM1 = COMP (0-30 dB), SM2 = ALC (0-30),
    // SM3 = SWR (0-30, divide by 10 for ratio), SM5 = TX Power (0-100 W)

    enum MeterType: String, CaseIterable, Identifiable, Codable {
        case smeter, compression, alc, swr, power, none_
        var id: String { rawValue }

        var smIndex: Int {
            switch self {
            case .smeter:      0
            case .compression: 1
            case .alc:         2
            case .swr:         3
            case .power:       5
            case .none_:      -1
            }
        }

        var label: String {
            switch self {
            case .smeter:      "S-Meter"
            case .power:       "TX Power"
            case .swr:         "SWR"
            case .alc:         "ALC"
            case .compression: "Compression"
            case .none_:       "(off)"
            }
        }

        /// Maximum raw value returned by the SM command for this type.
        var rawMax: Double {
            switch self {
            case .smeter, .compression, .alc, .swr: 30
            case .power:  100
            case .none_:  1
            }
        }

        /// Human-readable formatted value from raw SM reading.
        func formatValue(_ raw: Double) -> String {
            switch self {
            case .smeter:
                let s = Int(raw)
                if s <= 9 { return "S\(s)" }
                let overDB = (s - 9) * 10
                return "S9+\(overDB) dB"
            case .power:
                return "\(Int(raw)) W"
            case .swr:
                let ratio = 1.0 + raw / 10.0
                return String(format: "%.1f:1", ratio)
            case .alc:
                let pct = Int((raw / 30.0) * 100)
                return "\(pct)%"
            case .compression:
                return "\(Int(raw)) dB"
            case .none_:
                return "---"
            }
        }
    }

    static func getMeterValue(_ type: MeterType) -> String {
        guard type.smIndex >= 0 else { return "" }
        return "SM;"  // TS-890S: SM has no type selector — reads S-meter (RX) or power meter (TX)
    }

    // MARK: - Clock (CK) — verified against PC Command Reference Rev.1
    // CK0 = local clock date+time (combined, 2-digit year).
    // CK2 = local clock timezone offset (000–112, step=15 min, 056=UTC).
    // NOTE: CK3 = secondary clock timezone, CK4 = secondary clock identifier (NOT time/date).
    // CK0 is silently ignored by the radio when NTP auto-sync (CK6=1) is enabled.

    /// Set radio local clock date and time.  `CK0YYMMDDHHMMSS;`
    /// Year is 2-digit (18–99). Converts 4-digit year automatically.
    static func setClockDateTime(year: Int, month: Int, day: Int,
                                  hour: Int, minute: Int, second: Int) -> String {
        let yy = year % 100
        return String(format: "CK0%02d%02d%02d%02d%02d%02d;", yy, month, day, hour, minute, second)
    }

    /// Set local clock timezone offset.  `CK2NNN;`
    /// offsetMinutes: UTC offset in minutes (e.g. −300 for UTC−5, +330 for UTC+5:30).
    /// Radio scale: 000–112, step = 15 min, 056 = UTC.
    static func setLocalClockTimezone(offsetMinutes: Int) -> String {
        let steps = 56 + (offsetMinutes / 15)
        let clamped = min(112, max(0, steps))
        return String(format: "CK2%03d;", clamped)
    }

    /// Query radio local clock date and time.  `CK0;`
    static func getClockDateTime() -> String { "CK0;" }

    /// Trigger the radio to fetch time from its configured NTP server immediately.  `CK8;`
    /// Radio must have CK6=1 (auto-sync ON) and a valid NTP server set via CK7.
    static func triggerRadioNTPSync() -> String { "CK8;" }
}
