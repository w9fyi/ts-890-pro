//
//  HamQTHLookupService.swift
//  Kenwood control
//

import Foundation

/// HamQTH.com XML lookup. Free service; credentials stored under .hamqth.
final class HamQTHLookupService: CallsignLookupServiceProtocol {
    private let baseURL = "https://www.hamqth.com/xml.php"
    private var sessionID: String?

    func lookup(callsign: String) async throws -> CallsignInfo {
        if sessionID == nil { try await authenticate() }
        guard let sid = sessionID else { throw CallsignLookupError.authenticationRequired }

        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "id",       value: sid),
            URLQueryItem(name: "callsign", value: callsign),
            URLQueryItem(name: "prg",      value: "TS-890Pro"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)

        // HamQTH returns a <session> error element when the session expires.
        if let body = String(data: data, encoding: .utf8), body.contains("<error>Session does not exist") {
            sessionID = nil
            throw CallsignLookupError.sessionExpired
        }
        return try parseCallsign(from: data, callsign: callsign)
    }

    private func authenticate() async throws {
        guard let creds = KeychainHelper.shared.retrieve(service: .hamqth) else {
            throw CallsignLookupError.authenticationRequired
        }
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "u", value: creds.username),
            URLQueryItem(name: "p", value: creds.password),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let parser = HamQTHXMLParser()
        parser.parse(data: data)
        guard let sid = parser.sessionID else { throw CallsignLookupError.authenticationRequired }
        sessionID = sid
    }

    private func parseCallsign(from data: Data, callsign: String) throws -> CallsignInfo {
        let parser = HamQTHXMLParser()
        parser.parse(data: data)
        guard let d = parser.callsignData, !d.isEmpty else { throw CallsignLookupError.callsignNotFound }
        return CallsignInfo(
            callsign:     callsign,
            name:         d["name"],
            address:      d["adr_street1"] ?? d["adr_street"],
            city:         d["adr_city"],
            state:        nil,
            zip:          d["adr_zip"],
            country:      d["country"],
            grid:         d["grid"],
            latitude:     d["latitude"].flatMap(Double.init),
            longitude:    d["longitude"].flatMap(Double.init),
            email:        d["email"],
            licenseClass: d["lic_type"],
            source:       .hamqth
        )
    }
}

private final class HamQTHXMLParser: NSObject, XMLParserDelegate {
    var sessionID: String?
    var callsignData: [String: String]?

    private var cur = ""
    private var val = ""
    private var inSearch = false

    func parse(data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName _: String?, attributes _: [String: String] = [:]) {
        cur = e; val = ""
        if e == "search" { inSearch = true; callsignData = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { val += s }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?,
                qualifiedName _: String?) {
        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
        if e == "session_id" { sessionID = trimmed }
        else if inSearch, !trimmed.isEmpty { callsignData?[e] = trimmed }
        if e == "search" { inSearch = false }
        cur = ""; val = ""
    }
}
