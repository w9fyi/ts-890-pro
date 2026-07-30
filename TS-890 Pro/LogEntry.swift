//
//  LogEntry.swift
//  Kenwood control
//

import Foundation
import SwiftData

/// A single logged contact (QSO).
@Model
final class LogEntry {
    // Core QSO fields (ADIF-compatible)
    var callsign:    String = ""
    var dateTime:    Date   = Date()
    var frequencyHz: Int    = 0        // exact Hz, not MHz, to avoid float imprecision
    var mode:        String = "SSB"
    var rstSent:     String = "59"
    var rstReceived: String = "59"

    // Station details (auto-filled from callsign lookup)
    var opName:    String?
    var grid:      String?
    var country:   String?
    var state:     String?
    var city:      String?

    // Notes
    var notes: String?

    // Upload status
    var uploadedLOTW:    Bool = false
    var uploadedQRZLog:  Bool = false
    var uploadedClubLog: Bool = false
    var uploadedEQSL:    Bool = false

    init() {}

    init(
        callsign:    String,
        dateTime:    Date    = Date(),
        frequencyHz: Int,
        mode:        String,
        rstSent:     String  = "59",
        rstReceived: String  = "59",
        opName:      String? = nil,
        grid:        String? = nil,
        country:     String? = nil,
        state:       String? = nil,
        city:        String? = nil,
        notes:       String? = nil
    ) {
        self.callsign    = callsign
        self.dateTime    = dateTime
        self.frequencyHz = frequencyHz
        self.mode        = mode
        self.rstSent     = rstSent
        self.rstReceived = rstReceived
        self.opName      = opName
        self.grid        = grid
        self.country     = country
        self.state       = state
        self.city        = city
        self.notes       = notes
    }

    // Cached UTC formatters — DateFormatter construction is expensive (locale
    // setup), so build these once instead of per call. Used during ADIF export
    // where they run once per logged contact.
    private static let adifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let adifTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Display frequency as MHz string (e.g. "14.074")
    var frequencyMHz: String {
        String(format: "%g", Double(frequencyHz) / 1_000_000)
    }

    /// ADIF-format date string "YYYYMMDD"
    var adifDate: String {
        LogEntry.adifDateFormatter.string(from: dateTime)
    }

    /// ADIF-format time string "HHMM"
    var adifTime: String {
        LogEntry.adifTimeFormatter.string(from: dateTime)
    }
}
