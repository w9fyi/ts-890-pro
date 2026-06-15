//
//  LogbookManager.swift
//  Kenwood control
//
//  Generates ADIF for LOTW/local export and uploads to QRZ Logbook.
//

import Foundation
import AppKit

enum LogbookExportError: LocalizedError {
    case noCredentials(String)
    case networkError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials(let svc): return "\(svc) credentials not configured"
        case .networkError(let e):    return "Network error: \(e.localizedDescription)"
        case .serverError(let s):     return "Server error: \(s)"
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
            throw LogbookExportError.noCredentials("QRZ Logbook")
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

    // MARK: - Club Log upload

    /// Upload entries to Club Log (clublog.org).
    /// Credentials: username=email, password=API key in .clubLog Keychain service.
    @discardableResult
    static func uploadToClubLog(entries: [LogEntry], myCallsign: String) async throws -> Int {
        guard let creds = KeychainHelper.shared.retrieve(service: .clubLog) else {
            throw LogbookExportError.noCredentials("Club Log")
        }
        let email  = creds.username
        let apiKey = creds.password
        let adifBody = adif(from: entries, myCallsign: myCallsign.isEmpty ? nil : myCallsign)

        var req = URLRequest(url: URL(string: "https://clublog.org/api/upload")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "callsign", value: myCallsign),
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "email",    value: email),
            URLQueryItem(name: "adif",     value: adifBody),
        ]
        req.httpBody = params.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LogbookExportError.networkError(URLError(.badServerResponse))
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        guard body.uppercased().contains("OK") else {
            throw LogbookExportError.serverError(String(body.prefix(200)))
        }
        return entries.count
    }

    // MARK: - eQSL upload

    /// Upload entries to eQSL.cc.
    /// Credentials: username/password in .eqsl Keychain service.
    @discardableResult
    static func uploadToEQSL(entries: [LogEntry], myCallsign: String? = nil) async throws -> Int {
        guard let creds = KeychainHelper.shared.retrieve(service: .eqsl) else {
            throw LogbookExportError.noCredentials("eQSL")
        }
        let adifBody = adif(from: entries, myCallsign: myCallsign)

        var req = URLRequest(url: URL(string: "https://www.eqsl.cc/qslcard/ImportADIF.cfm")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "ADIFDATA",  value: adifBody),
            URLQueryItem(name: "EQSL_USER", value: creds.username),
            URLQueryItem(name: "EQSL_PSWD", value: creds.password),
        ]
        req.httpBody = params.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LogbookExportError.networkError(URLError(.badServerResponse))
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        // eQSL returns an HTML page — success contains "added to the queue"
        guard body.lowercased().contains("added") || body.lowercased().contains("success") else {
            throw LogbookExportError.serverError(String(body.prefix(300)))
        }
        return entries.count
    }

    // MARK: - TQSL / LOTW launcher

    /// Export `entries` to a temp ADIF file and open it in TQSL for signing and upload to LOTW.
    /// Returns false if TQSL is not installed (caller should show an install prompt).
    @discardableResult
    static func exportAndOpenWithTQSL(entries: [LogEntry], myCallsign: String? = nil) -> Bool {
        let adifBody = adif(from: entries, myCallsign: myCallsign)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ts890pro_lotw_export.adif")
        guard (try? adifBody.write(to: tmpURL, atomically: true, encoding: .utf8)) != nil else {
            return false
        }

        let tqslCandidates = ["/Applications/TQSL.app", "/usr/local/bin/tqsl"]
        if let appPath = tqslCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
           appPath.hasSuffix(".app") {
            NSWorkspace.shared.open(
                [tmpURL],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(tmpURL)
        }
        return true
    }

    // MARK: - ADIF import

    /// Parse an ADIF file and return an array of LogEntry objects ready to insert into SwiftData.
    /// Duplicate detection is left to the caller.
    static func importADIF(_ text: String) -> [LogEntry] {
        // Skip header section (everything before <EOH>)
        var body = text
        if let eohRange = text.range(of: "<EOH>", options: .caseInsensitive) {
            body = String(text[eohRange.upperBound...])
        }

        var entries: [LogEntry] = []
        var fields: [String: String] = [:]
        var pos = body.startIndex

        while pos < body.endIndex {
            guard let ltPos = body[pos...].firstIndex(of: "<") else { break }
            pos = ltPos

            guard let gtSearchStart = body.index(ltPos, offsetBy: 1, limitedBy: body.endIndex),
                  let gtPos = body[gtSearchStart...].firstIndex(of: ">") else { break }

            let tag = String(body[gtSearchStart..<gtPos])
            pos = body.index(after: gtPos)

            let tagUpper = tag.uppercased()
            if tagUpper.hasPrefix("EOR") {
                if let entry = adifFieldsToEntry(fields) { entries.append(entry) }
                fields = [:]
            } else if tagUpper.hasPrefix("EOH") {
                // Already handled above; skip
            } else {
                // Format: FIELDNAME:length or FIELDNAME:length:type
                let parts = tag.split(separator: ":", maxSplits: 2)
                guard parts.count >= 2, let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), length >= 0 else {
                    continue
                }
                let name = String(parts[0]).uppercased()
                if length == 0 {
                    fields[name] = ""
                    continue
                }
                let end = body.index(pos, offsetBy: length, limitedBy: body.endIndex) ?? body.endIndex
                fields[name] = String(body[pos..<end])
                pos = end
            }
        }
        // Trailing record without <EOR>
        if let entry = adifFieldsToEntry(fields) { entries.append(entry) }
        return entries
    }

    private static func adifFieldsToEntry(_ f: [String: String]) -> LogEntry? {
        guard let callsign = f["CALL"], !callsign.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let dateStr = f["QSO_DATE"] ?? ""
        let timeStr = f["TIME_ON"] ?? ""
        let dateTime = parseADIFDateTime(date: dateStr, time: timeStr) ?? Date()

        var freqHz = 0
        if let freqStr = f["FREQ"], let mhz = Double(freqStr) {
            freqHz = Int(mhz * 1_000_000)
        }

        return LogEntry(
            callsign:    callsign.uppercased().trimmingCharacters(in: .whitespaces),
            dateTime:    dateTime,
            frequencyHz: freqHz,
            mode:        f["MODE"] ?? "SSB",
            rstSent:     f["RST_SENT"] ?? "59",
            rstReceived: f["RST_RCVD"] ?? "59",
            opName:      nilIfEmpty(f["NAME"]),
            grid:        nilIfEmpty(f["GRIDSQUARE"]),
            country:     nilIfEmpty(f["COUNTRY"]),
            state:       nilIfEmpty(f["STATE"]),
            notes:       nilIfEmpty(f["COMMENT"])
        )
    }

    private static func parseADIFDateTime(date: String, time: String) -> Date? {
        let d = date.trimmingCharacters(in: .whitespaces)
        let t = time.trimmingCharacters(in: .whitespaces)
        guard d.count == 8 else { return nil }
        let timeComponent = t.count >= 4 ? String(t.prefix(4)) : "0000"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmm"
        fmt.timeZone = TimeZone(abbreviation: "UTC")
        return fmt.date(from: d + timeComponent)
    }

    private static func nilIfEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}
