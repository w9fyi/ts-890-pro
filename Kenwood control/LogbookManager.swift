//
//  LogbookManager.swift
//  Kenwood control
//
//  Generates ADIF for LOTW/local export and uploads to QRZ Logbook.
//

import Foundation

enum LogbookExportError: LocalizedError {
    case noCredentials
    case networkError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:      return "QRZ Logbook credentials not configured"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .serverError(let s): return "Server error: \(s)"
        }
    }
}

struct LogbookManager {

    // MARK: - ADIF generation

    /// Build an ADIF string from a set of log entries.
    /// Suitable for import into LOTW via TQSL, or any ADIF-compatible logger.
    static func adif(from entries: [LogEntry], myCallsign: String? = nil) -> String {
        var lines: [String] = ["<ADIF_VER:5>3.1.0", "<PROGRAMID:8>TS890Pro", "<EOH>", ""]
        for e in entries {
            var record: [String] = []
            func field(_ tag: String, _ value: String) {
                guard !value.isEmpty else { return }
                record.append("<\(tag):\(value.count)>\(value)")
            }
            field("CALL",     e.callsign)
            field("QSO_DATE", e.adifDate)
            field("TIME_ON",  e.adifTime)
            field("FREQ",     String(format: "%.6f", Double(e.frequencyHz) / 1_000_000))
            field("MODE",     adifMode(from: e.mode))
            field("RST_SENT", e.rstSent)
            field("RST_RCVD", e.rstReceived)
            if let v = e.opName    { field("NAME",        v) }
            if let v = e.grid      { field("GRIDSQUARE",  v) }
            if let v = e.country   { field("COUNTRY",     v) }
            if let v = e.state     { field("STATE",       v) }
            if let v = myCallsign  { field("STATION_CALLSIGN", v) }
            if let v = e.notes, !v.isEmpty { field("COMMENT", v) }
            record.append("<EOR>")
            lines.append(record.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    /// Convert app mode names to canonical ADIF mode designators.
    private static func adifMode(from mode: String) -> String {
        switch mode.uppercased() {
        case "USB", "LSB":       return "SSB"
        case "CW", "CW-R":      return "CW"
        case "FM":               return "FM"
        case "AM":               return "AM"
        case "FSK", "RTTY":     return "RTTY"
        case "FT8":              return "FT8"
        case "FT4":              return "FT4"
        case "PSK31":            return "PSK31"
        case "FREEDV", "RADE":  return "DIGITALVOICE"
        default:                 return mode.uppercased()
        }
    }

    // MARK: - QRZ Logbook upload

    /// Upload entries to QRZ Logbook via the ADIF/HTTP API.
    /// Returns the count of records accepted by QRZ.
    @discardableResult
    static func uploadToQRZ(entries: [LogEntry], myCallsign: String? = nil) async throws -> Int {
        guard let creds = KeychainHelper.shared.retrieve(service: .qrzLog) else {
            throw LogbookExportError.noCredentials
        }
        let apiKey = creds.password   // For QRZ Logbook, the "password" field holds the API key.

        let adifBody = adif(from: entries, myCallsign: myCallsign)

        // QRZ Logbook ADIF endpoint:  POST https://logbook.qrz.com/api
        var req = URLRequest(url: URL(string: "https://logbook.qrz.com/api")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "KEY",    value: apiKey),
            URLQueryItem(name: "ACTION", value: "INSERT"),
            URLQueryItem(name: "ADIF",   value: adifBody),
        ]
        req.httpBody = params.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LogbookExportError.networkError(URLError(.badServerResponse))
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        // QRZ returns "RESULT=OK&LOGIDS=123,456&COUNT=2" or "RESULT=FAIL&REASON=..."
        let pairs = Dictionary(
            body.split(separator: "&").compactMap({ pair -> (String, String)? in
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { return nil }
                return (kv[0], kv[1])
            }),
            uniquingKeysWith: { _, last in last }
        )
        if pairs["RESULT"] == "OK" {
            return Int(pairs["COUNT"] ?? "0") ?? 0
        } else {
            throw LogbookExportError.serverError(pairs["REASON"] ?? body)
        }
    }
}
