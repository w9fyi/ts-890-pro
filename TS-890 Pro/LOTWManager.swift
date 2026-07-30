//
//  LOTWManager.swift
//  Kenwood control
//
//  Native LOTW submission: import a TQSL .p12 certificate, build the TQSL XML schema,
//  sign with Apple CMSEncoder (PKCS#7 / CMS SignedData), and POST to LOTW directly.
//  No external TQSL installation required at runtime.
//

import Foundation
import Security

// MARK: - Errors

enum LOTWError: LocalizedError {
    case noCertificate
    case certificateImportFailed(String)
    case signingFailed(String)
    case uploadFailed(String)
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .noCertificate:               return "No LOTW certificate imported. Go to Settings → Logbook → LOTW to import your .p12 file."
        case .certificateImportFailed(let s): return "Certificate import failed: \(s)"
        case .signingFailed(let s):        return "Signing failed: \(s)"
        case .uploadFailed(let s):         return "LOTW upload failed: \(s)"
        case .noCredentials:               return "LOTW username/password not configured. Go to Settings → Logbook → LOTW."
        }
    }
}

// MARK: - Station data

struct LOTWStationData: Codable {
    var dxccEntityCode: Int    = 291   // 291 = United States of America
    var ituZone:        Int    = 7
    var cqZone:         Int    = 4
    var arrlSection:    String = ""    // e.g. "STX"
    var usState:        String = ""    // e.g. "TX"
    var gridLocator:    String = ""    // e.g. "EM10"

    static func load() -> LOTWStationData {
        let d = UserDefaults.standard
        var s = LOTWStationData()
        if let code = d.object(forKey: "lotw_dxcc")  as? Int { s.dxccEntityCode = code }
        if let itu  = d.object(forKey: "lotw_itu")   as? Int { s.ituZone        = itu }
        if let cq   = d.object(forKey: "lotw_cq")    as? Int { s.cqZone         = cq }
        s.arrlSection = d.string(forKey: "lotw_arrl") ?? ""
        s.usState     = d.string(forKey: "lotw_state") ?? ""
        s.gridLocator = d.string(forKey: "lotw_grid") ?? ""
        return s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(dxccEntityCode, forKey: "lotw_dxcc")
        d.set(ituZone,        forKey: "lotw_itu")
        d.set(cqZone,         forKey: "lotw_cq")
        d.set(arrlSection,    forKey: "lotw_arrl")
        d.set(usState,        forKey: "lotw_state")
        d.set(gridLocator,    forKey: "lotw_grid")
    }

    /// Map frequency in Hz to TQSL/ADIF band designator.
    static func frequencyToBand(_ hz: Int) -> String {
        switch hz {
        case 1_800_000 ..< 2_000_000:     return "160M"
        case 3_500_000 ..< 4_000_000:     return "80M"
        case 5_330_000 ..< 5_410_000:     return "60M"
        case 7_000_000 ..< 7_300_000:     return "40M"
        case 10_100_000 ..< 10_150_000:   return "30M"
        case 14_000_000 ..< 14_350_000:   return "20M"
        case 18_068_000 ..< 18_168_000:   return "17M"
        case 21_000_000 ..< 21_450_000:   return "15M"
        case 24_890_000 ..< 24_990_000:   return "12M"
        case 28_000_000 ..< 29_700_000:   return "10M"
        case 50_000_000 ..< 54_000_000:   return "6M"
        case 70_000_000 ..< 70_500_000:   return "4M"
        case 144_000_000 ..< 148_000_000: return "2M"
        case 222_000_000 ..< 225_000_000: return "1.25M"
        case 420_000_000 ..< 450_000_000: return "70CM"
        default: return "UNKNOWN"
        }
    }
}

// MARK: - Manager

struct LOTWManager {

    // MARK: Certificate storage
    // The .p12 bytes are stored as kSecValueData; the .p12 password is stored
    // as kSecAttrAccount (a string field on the same item).

    private static let certService = (Bundle.main.bundleIdentifier ?? "com.ai5os.ts890pro") + ".lotwcert"

    /// Import a TQSL .p12 file and persist it in the Keychain.
    /// Throws LOTWError.certificateImportFailed if the .p12 cannot be parsed with the given password.
    static func importCertificate(p12Data: Data, password: String) throws {
        // Validate before storing
        let _ = try makeIdentity(from: p12Data, password: password)

        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  certService,
            kSecAttrAccount:  password,
            kSecValueData:    p12Data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LOTWError.certificateImportFailed("Keychain write error \(status)")
        }
    }

    static func hasCertificate() -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  certService,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func deleteCertificate() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: certService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Subject common name of the stored certificate, for display in settings.
    static func certificateSubject() -> String? {
        guard let (p12Data, password) = loadStoredP12(),
              let (identity, _) = try? makeIdentity(from: p12Data, password: password) else { return nil }
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else { return nil }
        var cfName: CFString?
        SecCertificateCopyCommonName(cert, &cfName)
        return cfName as String?
    }

    // MARK: Signing

    /// Build the TQSL XML content (equivalent to a .tq5 file) for the given entries.
    static func buildTQSLXML(entries: [LogEntry], station: LOTWStationData, myCallsign: String) -> String {
        let cs = myCallsign.uppercased()
        var x = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<QSOs>\n"
        x += " <StationData callSign=\"\(cs)\""
        x += " dxccEntityCode=\"\(station.dxccEntityCode)\""
        x += " ituzoneCode=\"\(station.ituZone)\""
        x += " cqzoneCode=\"\(station.cqZone)\">\n"
        x += "  <DXCC_Entity_Code>\(station.dxccEntityCode)</DXCC_Entity_Code>\n"
        if !station.arrlSection.isEmpty { x += "  <ARRL_Section>\(station.arrlSection)</ARRL_Section>\n" }
        if !station.usState.isEmpty     { x += "  <US_State>\(station.usState)</US_State>\n" }
        if !station.gridLocator.isEmpty { x += "  <Grid_Locator>\(station.gridLocator)</Grid_Locator>\n" }
        x += "  <Logging_Software>TS-890 Pro</Logging_Software>\n"
        x += "  <Logging_Software_API_Version>2</Logging_Software_API_Version>\n"
        x += " </StationData>\n"

        for entry in entries {
            let band = LOTWStationData.frequencyToBand(entry.frequencyHz)
            guard band != "UNKNOWN" else { continue }
            x += " <QSO_Record>\n"
            x += "  <Call_Sent>\(xmlEscape(entry.callsign))</Call_Sent>\n"
            x += "  <Band>\(band)</Band>\n"
            x += "  <Mode>\(xmlEscape(lotwMode(entry.mode)))</Mode>\n"
            x += "  <Submode></Submode>\n"
            x += "  <QSO_Date>\(lotwDate(entry.dateTime))</QSO_Date>\n"
            x += "  <QSO_Time>\(lotwTime(entry.dateTime))</QSO_Time>\n"
            if entry.frequencyHz > 0 {
                x += "  <Freq>\(String(format: "%.6f", Double(entry.frequencyHz) / 1_000_000))</Freq>\n"
            }
            x += "  <PropMode></PropMode>\n"
            x += "  <Satellite_Name></Satellite_Name>\n"
            x += " </QSO_Record>\n"
        }
        x += "</QSOs>\n"
        return x
    }

    /// Sign the TQSL XML and return DER-encoded PKCS#7 SignedData (.tq8 bytes).
    static func sign(entries: [LogEntry], station: LOTWStationData, myCallsign: String) throws -> Data {
        guard let (p12Data, password) = loadStoredP12() else {
            throw LOTWError.noCertificate
        }
        let (identity, chain) = try makeIdentity(from: p12Data, password: password)

        let xml = buildTQSLXML(entries: entries, station: station, myCallsign: myCallsign)
        guard let xmlData = xml.data(using: .utf8) else {
            throw LOTWError.signingFailed("XML encoding failed")
        }

        var encoder: CMSEncoder?
        guard CMSEncoderCreate(&encoder) == errSecSuccess, let enc = encoder else {
            throw LOTWError.signingFailed("CMSEncoder creation failed")
        }

        var status = CMSEncoderAddSigners(enc, identity)
        guard status == errSecSuccess else { throw LOTWError.signingFailed("AddSigners: \(status)") }

        if !chain.isEmpty {
            status = CMSEncoderAddSupportingCerts(enc, chain as CFArray)
            guard status == errSecSuccess else { throw LOTWError.signingFailed("AddCerts: \(status)") }
        }

        CMSEncoderSetHasDetachedContent(enc, false)

        let bytes = [UInt8](xmlData)
        status = CMSEncoderUpdateContent(enc, bytes, bytes.count)
        guard status == errSecSuccess else { throw LOTWError.signingFailed("UpdateContent: \(status)") }

        var output: CFData?
        status = CMSEncoderCopyEncodedContent(enc, &output)
        guard status == errSecSuccess, let outData = output as Data? else {
            throw LOTWError.signingFailed("CopyEncodedContent: \(status)")
        }
        return outData
    }

    // MARK: Upload

    /// POST the signed .tq8 data to LOTW.
    /// Returns the LOTW response body on success.
    @discardableResult
    static func uploadTQ8(data: Data, username: String, password: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://lotw1.arrl.org/lotwuser/upload")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60

        let boundary = "TS890ProLOTW"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"upfile\"; filename=\"log.tq8\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let cred = "\(username):\(password)"
        if let d = cred.data(using: .utf8) {
            req.setValue("Basic \(d.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (respData, httpResp) = try await URLSession.shared.data(for: req)
        let respBody = String(data: respData, encoding: .utf8) ?? ""
        guard (httpResp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LOTWError.uploadFailed(respBody.isEmpty ? "HTTP error" : String(respBody.prefix(200)))
        }
        let lower = respBody.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("reject") {
            throw LOTWError.uploadFailed(String(respBody.prefix(300)))
        }
        return respBody
    }

    /// One-step: sign ADIF entries and upload to LOTW.
    /// Returns a human-readable result string on success.
    @discardableResult
    static func signAndUpload(entries: [LogEntry], station: LOTWStationData, myCallsign: String) async throws -> String {
        guard let creds = KeychainHelper.shared.retrieve(service: .lotw) else {
            throw LOTWError.noCredentials
        }
        let tq8 = try sign(entries: entries, station: station, myCallsign: myCallsign)
        let resp = try await uploadTQ8(data: tq8, username: creds.username, password: creds.password)
        return resp.isEmpty ? "Submitted \(entries.count) contact\(entries.count == 1 ? "" : "s") to LOTW." : String(resp.prefix(200))
    }

    // MARK: Private helpers

    private static func loadStoredP12() -> (data: Data, password: String)? {
        let query: [CFString: Any] = [
            kSecClass:         kSecClassGenericPassword,
            kSecAttrService:   certService,
            kSecReturnData:    true,
            kSecReturnAttributes: true,
            kSecMatchLimit:    kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let dict     = result as? [String: Any],
              let p12Data  = dict[kSecValueData as String] as? Data,
              let password = dict[kSecAttrAccount as String] as? String else { return nil }
        return (p12Data, password)
    }

    private static func makeIdentity(from p12Data: Data, password: String) throws -> (SecIdentity, [SecCertificate]) {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let arr  = items as? [[String: Any]],
              let item = arr.first,
              item[kSecImportItemIdentity as String] != nil else {
            let msg = status == errSecAuthFailed
                ? "Wrong certificate password."
                : "Could not read .p12 file (status \(status))."
            throw LOTWError.certificateImportFailed(msg)
        }
        let identity = item[kSecImportItemIdentity as String]! as! SecIdentity
        let chain = (item[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
        return (identity, chain)
    }

    private static func lotwMode(_ mode: String) -> String {
        switch mode.uppercased() {
        case "USB", "LSB": return "SSB"
        case "CW", "CW-R": return "CW"
        case "FSK", "RTTY": return "RTTY"
        case "FREEDV", "RADE": return "DIGITALVOICE"
        default: return mode.uppercased()
        }
    }

    // Cached UTC formatters — built once instead of per QSO during signing.
    private static let lotwDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(abbreviation: "UTC")!
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let lotwTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        f.timeZone = TimeZone(abbreviation: "UTC")!
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func lotwDate(_ d: Date) -> String { lotwDateFormatter.string(from: d) }

    private static func lotwTime(_ d: Date) -> String { lotwTimeFormatter.string(from: d) }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
