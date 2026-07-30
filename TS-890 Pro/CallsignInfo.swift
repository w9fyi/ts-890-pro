//
//  CallsignInfo.swift
//  Kenwood control
//

import Foundation

struct CallsignInfo: Codable, Hashable {
    let callsign: String
    let name: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let country: String?
    let grid: String?       // Maidenhead grid square
    let latitude: Double?
    let longitude: Double?
    let email: String?
    let licenseClass: String?
    let source: CallsignLookupSource
}

enum CallsignLookupSource: String, Codable, CaseIterable {
    case qrz    = "QRZ.com"
    case hamqth = "HamQTH.com"
    case fcc    = "FCC ULS"
}

enum CallsignLookupError: LocalizedError {
    case invalidCallsign
    case networkError(Error)
    case authenticationRequired
    case callsignNotFound
    case parsingError
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidCallsign:          return "Invalid callsign format"
        case .networkError(let e):      return "Network error: \(e.localizedDescription)"
        case .authenticationRequired:   return "Credentials required — configure in Settings → Logbook"
        case .callsignNotFound:         return "Callsign not found"
        case .parsingError:             return "Could not parse response"
        case .sessionExpired:           return "Session expired — will re-authenticate on next lookup"
        }
    }
}

protocol CallsignLookupServiceProtocol {
    func lookup(callsign: String) async throws -> CallsignInfo
}

/// Minimal callsign validation: 3–7 uppercase alphanumeric characters with at
/// least one letter and one digit.
func isValidCallsign(_ s: String) -> Bool {
    let up = s.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard up.count >= 3 && up.count <= 10 else { return false }
    guard up.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" }) else { return false }
    let hasLetter = up.contains { $0.isLetter }
    let hasDigit  = up.contains { $0.isNumber }
    return hasLetter && hasDigit
}
