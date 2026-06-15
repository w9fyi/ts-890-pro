//
//  FCCLookupService.swift
//  Kenwood control
//
//  Uses the FCC Universal Licensing System public API — no credentials needed.
//  The basic search returns name + license class; a secondary call fetches
//  the full address using the FRN (FCC Registration Number).
//

import Foundation

final class FCCLookupService: CallsignLookupServiceProtocol {
    // Basic search — returns callsign, name, FRN, category.
    private let searchURL = "https://data.fcc.gov/api/license-view/basicSearch/getLicenses"
    // Entity details by FRN — returns full address.
    private let entityURL = "https://data.fcc.gov/api/license-view/licenses/getEntities"

    func lookup(callsign: String) async throws -> CallsignInfo {
        // Step 1: basic search to get FRN + name.
        var comps = URLComponents(string: searchURL)!
        comps.queryItems = [
            URLQueryItem(name: "searchValue", value: callsign),
            URLQueryItem(name: "format",      value: "json"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw CallsignLookupError.networkError(URLError(.badServerResponse))
        }

        let basic = try parseBasic(data: data, callsign: callsign)

        // Step 2: if we have an FRN, fetch address details.
        if let frn = basic.frn {
            if let detailed = try? await fetchEntity(frn: frn, base: basic) { return detailed }
        }
        return basic.info
    }

    // MARK: - Private

    private struct BasicResult {
        let info: CallsignInfo
        let frn: String?
    }

    private func parseBasic(data: Data, callsign: String) throws -> BasicResult {
        struct FCCLicenses: Codable {
            struct Wrapper: Codable {
                struct License: Codable {
                    let licName: String?
                    let frn: String?
                    let callsign: String?
                    let categoryDesc: String?
                }
                let license: [License]?
            }
            let licenses: Wrapper?
        }
        let resp = try JSONDecoder().decode(FCCLicenses.self, from: data)
        guard let lic = resp.licenses?.license?.first else {
            throw CallsignLookupError.callsignNotFound
        }
        let info = CallsignInfo(
            callsign:     callsign,
            name:         lic.licName,
            address:      nil,
            city:         nil,
            state:        nil,
            zip:          nil,
            country:      "USA",
            grid:         nil,
            latitude:     nil,
            longitude:    nil,
            email:        nil,
            licenseClass: lic.categoryDesc,
            source:       .fcc
        )
        return BasicResult(info: info, frn: lic.frn)
    }

    private func fetchEntity(frn: String, base: BasicResult) async throws -> CallsignInfo {
        var comps = URLComponents(string: entityURL)!
        comps.queryItems = [
            URLQueryItem(name: "frn",    value: frn),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)

        struct FCCEntities: Codable {
            struct Wrapper: Codable {
                struct Entity: Codable {
                    let entityName: String?
                    let attnLine: String?
                    let address: String?
                    let city: String?
                    let state: String?
                    let zip: String?
                    let email: String?
                }
                let entity: [Entity]?
            }
            let entities: Wrapper?
        }
        guard let ent = (try? JSONDecoder().decode(FCCEntities.self, from: data))?.entities?.entity?.first
        else { return base.info }

        return CallsignInfo(
            callsign:     base.info.callsign,
            name:         ent.entityName ?? base.info.name,
            address:      ent.address,
            city:         ent.city,
            state:        ent.state,
            zip:          ent.zip,
            country:      "USA",
            grid:         nil,
            latitude:     nil,
            longitude:    nil,
            email:        ent.email,
            licenseClass: base.info.licenseClass,
            source:       .fcc
        )
    }
}
