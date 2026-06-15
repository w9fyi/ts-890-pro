//
//  CallsignLookupService.swift
//  Kenwood control
//

import Foundation
import Combine

/// Coordinates callsign lookups across QRZ, HamQTH, and FCC.
@MainActor
final class CallsignLookupService: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: CallsignLookupError?

    private let qrz    = QRZLookupService()
    private let hamqth = HamQTHLookupService()
    private let fcc    = FCCLookupService()

    func lookup(callsign: String, source: CallsignLookupSource) async throws -> CallsignInfo {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidCallsign(clean) else { throw CallsignLookupError.invalidCallsign }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            switch source {
            case .qrz:    return try await qrz.lookup(callsign: clean)
            case .hamqth: return try await hamqth.lookup(callsign: clean)
            case .fcc:    return try await fcc.lookup(callsign: clean)
            }
        } catch let e as CallsignLookupError {
            lastError = e
            throw e
        } catch {
            let wrapped = CallsignLookupError.networkError(error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Try each source in order; return the first success.
    func lookupWithFallback(callsign: String) async throws -> CallsignInfo {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidCallsign(clean) else { throw CallsignLookupError.invalidCallsign }

        var last: CallsignLookupError = .callsignNotFound
        for source in CallsignLookupSource.allCases {
            do { return try await lookup(callsign: clean, source: source) }
            catch let e as CallsignLookupError { last = e }
            catch {}
        }
        throw last
    }
}
