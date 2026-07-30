// KenwoodCapabilities.swift
// TS-890 Pro — multi-radio capability model
//
// Identifies the connected radio from the ID; response and exposes feature
// flags so the rest of the app can gate model-specific behaviour without
// scattering if/else chains everywhere.

import Foundation

// MARK: - Radio model identity

enum KenwoodRadioModel: String, CustomStringConvertible {
    case ts590s  = "021"   // TS-590S
    case ts590sg = "023"   // TS-590SG
    case ts890s  = "024"   // TS-890S  (primary target)
    case ts990s  = "022"   // TS-990S (019 is the TS-2000 — not this radio)
    case unknown = "000"

    var description: String {
        switch self {
        case .ts590s:  return "TS-590S"
        case .ts590sg: return "TS-590SG"
        case .ts890s:  return "TS-890S"
        case .ts990s:  return "TS-990S"
        case .unknown: return "Unknown"
        }
    }

    /// Parse the bare ID response string (e.g. "ID024;" or "024").
    init(idResponse: String) {
        let stripped = idResponse
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: "")
        // Core may arrive as "ID024" or just "024"
        let digits: String
        if stripped.uppercased().hasPrefix("ID") {
            digits = String(stripped.dropFirst(2))
        } else {
            digits = stripped
        }
        self = KenwoodRadioModel(rawValue: digits) ?? .unknown
    }
}

// MARK: - Capability flags

struct KenwoodCapabilities {

    let model: KenwoodRadioModel

    /// Radio accepts KNS LAN TCP connections (##CN/##ID handshake).
    let hasLAN: Bool

    /// LAN audio streaming supported (##VP1 / ##KN30 / ##KN31).
    /// TS-890S only — TS-990S has LAN CAT but no audio stream.
    let hasLANAudio: Bool

    /// Character encoding used for KNS LAN frames.
    let lanEncoding: LANEncoding

    /// Use OM command for operating mode (TS-890S, TS-990S).
    /// When false, use MD command (TS-590S, TS-590SG).
    let useOMCommand: Bool

    /// OM command exposes PSK modes A-F (TS-890S, TS-990S).
    let hasPSKModes: Bool

    /// Band-scope commands BS*/DD* available (TS-890S, TS-990S).
    let hasScope: Bool

    /// Sub-receiver / dual watch via SB command (TS-990S only).
    let hasDualReceive: Bool

    /// 18-band graphic EQ band-level commands (UT/UR) available.
    /// Common to TS-890S/990S/590S/590SG (590S needs FW ≥ 2.00 and the EQ
    /// enabled in the menu — the radio errors otherwise, which is harmless).
    let has18BandEQ: Bool

    /// MS (Audio Source Select) command available (TS-890S, TS-990S).
    let hasAudioSourceSelect: Bool

    /// Morse decoder CD0/CD1/CD2 command available (TS-590SG).
    let hasMorseDecoder: Bool

    /// KNS login protocol (##CN/##ID with KNS account types).
    /// TS-990S (original KNS radio) and TS-890S. TS-590S has no LAN.
    let hasKNS: Bool

    /// Auto-Information command string to send after connect.
    /// TS-890S/990S: "AI4;" (backed up, survives reconnect).
    /// TS-590S/SG: "AI2;" (non-persistent, AI4 not supported).
    let aiCommand: String

    /// Dual noise blanker system (NB1/NB2/NBT/NBD/NBW/NL1/NL2).
    /// TS-890S/990S have this. TS-590S has simple NB/NL only.
    let hasDualNoiseBlanker: Bool

    /// EX menu command format differs by radio.
    let exMenuFormat: EXMenuFormat

    /// Whether the radio supports APF (Audio Peak Filter) commands (AP0–AP3).
    /// TS-890S: yes. TS-590S/990S: no (590 has APF but not via CAT; 990 TBD).
    let hasAPFCommands: Bool

    /// Whether the radio supports the DA (Data mode) command.
    /// TS-590S: yes (DA0/DA1 overlays data mode on MD). TS-890S/990S: no (use OM).
    let hasDataModeCommand: Bool

    /// Whether the radio supports monitor commands MO0/MO1/MO2.
    /// TS-890S: yes. TS-590S: no (has ML for monitor level only).
    let hasMonitorCommands: Bool

    /// Maximum TX power in watts. TS-590S: 100W HF/50W 6m. TS-890S: 100W. TS-990S: 200W.
    let maxTXPowerWatts: Int

    /// Commands like AG, SQ, SM, NR, RG require a leading band parameter (0=Main, 1=Sub).
    /// TS-990S: true (dual independent receivers). All others: false.
    let usesBandPrefix: Bool

    /// Uses CB (Operating Band) / TB (Transmit Band) instead of FR/FT (Receiver/Transmitter VFO).
    /// TS-990S: true. All others: false.
    let usesCBTB: Bool

    // MARK: - TS-590S/SG serial dialect (derived)
    //
    // The TS-590S and TS-590SG share an older CAT dialect where many commands
    // have different parameter widths or read syntax than the TS-890S/990S.
    // These are derived from the model so the factory initializers stay small.

    /// TS-590S/SG share a distinct command dialect (see the per-command notes below).
    var is590Family: Bool { model == .ts590s || model == .ts590sg }

    /// Maximum raw S-meter dot count returned by SM. TS-590S/SG: 30. TS-890S/990S: 70.
    var sMeterMax: Int { is590Family ? 30 : 70 }

    /// AG/SQ/SM require a leading "0" parameter on the TS-590S/SG — the same wire
    /// format as the TS-990S band-prefixed variants with band 0. RG/NR take no
    /// prefix on the 590 (unlike the 990).
    var agSqSmNeedZeroParam: Bool { usesBandPrefix || is590Family }

    /// RF (read RIT/XIT offset) exists on TS-890S only. On the 590 the offset is
    /// only readable from the IF status response (chars 17–21).
    var hasRFCommand: Bool { !is590Family }

    /// Poll IF; for RIT offset / TX state / split / scan (TS-590S/SG). The IF
    /// command is absent from the TS-890S rev1 reference.
    var usesIFStatusPolling: Bool { is590Family }

    /// TS-590S/SG attenuator is a single 12 dB on/off: RA{2 digits} 00/01.
    /// TS-890S: RA{1 digit} 0–3 (off/6/12/18 dB).
    var attenuatorIsOnOff: Bool { is590Family }

    /// Highest valid PA (preamp) value. TS-890S: 2 (PRE1/PRE2). TS-590S/SG: 1 (on/off).
    var preampMaxLevel: Int { is590Family ? 1 : 2 }

    /// TS-890S GC: 0=OFF 1=SLOW 2=MID 3=FAST. TS-590S/SG GC: 0=OFF 1=SLOW 2=FAST (no MID).
    var agcHasMid: Bool { !is590Family }

    /// TS-590S/SG SL/SH use bare 2-digit codes (00–13) and FW for CW/FSK width.
    /// TS-890S uses SL{type}{2-digit} / SH{type}{3-digit} IDs.
    var filterUses590Codes: Bool { is590Family }

    /// TS-590S/SG FL: read "FL;", set FL{1=A,2=B}. TS-890S FL0{n} with n=0/1/2.
    var filterSlotUses590FL: Bool { is590Family }

    /// TS-590S/SG memory channels use MC (channel) + MR/MW (50-char record) and
    /// FR2 for memory mode. TS-890S uses MV/MN/MA0–MA7.
    var memoryUses590Commands: Bool { is590Family }

    /// TF1/TF2 (TX filter read) — TS-890S only.
    var hasTXFilterCommands: Bool { !is590Family }

    /// DV (DATA VOX source) — TS-890S only. On the 590 DATA VOX is a menu item.
    var hasDataVOXCommand: Bool { !is590Family }

    /// Bare NB read/set (NB;/NB{n}) — TS-590S/SG. "NB1;" is a SET on the 590!
    var noiseBlankerUsesBareNB: Bool { is590Family }

    /// Bare RL (NR level, 2 digits) — TS-590S/SG. TS-890S uses RL1/RL2.
    var nrLevelUsesBareRL: Bool { is590Family }

    /// Bare PR read/set (PR;/PR{n}) — TS-590S/SG. "PR0;" is a SET (proc off) on the 590!
    var speechProcUsesBarePR: Bool { is590Family }

    /// Bare SC read (SC;) — TS-590S/SG. "SC1;" STARTS A SCAN on the 590!
    var scanUsesBareSC: Bool { is590Family }

    /// TS-590S/SG VOX commands: VD{4 digits, ms 0–3000} / VG{3 digits, 0–9},
    /// no per-input-type prefix and no anti-VOX (VG1) command.
    var voxUses590Format: Bool { is590Family }

    /// TS-590S/SG LK set takes two digits (LK{P1}{P2}, P2 always 0).
    var lockSetUsesTwoDigits: Bool { is590Family }

    /// TS-590S/SG AN takes three parameters (no antennaOut P4).
    var antennaUses3Params: Bool { is590Family }

    /// BD/BU on the 590 are set-only band select (2-digit). No read form.
    var hasBandDirectRead: Bool { !is590Family }

    /// TS-590S/SG NT carries a bandwidth P2 and P1 can be 2 (manual notch).
    var notchHasManualMode: Bool { is590Family }

    /// NW (notch width) — TS-890S only.
    var hasNotchWidthCommand: Bool { !is590Family }

    /// PT (CW pitch) — TS-890S/990S. On the 590 pitch is a menu item.
    var hasCWPitchCommand: Bool { !is590Family }

    /// BI (CW break-in on/off) — TS-890S. The 590 uses VX in CW mode.
    var hasBreakInCommand: Bool { !is590Family }

    /// EQT/EQR preset commands — TS-890S/990S. The 590 selects EQ curves via
    /// the EQ command / menu (UT/UR band levels are common to all).
    var hasEQPresetCommands: Bool { !is590Family }

    /// Key digital-mode TX with TX1 (DATA SEND — modulates from ACC2/USB input).
    /// The 590 has no MS routing command, so TX0 would always take the front mic.
    var dataTXUsesTX1: Bool { is590Family }

    /// EX menu number for "DATA modulation line" (ACC2/USB rear input select).
    /// Needed for digital TX over the USB audio codec. TS-590S: 063, TS-590SG: 069.
    var dataModulationLineMenu: Int? {
        switch model {
        case .ts590s:  63
        case .ts590sg: 69
        default:       nil
        }
    }

    // MARK: - LAN encoding type

    enum LANEncoding {
        case utf8    // TS-890S
        case utf16   // TS-990S
        case none    // No LAN
    }

    // MARK: - EX menu format

    enum EXMenuFormat {
        /// TS-890S: EX{P1}{P2}{P3}; where menuNumber = P2*100+P3 or 10000+P3
        case ts890
        /// TS-590S: EX{NNN}; where NNN is 000–087
        case ts590
        /// TS-990S: EX{P1}{P2}{P3}; similar to 890 but different item numbering
        case ts990
    }

    // MARK: - Factory

    static func capabilities(for model: KenwoodRadioModel) -> KenwoodCapabilities {
        switch model {

        case .ts890s:
            return KenwoodCapabilities(
                model:                model,
                hasLAN:               true,
                hasLANAudio:          true,
                lanEncoding:          .utf8,
                useOMCommand:         true,
                hasPSKModes:          true,
                hasScope:             true,
                hasDualReceive:       false,
                has18BandEQ:          true,
                hasAudioSourceSelect: true,
                hasMorseDecoder:      false,
                hasKNS:               true,
                aiCommand:            "AI4;",
                hasDualNoiseBlanker:  true,
                exMenuFormat:         .ts890,
                hasAPFCommands:       true,
                hasDataModeCommand:   false,
                hasMonitorCommands:   true,
                maxTXPowerWatts:      100,
                usesBandPrefix:       false,
                usesCBTB:             false
            )

        case .ts990s:
            return KenwoodCapabilities(
                model:                model,
                hasLAN:               true,
                hasLANAudio:          false,   // LAN CAT only — no ##VP/##KN audio stream
                lanEncoding:          .utf16,
                useOMCommand:         true,
                hasPSKModes:          true,
                hasScope:             true,
                hasDualReceive:       true,
                has18BandEQ:          true,    // Uses UT/UR commands
                hasAudioSourceSelect: true,
                hasMorseDecoder:      false,
                hasKNS:               true,    // TS-990S was the first KNS radio
                aiCommand:            "AI4;",
                hasDualNoiseBlanker:  true,
                exMenuFormat:         .ts990,
                hasAPFCommands:       false,
                hasDataModeCommand:   false,
                hasMonitorCommands:   true,
                maxTXPowerWatts:      200,
                usesBandPrefix:       true,
                usesCBTB:             true
            )

        case .ts590sg:
            return KenwoodCapabilities(
                model:                model,
                hasLAN:               false,
                hasLANAudio:          false,
                lanEncoding:          .none,
                useOMCommand:         false,
                hasPSKModes:          false,
                hasScope:             false,
                hasDualReceive:       false,
                has18BandEQ:          true,
                hasAudioSourceSelect: false,
                hasMorseDecoder:      true,
                hasKNS:               false,
                aiCommand:            "AI2;",
                hasDualNoiseBlanker:  false,
                exMenuFormat:         .ts590,
                hasAPFCommands:       false,
                hasDataModeCommand:   true,
                hasMonitorCommands:   false,
                maxTXPowerWatts:      100,
                usesBandPrefix:       false,
                usesCBTB:             false
            )

        case .ts590s:
            return KenwoodCapabilities(
                model:                model,
                hasLAN:               false,
                hasLANAudio:          false,
                lanEncoding:          .none,
                useOMCommand:         false,
                hasPSKModes:          false,
                hasScope:             false,
                hasDualReceive:       false,
                has18BandEQ:          true,
                hasAudioSourceSelect: false,
                hasMorseDecoder:      false,
                hasKNS:               false,
                aiCommand:            "AI2;",
                hasDualNoiseBlanker:  false,
                exMenuFormat:         .ts590,
                hasAPFCommands:       false,
                hasDataModeCommand:   true,
                hasMonitorCommands:   false,
                maxTXPowerWatts:      100,
                usesBandPrefix:       false,
                usesCBTB:             false
            )

        case .unknown:
            // Default to TS-890S capabilities so an unrecognised ID doesn't
            // break anything for the primary user.
            return KenwoodCapabilities(
                model:                model,
                hasLAN:               true,
                hasLANAudio:          true,
                lanEncoding:          .utf8,
                useOMCommand:         true,
                hasPSKModes:          true,
                hasScope:             true,
                hasDualReceive:       false,
                has18BandEQ:          true,
                hasAudioSourceSelect: true,
                hasMorseDecoder:      false,
                hasKNS:               true,
                aiCommand:            "AI4;",
                hasDualNoiseBlanker:  true,
                exMenuFormat:         .ts890,
                hasAPFCommands:       true,
                hasDataModeCommand:   false,
                hasMonitorCommands:   true,
                maxTXPowerWatts:      100,
                usesBandPrefix:       false,
                usesCBTB:             false
            )
        }
    }
}
