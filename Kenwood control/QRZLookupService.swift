//
//  QRZLookupService.swift
//  Kenwood control
//

import Foundation

/// QRZ.com XML-data lookup (requires XML-data subscription).
/// Credentials stored in Keychain under KeychainHelper.Service.qrz.
final class QRZLookupService: CallsignLookupServiceProtocol {
    private let baseURL = "https://xmldata.qrz.com/xml/current/"
    private var sessionKey: String?

    func lookup(callsign: String) async throws -> CallsignInfo {
        // Session key is lazy — fetch once, reuse until server rejects it.
        if sessionKey == nil { try await authenticate() }
        guard let key = sessionKey else { throw CallsignLookupError.authenticationRequired }

        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "s",        value: key),
            URLQueryItem(name: "callsign", value: callsign),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)

        // Server returns 200 even for errors; check for session-expired signal.
        if let body = String(data: data, encoding: .utf8), body.contains("<Error>Session Timeout") {
            sessionKey = nil
            throw CallsignLookupError.sessionExpired
        }
        return try parseCallsign(from: data, callsign: callsign)
    }

    private func authenticate() async throws {
        guard let creds = KeychainHelper.shared.retrieve(service: .qrz) else {
            throw CallsignLookupError.authenticationRequired
        }
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "username", value: creds.username),
            URLQueryItem(name: "password", value: creds.password),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let parser = QRZXMLParser()
        parser.parse(data: data)
        guard let key = parser.sessionKey else { throw CallsignLookupError.authenticationRequired }
        sessionKey = key
    }

    private func parseCallsign(from data: Data, callsign: String) throws -> CallsignInfo {
        let parser = QRZXMLParser()
        parser.parse(data: data)
        guard let d = parser.callsignData, !d.isEmpty else { throw CallsignLookupError.callsignNotFound }
        return CallsignInfo(
            callsign:     callsign,
            name:         d["fname"].flatMap { f in d["name"].map { "\(f) \($0)" } } ?? d["name"],
            address:      d["addr1"],
            city:         d["addr2"],
            state:        d["state"],
            zip:          d["zip"],
            country:      d["country"],
            grid:         d["grid"],
            latitude:     d["lat"].flatMap(Double.init),
            longitude:    d["lon"].flatMap(Double.init),
            email:        d["email"],
            licenseClass: d["class"],
            source:       .qrz
        )
    }
}

private final class QRZXMLParser: NSObject, XMLParserDelegate {
    var sessionKey: String?
    var callsignData: [String: String]?

    private var cur = ""
    private var val = ""
    private var inCallsign = false

    func parse(data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName _: String?, attributes _: [String: String] = [:]) {
        cur = e; val = ""
        if e == "Callsign" { inCallsign = true; callsignData = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { val += s }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?,
                qualifiedName _: String?) {
        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
        if e == "Key"      { sessionKey = trimmed }
        else if inCallsign, !trimmed.isEmpty { callsignData?[e.lowercased()] = trimmed }
        if e == "Callsign" { inCallsign = false }
        cur = ""; val = ""
    }
}
