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
    case ts990s  = "019"   // TS-990S
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

    /// 18-band parametric EQ commands available.
    /// TS-890S: EQTxx/EQRxx; TS-990S: UT/UR; TS-590SG: preset curves only → false.
    let has18BandEQ: Bool

    /// MS (Audio Source Select) command available (TS-890S, TS-990S).
    let hasAudioSourceSelect: Bool

    /// Morse decoder CD0/CD1/CD2 command available (TS-590SG).
    let hasMorseDecoder: Bool

    // MARK: - LAN encoding type

    enum LANEncoding {
        case utf8    // TS-890S
        case utf16   // TS-990S
        case none    // No LAN
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
                hasMorseDecoder:      false
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
                hasMorseDecoder:      false
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
                has18BandEQ:          false,
                hasAudioSourceSelect: false,
                hasMorseDecoder:      true
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
                has18BandEQ:          false,
                hasAudioSourceSelect: false,
                hasMorseDecoder:      false
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
                hasMorseDecoder:      false
            )
        }
    }
}
