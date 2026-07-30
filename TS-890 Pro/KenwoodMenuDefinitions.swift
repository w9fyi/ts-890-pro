// KenwoodMenuDefinitions.swift
// TS-890 Pro — per-radio menu definition factory
//
// Returns the correct EX menu item list for the connected radio model.
// Each radio has its own menu numbering and item set.

import Foundation

/// Unified menu item type used by all radio models.
/// The `number` field uses the radio-specific encoding:
///   TS-890S: P2*100+P3 (regular) or 10000+P3 (advanced)
///   TS-590S: 000–087 (flat numbering); TS-590SG: 000–099 (renumbered)
///   TS-990S: similar to 890 but different item set
public struct KenwoodMenuItem: Identifiable {
    public let id = UUID()
    public let group: String
    public let number: Int
    public let displayLabel: String
    public let detail: String
}

/// Factory that returns menu items for the connected radio.
enum KenwoodMenuDefinitions {

    static func menuItems(for model: KenwoodRadioModel) -> [KenwoodMenuItem] {
        switch model {
        case .ts890s, .unknown:
            return ts890MenuItems.map {
                KenwoodMenuItem(group: $0.group, number: $0.number,
                                displayLabel: $0.displayLabel, detail: $0.detail)
            }
        case .ts590s:
            return ts590MenuItems
        case .ts590sg:
            return ts590sgMenuItems
        case .ts990s:
            return ts990MenuItems
        }
    }

    /// Build the correct EX read command for the given radio and menu number.
    static func getMenuCommand(for model: KenwoodRadioModel, menuNumber: Int) -> String {
        switch model {
        case .ts590s, .ts590sg:
            // TS-590S: EX{P1=NNN}{P2=00}{P3=0}{P4=0}; — the trailing address
            // digits are required (PC Command Reference rev3, EX entry).
            return String(format: "EX%03d0000;", menuNumber)

        case .ts990s:
            // TS-990S: same P1/P2/P3 structure as TS-890S
            if menuNumber >= 10000 {
                return String(format: "EX100%02d;", menuNumber - 10000)
            }
            return String(format: "EX0%02d%02d;", menuNumber / 100, menuNumber % 100)

        case .ts890s, .unknown:
            // TS-890S: existing encoding
            return KenwoodCAT.getMenuValue(menuNumber)
        }
    }

    /// Build the correct EX set command for the given radio and menu number.
    static func setMenuCommand(for model: KenwoodRadioModel, menuNumber: Int, value: Int) -> String {
        switch model {
        case .ts590s, .ts590sg:
            // TS-590S: EX{NNN}{00}{0}{0}{value}; — value is variable length,
            // no space separator and no zero padding.
            return String(format: "EX%03d0000%d;", menuNumber, value)

        case .ts990s:
            if menuNumber >= 10000 {
                return String(format: "EX100%02d %03d;", menuNumber - 10000, value)
            }
            return String(format: "EX0%02d%02d %03d;", menuNumber / 100, menuNumber % 100, value)

        case .ts890s, .unknown:
            return KenwoodCAT.setMenuValue(menuNumber, value: value)
        }
    }
}
