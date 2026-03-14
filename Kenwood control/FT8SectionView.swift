//
//  FT8SectionView.swift
//  Kenwood control
//
//  FT8 in this app is intentionally non-GPL: do not copy WSJT-X code.
//  This file provides a VoiceOver-first UI scaffold and a text-level auto-reply state machine.
//

import SwiftUI
import Observation
import Foundation
import AppKit
import UniformTypeIdentifiers

@Observable
final class FT8ViewModel {
    nonisolated deinit {}
    var isAutoReplyEnabled: Bool = UserDefaults.standard.bool(forKey: "FT8.AutoReplyEnabled") {
        didSet { UserDefaults.standard.set(isAutoReplyEnabled, forKey: "FT8.AutoReplyEnabled") }
    }
    var simulateDecodedText: String = ""
    var decodedMessages: [DecodedMessage] = []
    var holdDecodedListUpdates: Bool = false
    var pendingDecodedMessagesCount: Int = 0
    var activityLog: [String] = []
    var verboseFT8Logging: Bool = false
    var lastTxSummary: String = "No FT8 transmit yet."
    var txText: String = ""
    var plannedTxText: String = ""
    var isFT8Running: Bool = false
    var preFT8Summary: String = ""
    var isCQRunning: Bool = false
    var cqParityRaw: String = "Even"
    var isTxArmed: Bool = false
    var nextCQTxAt: Date?
    var isAutoSequenceEnabled: Bool = UserDefaults.standard.bool(forKey: "FT8.AutoSequenceEnabled") {
        didSet { UserDefaults.standard.set(isAutoSequenceEnabled, forKey: "FT8.AutoSequenceEnabled") }
    }
    var autoSequencePriority: AutoSequencePriority = .firstDecoded
    var alertSoundName: String = UserDefaults.standard.string(forKey: "FT8.AlertSoundName") ?? "Radar" {
        didSet { UserDefaults.standard.set(alertSoundName, forKey: "FT8.AlertSoundName") }
    }
    private var autoSeqCandidates: [(msg: DecodedMessage, snr: Float, distKm: Double?)] = []

    private var cqTimer: DispatchSourceTimer?

    // RX capture (decode not implemented yet).
    var isRxCaptureEnabled: Bool = false
    var rxLevelDbFS: Double = -120.0
    var rxBufferedSeconds: Double = 0.0
    var lastSavedWavPath: String = ""
    var isDecoding: Bool = false
    var lastDecodeSummary: String = ""
    var isAutoDecodeEnabled: Bool = false
    var selectedProtocol: FT8Protocol = .ft8
    var queuedTarget: String?
    var sameMessageTxCount: Int = 0
    var lastTransmittedText: String = ""
    var cqTickGeneration: Int = 0
    var txAmplitude: Float = 0.15 {
        didSet { UserDefaults.standard.set(txAmplitude, forKey: "FT8.TxAmplitude") }
    }

    // Per-caller simple state so we don't keep repeating the same response.
    private var qsoStageByCaller: [String: Stage] = [:]
    private var pendingDecodedMessages: [DecodedMessage] = []
    private var alertedCallers: Set<String> = []

    enum Stage: String {
        case none
        case sentGrid
        case sentRReport
        case sentRRR
        case sent73
    }

    // Best-effort snapshot so we can put the rig back when FT8 is stopped.
    var preFT8FrequencyHz: Int?
    var preFT8Mode: KenwoodCAT.OperatingMode?
    var preFT8DataModeEnabled: Bool?
    var preFT8MDMode: Int?

    // Dial frequency active during this FT8 session — set by startFT8.
    var currentDialHz: Int = 0

    // QSO log — contacts who called us or were worked this session.
    struct LoggedQSO: Identifiable {
        let id: UUID = UUID()
        let callsign: String
        let date: Date
        let dialHz: Int
        let rstRcvd: String     // SNR we received them at, e.g. "-05"
        var rstSent: String     // SNR they reported receiving us, e.g. "+00"
        let theirGrid: String   // their grid square (may be empty)
        var confirmed: Bool     // true when 73 or RR73 exchanged
    }
    var loggedQSOs: [LoggedQSO] = []

    // RX buffering at 12 kHz for future decode.
    private let rxQueue = DispatchQueue(label: "FT8.rx")
    private var rx12k: [Float] = []
    private var rxFrameCounter: Int = 0
    private var rxEndTime: TimeInterval?

    init() {
        let saved = UserDefaults.standard.float(forKey: "FT8.TxAmplitude")
        txAmplitude = saved > 0 ? saved : 0.15
    }

    private var autoDecodeWorkItem: DispatchWorkItem?
    private var autoDecodeMyCall: String = ""
    private var autoDecodeMyGrid: String = ""

    enum CQParity: String, CaseIterable {
        case even = "Even"
        case odd = "Odd"
    }

    enum AutoSequencePriority: String, CaseIterable {
        case firstDecoded = "First Decoded"
        case bestSNR      = "Best SNR"
        case mostDistant  = "Most Distant"
    }

    struct DecodedMessage: Identifiable {
        let id: UUID
        let receivedAt: Date
        let raw: String
        let caller: String
        let to: String
        let payload: String
        let isDirectedToMe: Bool
        let snr: Float

        init(receivedAt: Date, raw: String, caller: String, to: String,
             payload: String, isDirectedToMe: Bool, snr: Float = 0) {
            self.id            = UUID()
            self.receivedAt    = receivedAt
            self.raw           = raw
            self.caller        = caller
            self.to            = to
            self.payload       = payload
            self.isDirectedToMe = isDirectedToMe
            self.snr           = snr
        }
    }

    func appendLog(_ line: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        activityLog.append("[\(ts)] \(line)")
        if activityLog.count > 400 {
            activityLog.removeFirst(activityLog.count - 400)
        }
    }

    func processDecodedLine(_ line: String, snr: Float = 0, myCall: String, myGrid: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.uppercased()
        if verboseFT8Logging {
            appendLog("RX: \(normalized)")
        }

        let upperCall = myCall.uppercased()
        let upperGrid = myGrid.uppercased()

        let parsed = parseDecodedLine(normalized, myCall: upperCall)
        if let parsed {
            let msg = DecodedMessage(receivedAt: parsed.receivedAt, raw: parsed.raw,
                                     caller: parsed.caller, to: parsed.to,
                                     payload: parsed.payload,
                                     isDirectedToMe: parsed.isDirectedToMe, snr: snr)
            ingestDecodedMessage(msg)
        }

        guard !myCall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if isAutoReplyEnabled { appendLog("Auto-reply skipped: set your callsign first.") }
            return
        }

        // Only drive the QSO state machine for an already-queued station.
        // processDecodedLine and fillReply share the same qsoStageByCaller state machine.
        // If we call autoReply here for a not-yet-queued station, it advances the stage
        // before fillReply (called from commitAutoSeq → queueTarget) gets to run — causing
        // fillReply to see a stale stage and fall back to sending our grid instead of
        // the correct reply (e.g. R-16 when they opened with a signal report).
        let fromQueuedTarget = queuedTarget != nil && parsed?.caller == queuedTarget
        guard fromQueuedTarget else { return }

        if let reply = autoReply(forDecodedLine: normalized, myCall: upperCall, myGrid: upperGrid) {
            plannedTxText = reply
            txText = reply
            appendLog("Plan TX: \(reply)")
        }
    }

    private func ingestDecodedMessage(_ msg: DecodedMessage) {
        if msg.isDirectedToMe {
            if !alertedCallers.contains(msg.caller) {
                // First time this station has called us this session.
                alertedCallers.insert(msg.caller)
                let snrStr = formatFT8SNR(msg.snr)
                let theirGrid = extractGrid(from: msg.payload)
                loggedQSOs.append(LoggedQSO(
                    callsign: msg.caller,
                    date: msg.receivedAt,
                    dialHz: currentDialHz,
                    rstRcvd: snrStr,
                    rstSent: "+00",
                    theirGrid: theirGrid,
                    confirmed: false
                ))
                let logLine = "Called by: \(msg.caller)"
                    + (theirGrid.isEmpty ? "" : " (\(theirGrid))")
                    + " SNR \(snrStr) dB"
                appendLog(logLine)
                AccessibilityNotification.Announcement(logLine).post()
                (NSSound(named: NSSound.Name(alertSoundName))
                    ?? NSSound(named: NSSound.Name("Radar"))
                    ?? NSSound(named: NSSound.Name("Ping")))?.play()
            } else if let idx = loggedQSOs.lastIndex(where: { $0.callsign == msg.caller }) {
                // Update existing QSO record with RST_SENT or confirmation.
                let first = msg.payload.split(separator: " ").map(String.init).first ?? ""
                if first.hasPrefix("R"), isReport(first) {
                    // e.g. "R-05" — their report of our signal = RST_SENT
                    loggedQSOs[idx].rstSent = String(first.dropFirst())
                }
                if first == "73" || first == "RR73" {
                    loggedQSOs[idx].confirmed = true
                    let confirmLine = "QSO confirmed: \(msg.caller)"
                    appendLog(confirmLine)
                    AccessibilityNotification.Announcement(confirmLine).post()
                }
            }
        }

        // Collect autosequence candidates for this decode batch.
        // Auto-Reply also needs this so that a queued target gets set when CQ is running —
        // without queuedTarget set, cqTick will keep sending CQ instead of the planned reply.
        // RR73, 73, and RRR are closing messages — not new calls. Skip them as candidates.
        let isClosingPayload = msg.payload == "RR73" || msg.payload == "73" || msg.payload == "RRR"
        if (isAutoSequenceEnabled || isAutoReplyEnabled) && isCQRunning && queuedTarget == nil && msg.isDirectedToMe && !isClosingPayload {
            AppFileLogger.shared.log("FT8: directed msg caller=\(msg.caller) adding as candidate snr=\(msg.snr)")
            let distKm: Double? = autoDecodeMyGrid.isEmpty ? nil
                : FT8ViewModel.gridDistanceKm(from: autoDecodeMyGrid, to: msg.payload)
            autoSeqCandidates.append((msg: msg, snr: msg.snr, distKm: distKm))
        }

        if holdDecodedListUpdates {
            pendingDecodedMessages.insert(msg, at: 0)
            if pendingDecodedMessages.count > 200 {
                pendingDecodedMessages.removeLast(pendingDecodedMessages.count - 200)
            }
            pendingDecodedMessagesCount = pendingDecodedMessages.count
            return
        }

        decodedMessages.insert(msg, at: 0)
        if decodedMessages.count > 200 {
            decodedMessages.removeLast(decodedMessages.count - 200)
        }
    }

    func setHoldDecodedListUpdates(_ hold: Bool) {
        holdDecodedListUpdates = hold
        if hold {
            appendLog("Hold decoded list updates: ON")
        } else {
            appendLog("Hold decoded list updates: OFF")
            flushPendingDecodedMessages()
        }
    }

    func flushPendingDecodedMessages() {
        guard !pendingDecodedMessages.isEmpty else { return }
        let count = pendingDecodedMessages.count
        decodedMessages.insert(contentsOf: pendingDecodedMessages, at: 0)
        if decodedMessages.count > 200 {
            decodedMessages.removeLast(decodedMessages.count - 200)
        }
        pendingDecodedMessages.removeAll()
        pendingDecodedMessagesCount = 0
        appendLog("Loaded \(count) queued decoded messages")
    }

    func clearDecodedMessages() {
        decodedMessages.removeAll()
        pendingDecodedMessages.removeAll()
        pendingDecodedMessagesCount = 0
        queuedTarget = nil
        alertedCallers.removeAll()
        appendLog("Cleared decoded messages")
    }

    func clearQueuedTarget() {
        queuedTarget = nil
        sameMessageTxCount = 0
        lastTransmittedText = ""
        plannedTxText = ""
        txText = ""
        appendLog("Queued target cleared")
    }

    func clearAlertedCallers() {
        alertedCallers.removeAll()
    }

    /// Infer which TX parity (even/odd) is opposite to the slot the decoded station used.
    /// FT8 decodes fire ~0.6 s after the slot boundary. Subtracting 7.5 s (half a slot)
    /// places us reliably in the middle of the 15 s slot that was just decoded, regardless
    /// of whether the decode fires slightly early or late. The previous -0.5 s offset could
    /// land right on the slot boundary and be attributed to the NEXT slot, causing the app
    /// to reply on the SAME parity as the caller.
    func oppositeParityFor(_ msg: DecodedMessage) -> CQParity {
        let midSlotApprox = msg.receivedAt.timeIntervalSince1970 - 7.5
        let slotIndex = (Int(midSlotApprox) % 60 + 60) % 60 / 15   // 0, 1, 2, 3
        let theyUsedEvenSlot = (slotIndex % 2) == 0
        return theyUsedEvenSlot ? .odd : .even
    }

    func queueTarget(_ call: String, for msg: DecodedMessage, myCall: String, myGrid: String) {
        queuedTarget = call
        fillReply(for: msg, myCall: myCall, myGrid: myGrid)
        appendLog("Queued target: \(call)")
        AppFileLogger.shared.log("FT8: queued target \(call)")
    }

    func fillReply(for msg: DecodedMessage, myCall: String, myGrid: String) {
        let call = myCall.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let grid = myGrid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !call.isEmpty else {
            appendLog("Click-reply skipped: set your callsign first.")
            return
        }

        // Prefer state-machine reply if we have the full raw line.
        if let r = autoReply(forDecodedLine: msg.raw, myCall: call, myGrid: grid) {
            txText = r
            plannedTxText = r
            appendLog("Fill TX from click: \(r)")
            return
        }

        // Fallback: a safe first exchange is sending our grid.
        let r = "\(msg.caller) \(call) \(grid)"
        txText = r
        plannedTxText = r
        appendLog("Fill TX (fallback): \(r)")
    }

    // Minimal FT8 directed-message responder:
    // - Only reacts when the message is directed to myCall (CALLER MYCALL ...).
    // - Does not attempt signal report math; it mirrors the received report with the correct prefix.
    func autoReply(forDecodedLine line: String, myCall: String, myGrid: String) -> String? {
        let tokens = line
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { String($0) }

        // FT8 wire format: DESTINATION CALLER PAYLOAD
        // e.g. "AI5OS KB9DED EN54" → to=AI5OS (us), caller=KB9DED (them)
        guard tokens.count >= 2 else { return nil }
        let to = tokens[0]
        let caller = tokens[1]
        guard to == myCall else { return nil }

        let third = tokens.count >= 3 ? tokens[2] : ""
        let stage = qsoStageByCaller[caller] ?? .none

        // If caller sends us their grid (often the first directed call),
        // respond with our grid.
        if isGrid(third), stage == .none || stage == .sentGrid {
            qsoStageByCaller[caller] = .sentGrid
            return "\(caller) \(myCall) \(myGrid)"
        }

        // Signal report forms: "-10", "+02", "R-05", "R+00"
        if isReport(third) {
            // If they gave us a plain report, we respond with "R<report>".
            // If they gave "R<report>", we respond with "RRR".
            if third.hasPrefix("R") {
                if stage != .sentRRR {
                    qsoStageByCaller[caller] = .sentRRR
                    return "\(caller) \(myCall) RRR"
                }
                return nil
            } else {
                if stage != .sentRReport {
                    qsoStageByCaller[caller] = .sentRReport
                    return "\(caller) \(myCall) R\(third)"
                }
                return nil
            }
        }

        if third == "RRR" || third == "RR73" {
            if stage != .sent73 {
                qsoStageByCaller[caller] = .sent73
                // Do NOT clear queuedTarget here — cqTick's closingTxCount will transmit
                // the 73 reply and then clear the target after it has actually been sent.
                return "\(caller) \(myCall) 73"
            }
            return nil
        }

        if third == "73" {
            // They sent 73 — QSO complete, no reply needed. Clear the target now.
            qsoStageByCaller[caller] = .sent73
            if queuedTarget == caller { queuedTarget = nil }
            return nil
        }

        // Unknown payload; ignore.
        return nil
    }

    // MARK: - QSO Log helpers

    private func formatFT8SNR(_ snr: Float) -> String {
        let i = Int(snr.rounded())
        return i >= 0 ? String(format: "+%02d", i) : String(format: "%03d", i)
    }

    private func extractGrid(from payload: String) -> String {
        let p = payload.uppercased()
        let chars = Array(p)
        guard chars.count >= 4,
              chars[0].isLetter, chars[1].isLetter,
              chars[2].isNumber, chars[3].isNumber else { return "" }
        if chars.count >= 6, chars[4].isLetter, chars[5].isLetter {
            return String(p.prefix(6))
        }
        return String(p.prefix(4))
    }

    func clearLoggedQSOs() {
        loggedQSOs.removeAll()
        appendLog("QSO log cleared")
    }

    /// Generate an ADIF string from the session QSO log.
    func exportADIF(myCall: String, myGrid: String) -> String {
        var out = ""
        out += "Generated by TS-890 Pro\n"
        out += "<ADIF_VER:5>3.1.4 <PROGRAMID:9>TS890 Pro <EOH>\n\n"

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        func field(_ tag: String, _ value: String) -> String {
            "<\(tag):\(value.count)>\(value)"
        }

        for qso in loggedQSOs {
            let c = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: qso.date)
            let dateStr = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let timeStr = String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            let freqMHz = String(format: "%.6f", Double(qso.dialHz) / 1_000_000.0)
            let band    = Self.adifBand(hz: qso.dialHz)

            var parts = [
                field("CALL",     qso.callsign),
                field("QSO_DATE", dateStr),
                field("TIME_ON",  timeStr),
                field("BAND",     band),
                field("FREQ",     freqMHz),
                field("MODE",     "FT8"),
                field("RST_SENT", qso.rstSent),
                field("RST_RCVD", qso.rstRcvd),
                field("OPERATOR", myCall),
            ]
            if !qso.theirGrid.isEmpty { parts.append(field("GRIDSQUARE",    qso.theirGrid)) }
            if !myGrid.isEmpty        { parts.append(field("MY_GRIDSQUARE", myGrid)) }
            parts.append("<EOR>")
            out += parts.joined(separator: " ") + "\n\n"
        }
        return out
    }

    private static func adifBand(hz: Int) -> String {
        switch hz {
        case 1_800_000...2_000_000:   return "160M"
        case 3_500_000...4_000_000:   return "80M"
        case 5_330_000...5_410_000:   return "60M"
        case 7_000_000...7_300_000:   return "40M"
        case 10_100_000...10_150_000: return "30M"
        case 14_000_000...14_350_000: return "20M"
        case 18_068_000...18_168_000: return "17M"
        case 21_000_000...21_450_000: return "15M"
        case 24_890_000...24_990_000: return "12M"
        case 28_000_000...29_700_000: return "10M"
        case 50_000_000...54_000_000: return "6M"
        default: return "HF"
        }
    }

    func parseDecodedLine(_ line: String, myCall: String) -> DecodedMessage? {
        let tokens = line
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { Self.normalizedToken(String($0)) }
            .filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return nil }
        // Common FT8 "CQ" form: "CQ K1ABC FN42"
        if tokens[0] == "CQ", tokens.count >= 2 {
            guard let callerIndex = tokens.indices.dropFirst().first(where: { Self.looksLikeHamCallsign(tokens[$0]) }) else {
                return nil
            }
            let caller = tokens[callerIndex]
            let to = "CQ"
            let payload = callerIndex + 1 < tokens.count ? tokens[(callerIndex + 1)...].joined(separator: " ") : ""
            return DecodedMessage(
                receivedAt: Date(),
                raw: line,
                caller: caller,
                to: to,
                payload: payload,
                isDirectedToMe: false
            )
        }
        // FT8 wire format: DESTINATION CALLER PAYLOAD
        // e.g. "AI5OS KB9DED EN54" → to=AI5OS caller=KB9DED payload=EN54
        let to = tokens[0]
        let caller = tokens[1]
        guard Self.looksLikeHamCallsign(to) else { return nil }
        guard Self.looksLikeHamCallsign(caller) else { return nil }
        let payload = tokens.dropFirst(2).joined(separator: " ")
        return DecodedMessage(
            receivedAt: Date(),
            raw: line,
            caller: caller,
            to: to,
            payload: payload,
            isDirectedToMe: to == myCall
        )
    }

    func ingestRx48kMono(_ samples48k: [Float]) {
        guard isRxCaptureEnabled else { return }
        rxQueue.async { [weak self] in
            guard let self else { return }
            self.rxEndTime = Date().timeIntervalSince1970
            // Downsample 48k -> 12k by factor 4 with a simple 4-sample box filter.
            // This is sufficient for initial capture; we can replace with a proper resampler later.
            var out = [Float]()
            out.reserveCapacity(samples48k.count / 4)
            var i = 0
            while i + 3 < samples48k.count {
                let y = (samples48k[i] + samples48k[i + 1] + samples48k[i + 2] + samples48k[i + 3]) * 0.25
                out.append(y)
                i += 4
            }

            self.rx12k.append(contentsOf: out)
            // Keep last ~45 seconds.
            let maxSamples = 12_000 * 45
            if self.rx12k.count > maxSamples {
                self.rx12k.removeFirst(self.rx12k.count - maxSamples)
            }

            // Level/seconds updates at ~2 Hz.
            self.rxFrameCounter += 1
            if (self.rxFrameCounter % 50) == 0 {
                var sum: Double = 0
                for s in samples48k {
                    let d = Double(s)
                    sum += d * d
                }
                let mean = sum / Double(max(1, samples48k.count))
                let rms = sqrt(mean)
                let db = 20.0 * log10(rms + 1e-9)
                let seconds = Double(self.rx12k.count) / 12_000.0

                DispatchQueue.main.async {
                    self.rxLevelDbFS = max(-120.0, min(0.0, db))
                    self.rxBufferedSeconds = seconds
                }
            }
        }
    }

    func saveLast15SecondsToWav() {
        // Backward-compatible alias: what we really want for FT8 is the last full 15s slot.
        saveLastFull15SecondSlotToWav()
    }

    func saveLastFull15SecondSlotToWav(completion: ((String?) -> Void)? = nil) {
        rxQueue.async { [weak self] in
            guard let self else { return }
            let need = 12_000 * 15
            guard self.rx12k.count >= need else {
                DispatchQueue.main.async {
                    self.appendLog("RX save blocked: need 15s buffered (have \(Int(self.rxBufferedSeconds))s)")
                    completion?(nil)
                }
                AppFileLogger.shared.log("FT8: RX save blocked (need 15s) bufferedSeconds=\(String(format: "%.2f", self.rxBufferedSeconds))")
                return
            }

            guard let endTime = self.rxEndTime else {
                DispatchQueue.main.async {
                    self.appendLog("RX save blocked: no timing info yet (wait a second and retry).")
                    completion?(nil)
                }
                AppFileLogger.shared.log("FT8: RX save blocked (no timing info)")
                return
            }

            // Save the most recent *full* 15s slot (aligned to UTC seconds).
            // Example: if now is :37, slotEnd is :30, slotStart is :15.
            let nowSec = Int(Date().timeIntervalSince1970)
            let slotEndSec = nowSec - (nowSec % 15)
            let slotEnd = TimeInterval(slotEndSec)
            let slotStart = slotEnd - 15.0

            // Compute where that slot ends in our rolling buffer (relative to the last ingested audio timestamp).
            let secondsFromBufferEndToSlotEnd = endTime - slotEnd
            let offsetToSlotEndSamples = Int((secondsFromBufferEndToSlotEnd * 12_000.0).rounded())
            let slotEndIndex = self.rx12k.count - offsetToSlotEndSamples
            let slotStartIndex = slotEndIndex - need

            guard slotStartIndex >= 0, slotEndIndex <= self.rx12k.count, slotStartIndex < slotEndIndex else {
                DispatchQueue.main.async {
                    self.appendLog("RX save blocked: slot not in buffer yet (buffered=\(String(format: "%.1f", self.rxBufferedSeconds))s).")
                    completion?(nil)
                }
                AppFileLogger.shared.log("FT8: RX save blocked (slot not in buffer) bufferedSeconds=\(String(format: "%.2f", self.rxBufferedSeconds)) slotStartIndex=\(slotStartIndex) slotEndIndex=\(slotEndIndex) rx12k=\(self.rx12k.count)")
                return
            }

            let slot = Array(self.rx12k[slotStartIndex..<slotEndIndex])
            // Use the sandbox temp directory (absolute /tmp may be denied under App Sandbox).
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ft8_rx_slot_\(Self.timestampForFilename()).wav")
            do {
                try Self.writeWav16Mono(path: url, sampleRate: 12_000, samples: slot)
                DispatchQueue.main.async {
                    self.lastSavedWavPath = url.path
                    let startLabel = Date(timeIntervalSince1970: slotStart).formatted(date: .omitted, time: .standard)
                    let endLabel = Date(timeIntervalSince1970: slotEnd).formatted(date: .omitted, time: .standard)
                    self.appendLog("Saved RX slot (\(startLabel)-\(endLabel)): \(url.path)")
                    completion?(url.path)
                }
                AppFileLogger.shared.log("FT8: RX slot saved path=\(url.path)")
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("RX save failed: \(error.localizedDescription)")
                    completion?(nil)
                }
                AppFileLogger.shared.log("FT8: RX save failed: \(error.localizedDescription)")
            }
        }
    }

    func decodeCurrentSlot(myCall: String, myGrid: String) {
        let proto = selectedProtocol
        let need  = proto.slotSamples
        rxQueue.async { [weak self] in
            guard let self else { return }
            guard self.rx12k.count >= need else {
                DispatchQueue.main.async {
                    self.appendLog("Decode blocked: need \(Int(proto.slotDuration))s buffered (have \(Int(self.rxBufferedSeconds))s)")
                    AppFileLogger.shared.log("FT8: decode blocked need=\(Int(proto.slotDuration))s have=\(String(format: "%.1f", self.rxBufferedSeconds))s")
                }
                return
            }
            let slot = Array(self.rx12k.suffix(need))
            DispatchQueue.main.async { self.isDecoding = true }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let results = FT8LibDecoder.decodeSlot(samples12k: slot, protocol: proto)
                DispatchQueue.main.async {
                    self.isDecoding = false
                    if results.isEmpty {
                        self.lastDecodeSummary = "No decodes"
                        self.appendLog("\(proto.rawValue) decode: no messages found")
                        AppFileLogger.shared.log("FT8: decode complete: no messages")
                    } else {
                        self.lastDecodeSummary = "Decoded \(results.count) message\(results.count == 1 ? "" : "s")"
                        self.appendLog("\(proto.rawValue) decode: \(results.count) message(s)")
                        AppFileLogger.shared.log("FT8: decode complete: \(results.count) message(s)")
                        self.autoSeqCandidates.removeAll()
                        for r in results {
                            AppFileLogger.shared.log("FT8: decoded msg=\(r.message) snr=\(r.snr)")
                            self.processDecodedLine(r.message, snr: r.snr, myCall: myCall, myGrid: myGrid)
                        }
                        self.commitAutoSeq()
                    }
                }
            }
        }
    }

    // MARK: - Autosequence

    /// After a full decode batch, pick the best candidate (per priority) and queue them.
    func commitAutoSeq() {
        AppFileLogger.shared.log("FT8: commitAutoSeq candidates=\(autoSeqCandidates.count) autoReply=\(isAutoReplyEnabled) autoSeq=\(isAutoSequenceEnabled) isCQRunning=\(isCQRunning) queuedTarget=\(queuedTarget ?? "nil")")
        guard (isAutoSequenceEnabled || isAutoReplyEnabled) && isCQRunning && queuedTarget == nil
                && !autoSeqCandidates.isEmpty else {
            autoSeqCandidates.removeAll()
            return
        }
        let winner: DecodedMessage?
        switch autoSequencePriority {
        case .firstDecoded:
            winner = autoSeqCandidates.first?.msg
        case .bestSNR:
            winner = autoSeqCandidates.max(by: { $0.snr < $1.snr })?.msg
        case .mostDistant:
            winner = autoSeqCandidates.max(by: { ($0.distKm ?? 0) < ($1.distKm ?? 0) })?.msg
        }
        if let w = winner {
            queueTarget(w.caller, for: w, myCall: autoDecodeMyCall, myGrid: autoDecodeMyGrid)
            appendLog("AutoSeq: queued \(w.caller) (\(autoSequencePriority.rawValue))")
            AppFileLogger.shared.log("FT8 AutoSeq: queued \(w.caller) priority=\(autoSequencePriority.rawValue)")
        }
        autoSeqCandidates.removeAll()
    }

    // MARK: - Grid distance helpers

    static func maidenheadToLatLon(_ grid: String) -> (lat: Double, lon: Double)? {
        let g = grid.uppercased()
        guard g.count >= 4 else { return nil }
        let chars = Array(g)
        guard chars[0].isLetter, chars[1].isLetter,
              chars[2].isNumber, chars[3].isNumber else { return nil }
        guard let f0 = chars[0].asciiValue, let f1 = chars[1].asciiValue else { return nil }
        let aVal = Int(Character("A").asciiValue!)
        let lon0 = Double(Int(f0) - aVal) * 20.0 - 180.0
        let lat0 = Double(Int(f1) - aVal) * 10.0 - 90.0
        let sq0 = Int(chars[2].asciiValue! - Character("0").asciiValue!)
        let sq1 = Int(chars[3].asciiValue! - Character("0").asciiValue!)
        return (lat: lat0 + Double(sq1) * 1.0 + 0.5,
                lon: lon0 + Double(sq0) * 2.0 + 1.0)
    }

    static func gridDistanceKm(from grid1: String, to grid2: String) -> Double? {
        guard !grid1.isEmpty, !grid2.isEmpty,
              let p1 = maidenheadToLatLon(grid1),
              let p2 = maidenheadToLatLon(grid2) else { return nil }
        let R = 6371.0
        let dLat = (p2.lat - p1.lat) * .pi / 180
        let dLon = (p2.lon - p1.lon) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2)
            + cos(p1.lat * .pi/180) * cos(p2.lat * .pi/180) * sin(dLon/2)*sin(dLon/2)
        return 2 * R * atan2(sqrt(a), sqrt(1 - a))
    }

    // MARK: - Alert sound list

    static let availableSoundNames: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Radar",
        "Sosumi", "Submarine", "Tink"
    ]

    func setAutoDecodeEnabled(_ enabled: Bool, myCall: String, myGrid: String) {
        isAutoDecodeEnabled = enabled
        autoDecodeMyCall = myCall
        autoDecodeMyGrid = myGrid
        if enabled {
            appendLog("Auto-decode enabled (\(selectedProtocol.rawValue) \(Int(selectedProtocol.slotDuration))s slots)")
            AppFileLogger.shared.log("FT8: auto-decode enabled proto=\(selectedProtocol.rawValue) myCall=\(myCall) myGrid=\(myGrid)")
            scheduleNextAutoDecodeTick()
        } else {
            appendLog("Auto-decode disabled")
            autoDecodeWorkItem?.cancel()
            autoDecodeWorkItem = nil
        }
    }

    private func scheduleNextAutoDecodeTick() {
        guard isAutoDecodeEnabled else { return }
        let slotDur = selectedProtocol.slotDuration

        // Next slot boundary + 0.6 s to ensure the slot is fully buffered.
        let nowTS  = Date().timeIntervalSince1970
        let nextTS = (floor(nowTS / slotDur) + 1.0) * slotDur
        let fireAt = Date(timeIntervalSince1970: nextTS + 0.6)

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isAutoDecodeEnabled else { return }
            if self.isDecoding {
                self.appendLog("Auto-decode skipped: decoder busy")
                self.scheduleNextAutoDecodeTick()
                return
            }
            self.appendLog("Auto-decode tick (\(self.selectedProtocol.rawValue))")
            AppFileLogger.shared.log("FT8: auto-decode tick proto=\(self.selectedProtocol.rawValue) rxBuf=\(String(format: "%.1f", self.rxBufferedSeconds))s autoReply=\(self.isAutoReplyEnabled) autoSeq=\(self.isAutoSequenceEnabled) isCQRunning=\(self.isCQRunning)")
            self.decodeCurrentSlot(myCall: self.autoDecodeMyCall, myGrid: self.autoDecodeMyGrid)
            self.scheduleNextAutoDecodeTick()
        }

        autoDecodeWorkItem?.cancel()
        autoDecodeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, fireAt.timeIntervalSinceNow), execute: item)
    }

    private static let nonCallTokens: Set<String> = [
        "FT8", "FT4", "JT9", "JT65", "Q65", "MSK144", "WSPR", "FST4", "FST4W",
        "USB", "LSB", "AM", "FM", "CW", "SNR", "DT", "FREQ", "FREQUENCY",
        "HZ", "KHZ", "MHZ", "TX", "RX", "DECODE", "DECODING",
        "USAGE", "OPTIONS", "READS", "DISPLAY", "DEFAULT", "PATH", "KEY",
        "SECONDS", "DATA", "FROM", "SHARED", "MEMORY", "FILE", "FILE1", "FILE2"
    ]

    private static func normalizedToken(_ s: String) -> String {
        let up = s.uppercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/+-"))
        var scalars = Array(up.unicodeScalars)
        while let first = scalars.first, !allowed.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, !allowed.contains(last) { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func looksLikeHamCallsign(_ s: String) -> Bool {
        let up = normalizedToken(s)
        guard up.count >= 3 && up.count <= 12 else { return false }
        guard !nonCallTokens.contains(up) else { return false }
        guard up.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil else { return false }
        let parts = up.split(separator: "/")
        guard !parts.isEmpty else { return false }
        let main = String(parts[0])
        guard !main.isEmpty else { return false }
        for ch in up.unicodeScalars {
            let v = ch.value
            let isAZ = (65...90).contains(v)
            let is09 = (48...57).contains(v)
            let isSlash = v == 47
            if !(isAZ || is09 || isSlash) { return false }
        }
        let chars = Array(main)
        guard let firstDigit = chars.firstIndex(where: { $0.isNumber }),
              let lastDigit = chars.lastIndex(where: { $0.isNumber }) else {
            return false
        }
        let prefix = String(chars[..<firstDigit])
        let numeral = String(chars[firstDigit...lastDigit])
        let suffixStart = chars.index(after: lastDigit)
        let suffix = suffixStart < chars.endIndex ? String(chars[suffixStart...]) : ""
        guard prefix.count >= 1 && prefix.count <= 3 else { return false }
        guard numeral.count >= 1 && numeral.count <= 2 else { return false }
        guard suffix.count >= 1 && suffix.count <= 4 else { return false }
        guard prefix.allSatisfy(\.isLetter) else { return false }
        guard suffix.allSatisfy(\.isLetter) else { return false }
        for p in parts.dropFirst() {
            guard !p.isEmpty else { return false }
            guard p.count <= 6 else { return false }
        }
        return true
    }

    private static func isLikelyGridToken(_ s: String) -> Bool {
        let up = normalizedToken(s)
        guard up.count == 4 || up.count == 6 else { return false }
        let chars = Array(up)
        guard chars.count >= 4 else { return false }
        guard chars[0].isLetter, chars[1].isLetter else { return false }
        guard chars[2].isNumber, chars[3].isNumber else { return false }
        return true
    }

    private static func isLikelyReportToken(_ s: String) -> Bool {
        let up = normalizedToken(s)
        let body = up.hasPrefix("R") ? String(up.dropFirst()) : up
        guard body.count == 3 else { return false }
        let chars = Array(body)
        guard chars[0] == "+" || chars[0] == "-" else { return false }
        return chars[1].isNumber && chars[2].isNumber
    }

    private static func compactForLog(_ s: String, limit: Int) -> String {
        let collapsed = s
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func timestampForFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func writeWav16Mono(path: URL, sampleRate: Int, samples: [Float]) throws {
        // 16-bit PCM WAV, little-endian.
        let numSamples = samples.count
        let bytesPerSample = 2
        let dataBytes = numSamples * bytesPerSample
        let riffChunkSize = 36 + dataBytes

        var data = Data()
        data.reserveCapacity(44 + dataBytes)

        func putASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func putU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(UnsafeBufferPointer(start: &le, count: 1))
        }
        func putU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(UnsafeBufferPointer(start: &le, count: 1))
        }

        putASCII("RIFF")
        putU32(UInt32(riffChunkSize))
        putASCII("WAVE")

        putASCII("fmt ")
        putU32(16) // PCM fmt chunk size
        putU16(1) // PCM
        putU16(1) // mono
        putU32(UInt32(sampleRate))
        putU32(UInt32(sampleRate * bytesPerSample)) // byte rate
        putU16(UInt16(bytesPerSample)) // block align
        putU16(16) // bits per sample

        putASCII("data")
        putU32(UInt32(dataBytes))

        for s in samples {
            let clamped = max(-1.0, min(1.0, Double(s)))
            let v = Int16(clamped * 32767.0)
            var le = v.littleEndian
            data.append(UnsafeBufferPointer(start: &le, count: 1))
        }

        try data.write(to: path, options: .atomic)
    }

    private func isGrid(_ s: String) -> Bool {
        // Very loose: 4 or 6 chars; first 2 letters, next 2 digits.
        let up = s.uppercased()
        guard up.count == 4 || up.count == 6 else { return false }
        let chars = Array(up)
        guard chars.count >= 4 else { return false }
        guard chars[0].isLetter, chars[1].isLetter else { return false }
        guard chars[2].isNumber, chars[3].isNumber else { return false }
        return true
    }

    private func isReport(_ s: String) -> Bool {
        // "-10", "+02", "R-05", "R+00"
        let up = s.uppercased()
        let body = up.hasPrefix("R") ? String(up.dropFirst()) : up
        guard body.count == 3 else { return false }
        let chars = Array(body)
        guard chars[0] == "+" || chars[0] == "-" else { return false }
        return chars[1].isNumber && chars[2].isNumber
    }
}

private struct FT8BandPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let frequencyHz: Int
    let notes: String

    static let allPresets: [FT8BandPreset] = [
        FT8BandPreset(id: "160m", label: "160m", frequencyHz: 1_840_000, notes: "FT8"),
        FT8BandPreset(id: "80m",  label: "80m",  frequencyHz: 3_573_000, notes: "FT8"),
        FT8BandPreset(id: "60m",  label: "60m",  frequencyHz: 5_357_000, notes: "FT8 (channelized)"),
        FT8BandPreset(id: "40m",  label: "40m",  frequencyHz: 7_074_000, notes: "FT8"),
        FT8BandPreset(id: "30m",  label: "30m",  frequencyHz: 10_136_000, notes: "FT8"),
        FT8BandPreset(id: "20m",  label: "20m",  frequencyHz: 14_074_000, notes: "FT8"),
        FT8BandPreset(id: "17m",  label: "17m",  frequencyHz: 18_100_000, notes: "FT8"),
        FT8BandPreset(id: "15m",  label: "15m",  frequencyHz: 21_074_000, notes: "FT8"),
        FT8BandPreset(id: "12m",  label: "12m",  frequencyHz: 24_915_000, notes: "FT8"),
        FT8BandPreset(id: "10m",  label: "10m",  frequencyHz: 28_074_000, notes: "FT8"),
        FT8BandPreset(id: "6m",   label: "6m",   frequencyHz: 50_313_000, notes: "FT8"),
        FT8BandPreset(id: "2m",   label: "2m",   frequencyHz: 144_174_000, notes: "FT8")
    ]
}

struct FT8SectionView: View {
    let radio: RadioState
    @Environment(\.dismiss) private var dismiss

    @State private var vm = FT8ViewModel()
    @State private var showSettings: Bool = false

    @AppStorage("FT8.MyCallsign") private var myCallsign: String = ""
    @AppStorage("FT8.MyGrid") private var myGrid: String = ""
    @AppStorage("FT8.MyLocation") private var myLocation: String = ""

    @State private var selectedPresetID: String = "20m"
    @State private var frequencyOverrideMHz: String = ""
    @State private var forceUSB: Bool = true
    @State private var forceDataMode: Bool = true
    @State private var ensureLanAudio: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // ─ Top bar ───────────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Row 1: protocol / start-stop / settings
                HStack(spacing: 16) {
                    Picker("", selection: $vm.selectedProtocol) {
                        ForEach(FT8Protocol.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .accessibilityLabel("Protocol, FT8 or FT4")

                    Button(vm.isFT8Running ? "Stop FT8" : "Start FT8") {
                        if vm.isFT8Running { stopFT8() } else { startFT8() }
                    }
                    .accessibilityLabel(vm.isFT8Running ? "Stop FT8" : "Start FT8")

                    Spacer()

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("FT8 Settings")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Row 2: band / CQ / parity / auto-reply
                HStack(spacing: 12) {
                    Picker("Band", selection: $selectedPresetID) {
                        ForEach(FT8BandPreset.allPresets) { p in
                            Text(p.label).tag(p.id)
                        }
                        Text("Manual").tag("manual")
                    }
                    .frame(minWidth: 100)
                    .accessibilityLabel("FT8 band")
                    .accessibilityHint(vm.isFT8Running ? "Stop FT8 to change band" : "Radio retunes when you press Start FT8")
                    .disabled(vm.isFT8Running)

                    if selectedPresetID == "manual" {
                        TextField("MHz", text: $frequencyOverrideMHz)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .accessibilityLabel("Manual frequency in megahertz")
                            .disabled(vm.isFT8Running)
                    }

                    Divider().frame(height: 20)

                    Button(vm.isCQRunning ? "Stop CQ" : "CQ") {
                        if vm.isCQRunning { stopCQ() } else { startCQ() }
                    }
                    .disabled(!vm.isFT8Running)
                    .accessibilityLabel(vm.isCQRunning ? "Stop CQ" : "Start CQ")

                    Picker("Cycle", selection: $vm.cqParityRaw) {
                        ForEach(FT8ViewModel.CQParity.allCases, id: \.rawValue) { p in
                            Text(p.rawValue).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .accessibilityLabel("CQ cycle parity, even or odd")

                    Toggle("Auto-Reply", isOn: $vm.isAutoReplyEnabled)
                        .accessibilityLabel("Auto-reply to directed calls")

                    Spacer()

                    if vm.isCQRunning {
                        if let next = vm.nextCQTxAt {
                            Text("TX \(next.formatted(date: .omitted, time: .standard))  CQ \(myCallsign.uppercased()) \(myGrid.uppercased())")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Next CQ transmit at \(next.formatted(date: .omitted, time: .standard))")
                        } else {
                            Text("CQ \(myCallsign.uppercased()) \(myGrid.uppercased())")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // ─ Queued target banner (only when running + queued) ─────────────
            if vm.isFT8Running, let target = vm.queuedTarget {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    Text("Next TX: \(target)")
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Next transmit target, \(target)")
                    Spacer()
                    Button("Cancel") { vm.clearQueuedTarget() }
                        .accessibilityLabel("Cancel queued transmit target")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
            }

            Divider()

            // ─ Decode list ───────────────────────────────────────────────────
            List(vm.decodedMessages) { msg in
                Button(action: {
                    // Determine which TX cycle is opposite to the station we're calling.
                    let parity = vm.oppositeParityFor(msg)
                    vm.cqParityRaw = parity.rawValue
                    vm.queueTarget(msg.caller, for: msg, myCall: myCallsign, myGrid: myGrid)
                    // Auto-start (or restart on the correct cycle) when FT8 is running.
                    guard vm.isFT8Running else { return }
                    if vm.isCQRunning { stopCQ() }
                    startCQ()
                }) {
                    HStack(spacing: 12) {
                        Text(msg.raw)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if msg.isDirectedToMe {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundColor(.accentColor)
                                .accessibilityLabel("directed to you")
                        }
                        if vm.queuedTarget == msg.caller {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .accessibilityLabel("queued for reply")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    msg.raw
                    + (msg.isDirectedToMe ? ", directed to you" : "")
                    + (vm.queuedTarget == msg.caller ? ", queued for reply" : "")
                )
                .accessibilityHint("Double-tap to queue for transmit")
                .listRowBackground(
                    vm.queuedTarget == msg.caller
                        ? Color.accentColor.opacity(0.12)
                        : msg.isDirectedToMe
                            ? Color.yellow.opacity(0.06)
                            : Color.clear
                )
            }
            .listStyle(.plain)
            .overlay {
                if vm.decodedMessages.isEmpty {
                    ContentUnavailableView(
                        vm.isFT8Running ? "Listening for Signals" : "FT8 Not Running",
                        systemImage: vm.isFT8Running
                            ? "antenna.radiowaves.left.and.right"
                            : "stop.circle",
                        description: Text(vm.isFT8Running
                            ? "Decoded stations will appear here. Tap any row to queue a reply."
                            : "Tap Start FT8 to begin receiving and decoding.")
                    )
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            FT8SettingsSheet(
                vm: vm,
                myCallsign: $myCallsign,
                myGrid: $myGrid,
                myLocation: $myLocation,
                forceUSB: $forceUSB,
                forceDataMode: $forceDataMode,
                ensureLanAudio: $ensureLanAudio,
                isPresented: $showSettings
            )
        }
        .onAppear {
            if myCallsign.isEmpty || myGrid.isEmpty {
                vm.appendLog("Tip: open FT8 Settings (gear icon) to set your callsign and grid.")
            }
            radio.onLanRxAudio48kMono = { [weak vm] frame in
                vm?.ingestRx48kMono(frame)
            }
            AppFileLogger.shared.log("FT8: installed RX audio tap")
        }
        .onDisappear {
            radio.onLanRxAudio48kMono = nil
            AppFileLogger.shared.log("FT8: removed RX audio tap")
        }
        .background(
            Button("") { dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        )
    }

    private var selectedFrequencyHz: Int {
        if selectedPresetID == "manual" {
            let trimmed = frequencyOverrideMHz.trimmingCharacters(in: .whitespacesAndNewlines)
            if let mhz = Double(trimmed) {
                return Int((mhz * 1_000_000.0).rounded())
            }
            return 14_074_000
        }
        return FT8BandPreset.allPresets.first(where: { $0.id == selectedPresetID })?.frequencyHz ?? 14_074_000
    }

    private func dialFrequencyLabelHz(_ hz: Int) -> String {
        String(format: "%.6f MHz", Double(hz) / 1_000_000.0)
    }

    private func startFT8() {
        let hz = selectedFrequencyHz

        // Snapshot what we know now (best-effort). If values are unknown,
        // we won't try to restore them.
        vm.preFT8FrequencyHz = radio.vfoAFrequencyHz
        vm.currentDialHz = hz
        // Normalize data modes to their voice equivalent — if the radio was already in
        // USB-DATA (leftover from a previous FT8/FreeDV session), restoring to USB-DATA
        // after Stop would leave the radio in digital mode unintentionally.
        let rawMode = radio.operatingMode ?? .usb
        switch rawMode {
        case .usbData: vm.preFT8Mode = .usb
        case .lsbData: vm.preFT8Mode = .lsb
        case .fmData:  vm.preFT8Mode = .fm
        case .amData:  vm.preFT8Mode = .am
        default:       vm.preFT8Mode = rawMode
        }
        vm.preFT8DataModeEnabled = radio.dataModeEnabled
        vm.preFT8MDMode = radio.mdMode
        vm.preFT8Summary = [
            vm.preFT8FrequencyHz != nil ? "freq=\(dialFrequencyLabelHz(vm.preFT8FrequencyHz!))" : nil,
            vm.preFT8Mode != nil ? "mode=\(vm.preFT8Mode!.label)" : nil,
            vm.preFT8MDMode != nil ? "md=\(vm.preFT8MDMode!)" : nil
        ].compactMap { $0 }.joined(separator: ", ")

        vm.clearDecodedMessages()   // fresh list on each Start
        vm.isFT8Running = true
        vm.isTxArmed = true
        vm.appendLog("FT8 start: tuning to \(dialFrequencyLabelHz(hz))")
        AppFileLogger.shared.log("FT8: start hz=\(hz) preset=\(selectedPresetID)")
        if !vm.isRxCaptureEnabled {
            vm.isRxCaptureEnabled = true
            vm.appendLog("FT8 start: RX capture enabled automatically")
            AppFileLogger.shared.log("FT8: RX capture auto-enabled")
        }
        vm.setAutoDecodeEnabled(true, myCall: myCallsign, myGrid: myGrid)
        vm.appendLog("FT8 start: auto-decode enabled")
        AppFileLogger.shared.log("FT8: auto-decode auto-enabled")

        // Set dial frequency and mode.
        radio.send(KenwoodCAT.setVFOAFrequencyHz(hz))
        if forceUSB {
            radio.send(KenwoodCAT.setOperatingMode(.usb))
        }
        if forceDataMode {
            // TS-890 appears to use MD for USB-DATA (DA is rejected by the radio).
            radio.send(KenwoodCAT.setModeMD(2))
            radio.send(KenwoodCAT.getModeMD())
        }

        // Start LAN RX audio if requested (best-effort: uses last host).
        if ensureLanAudio, !radio.isLanAudioRunning {
            let host = UserDefaults.standard.string(forKey: "LastConnectedHost")
                ?? KNSSettings.loadLastHost()
                ?? "192.168.50.56"
            vm.appendLog("FT8 start: ensuring LAN audio on host \(host)")
            AppFileLogger.shared.log("FT8: ensure LAN audio host=\(host)")
            radio.startLanAudio(host: host)
        }
    }

    private func stopFT8() {
        stopCQ()
        vm.isTxArmed = false
        vm.appendLog("FT8 stop: restoring pre-FT8 rig state (best-effort)")
        AppFileLogger.shared.log("FT8: stop restore")

        if let hz = vm.preFT8FrequencyHz {
            vm.appendLog("Restore: VFO A \(dialFrequencyLabelHz(hz))")
            AppFileLogger.shared.log("FT8: restore FA hz=\(hz)")
            radio.send(KenwoodCAT.setVFOAFrequencyHz(hz))
        }
        if let mode = vm.preFT8Mode {
            vm.appendLog("Restore: mode \(mode.label)")
            AppFileLogger.shared.log("FT8: restore OM \(mode.label)")
            radio.send(KenwoodCAT.setOperatingMode(mode))
            radio.send(KenwoodCAT.getOperatingMode())
        }
        if let md = vm.preFT8MDMode {
            vm.appendLog("Restore: MD \(md)")
            AppFileLogger.shared.log("FT8: restore MD \(md)")
            radio.send(KenwoodCAT.setModeMD(md))
            radio.send(KenwoodCAT.getModeMD())
        }

        if vm.isAutoDecodeEnabled {
            vm.setAutoDecodeEnabled(false, myCall: myCallsign, myGrid: myGrid)
            AppFileLogger.shared.log("FT8: auto-decode auto-disabled on stop")
        }
        if vm.isRxCaptureEnabled {
            vm.isRxCaptureEnabled = false
            vm.appendLog("FT8 stop: RX capture disabled")
            AppFileLogger.shared.log("FT8: RX capture auto-disabled on stop")
        }

        vm.lastTxSummary = "FT8 stopped; TX idle."
        vm.isFT8Running = false
    }

    private func startCQ() {
        let call = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let grid = myGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty, !grid.isEmpty else {
            vm.appendLog("CQ start blocked: set callsign + grid in Station Profile.")
            AppFileLogger.shared.log("FT8: CQ start blocked (missing callsign/grid)")
            return
        }
        guard vm.isFT8Running else { return }
        vm.cqTickGeneration += 1
        vm.isCQRunning = true
        vm.appendLog("CQ loop started parity=\(vm.cqParityRaw) txArmed=\(vm.isTxArmed)")
        AppFileLogger.shared.log("FT8: CQ start parity=\(vm.cqParityRaw) txArmed=\(vm.isTxArmed)")
        scheduleNextCQTick()
    }

    private func stopCQ() {
        vm.isCQRunning = false
        vm.nextCQTxAt = nil
        vm.queuedTarget = nil
        vm.sameMessageTxCount = 0
        vm.lastTransmittedText = ""
        vm.cqTickGeneration += 1
        vm.plannedTxText = ""
        vm.appendLog("CQ loop stopped")
        vm.lastTxSummary = "CQ stopped; TX idle."
        AppFileLogger.shared.log("FT8: CQ stop")
    }

    private func scheduleNextCQTick() {
        guard vm.isCQRunning else { return }
        let parity = FT8ViewModel.CQParity(rawValue: vm.cqParityRaw) ?? .even

        let now = Date()
        let nowSec = Int(now.timeIntervalSince1970)
        var t = nowSec - (nowSec % 15) + 15 // next 15s boundary
        while true {
            let slot = (t % 60) / 15 // 0,1,2,3
            let isEven = (slot % 2) == 0
            if (parity == .even && isEven) || (parity == .odd && !isEven) { break }
            t += 15
        }

        let next = Date(timeIntervalSince1970: TimeInterval(t))
        vm.nextCQTxAt = next

        // Capture the current generation so orphaned chains from a previous
        // start/stop cycle discard themselves rather than double-firing.
        let generation = vm.cqTickGeneration
        let dt = max(0.01, next.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + dt) {
            guard vm.isCQRunning, vm.cqTickGeneration == generation else { return }
            cqTick(at: next)
            scheduleNextCQTick()
        }
    }

    private func cqTick(at when: Date) {
        let call = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let grid = myGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // If a station is queued for reply, transmit the planned exchange message
        // instead of a bare CQ.  The auto-reply state machine keeps plannedTxText
        // updated as the QSO progresses slot by slot.
        let isQueued = vm.queuedTarget != nil && !vm.plannedTxText.isEmpty
        let msg: String
        if isQueued {
            msg = vm.plannedTxText
            // Track how many times we've sent the same message without advancement.
            // Closing messages (73/RRR) get 3 retries; mid-QSO stalls get 6.
            if msg == vm.lastTransmittedText {
                vm.sameMessageTxCount += 1
            } else {
                vm.sameMessageTxCount = 1
                vm.lastTransmittedText = msg
            }
            let isClosing = msg.hasSuffix(" 73") || msg.hasSuffix(" RRR")
            let limit = isClosing ? 3 : 6
            if vm.sameMessageTxCount >= limit {
                let timedOut = vm.queuedTarget ?? "?"
                vm.queuedTarget = nil
                vm.sameMessageTxCount = 0
                vm.lastTransmittedText = ""
                vm.plannedTxText = ""
                vm.appendLog("Auto-cleared \(timedOut): no response after \(limit) TX of \(msg)")
                AppFileLogger.shared.log("FT8: auto-cleared queuedTarget=\(timedOut) after \(limit) TX")
            }
        } else {
            vm.sameMessageTxCount = 0
            vm.lastTransmittedText = ""
            msg = "CQ \(call) \(grid)"
            vm.txText = msg
            vm.plannedTxText = msg
        }

        vm.appendLog("CQ tick @\(when.formatted(date: .omitted, time: .standard)): \(msg)")
        vm.lastTxSummary = isQueued ? "TX (reply): \(msg)" : "CQ queued: \(msg)"
        AppFileLogger.shared.log("FT8: CQ tick \(msg)")

        // A manually-queued target bypasses TX Armed — the user explicitly chose to call them.
        guard vm.isTxArmed || isQueued else {
            vm.appendLog("TX not armed: no RF transmission")
            vm.lastTxSummary = "Not transmitted: TX not armed."
            AppFileLogger.shared.log("FT8: CQ tick skipped (TX not armed)")
            return
        }

        // Encode and resample on a background thread to avoid blocking the main thread.
        let proto     = vm.selectedProtocol
        let amplitude = vm.txAmplitude
        let radio     = radio
        let vm        = vm
        DispatchQueue.global(qos: .userInitiated).async {
            guard let audio = FT8LibEncoder.encode(message: msg, protocol: proto) else {
                AppFileLogger.shared.log("FT8: TX encode failed msg=\(msg)")
                DispatchQueue.main.async {
                    vm.appendLog("TX encode failed: \(msg)")
                    vm.lastTxSummary = "TX encode failed: \(msg)"
                }
                return
            }
            AppFileLogger.shared.log("FT8: TX \(proto.rawValue) \(msg) (\(audio.count) samples)")
            radio.transmitFT8Audio(samples12k: audio, amplitude: amplitude)
            DispatchQueue.main.async { vm.lastTxSummary = "TX: \(msg)" }
        }
    }
}

private struct FT8SettingsSheet: View {
    @Bindable var vm: FT8ViewModel
    @Binding var myCallsign: String
    @Binding var myGrid: String
    @Binding var myLocation: String
    @Binding var forceUSB: Bool
    @Binding var forceDataMode: Bool
    @Binding var ensureLanAudio: Bool
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("FT8 Settings")
                    .font(.title2)

                // ── Station ──────────────────────────────────────────────────
                GroupBox("Station") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Callsign:")
                                .frame(width: 80, alignment: .leading)
                            TextField("e.g. W9XYZ", text: $myCallsign)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Callsign")
                        }
                        HStack(spacing: 12) {
                            Text("Grid:")
                                .frame(width: 80, alignment: .leading)
                            TextField("e.g. EM10", text: $myGrid)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Grid square")
                        }
                        HStack(spacing: 12) {
                            Text("Location:")
                                .frame(width: 80, alignment: .leading)
                            TextField("City, State (optional)", text: $myLocation)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Location")
                        }
                        Text("Values are saved on this Mac.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── TX Audio Level ───────────────────────────────────────────
                GroupBox("TX Audio Level") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Slider(value: $vm.txAmplitude, in: 0.01...1.0)
                                .accessibilityLabel("Transmit audio level, \(Int(vm.txAmplitude * 100)) percent")
                            Text(String(format: "%.0f%%", vm.txAmplitude * 100))
                                .frame(width: 44, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                        Text("Controls the FT8 waveform amplitude sent to the radio via LAN mic.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Alert Sounds ─────────────────────────────────────────────
                GroupBox("Alert Sounds") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Directed call alert:")
                                .frame(width: 140, alignment: .leading)
                            Picker("Alert sound", selection: $vm.alertSoundName) {
                                ForEach(FT8ViewModel.availableSoundNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .frame(minWidth: 130)
                            .accessibilityLabel("Alert sound for directed calls")
                            Button("Preview") {
                                NSSound(named: NSSound.Name(vm.alertSoundName))?.play()
                            }
                            .accessibilityLabel("Preview alert sound")
                        }
                        Text("Plays when a station calls you directly (e.g. W1AW AI5OS +02).")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── QSO Log ──────────────────────────────────────────────────
                GroupBox("QSO Log") {
                    VStack(alignment: .leading, spacing: 10) {
                        let total     = vm.loggedQSOs.count
                        let confirmed = vm.loggedQSOs.filter(\.confirmed).count
                        Text("\(total) contact\(total == 1 ? "" : "s") (\(confirmed) confirmed)")
                            .font(.subheadline)
                            .accessibilityLabel("\(total) contacts this session, \(confirmed) confirmed")

                        HStack(spacing: 12) {
                            Button("Export ADIF…") {
                                let panel = NSSavePanel()
                                panel.title           = "Export FT8 QSO Log"
                                panel.nameFieldStringValue = "ft8-qsos.adi"
                                panel.allowedContentTypes  = [.init(filenameExtension: "adi")!]
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    let adif = vm.exportADIF(myCall: myCallsign, myGrid: myGrid)
                                    try? adif.write(to: url, atomically: true, encoding: .utf8)
                                }
                            }
                            .disabled(vm.loggedQSOs.isEmpty)
                            .accessibilityLabel("Export FT8 QSO log as ADIF file")

                            Button("Clear Log") { vm.clearLoggedQSOs() }
                                .disabled(vm.loggedQSOs.isEmpty)
                                .accessibilityLabel("Clear FT8 QSO log")
                        }

                        Text("Logs every station that calls you. ADIF can be imported into most logging programs.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Auto-Sequence ─────────────────────────────────────────────
                GroupBox("Auto-Sequence") {                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Auto-sequence while CQ is running", isOn: $vm.isAutoSequenceEnabled)
                            .accessibilityLabel("Auto-sequence responding stations")
                        if vm.isAutoSequenceEnabled {
                            HStack(spacing: 12) {
                                Text("Priority:")
                                    .frame(width: 60, alignment: .leading)
                                Picker("Priority", selection: $vm.autoSequencePriority) {
                                    ForEach(FT8ViewModel.AutoSequencePriority.allCases, id: \.rawValue) { p in
                                        Text(p.rawValue).tag(p)
                                    }
                                }
                                .frame(minWidth: 160)
                                .accessibilityLabel("Auto-sequence priority")
                            }
                        }
                        Text("When enabled and CQ is running, automatically queues the highest-priority calling station each decode cycle.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Radio Setup ───────────────────────────────────────────────
                GroupBox("Radio Setup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Force USB mode", isOn: $forceUSB)
                        Toggle("Force Data Mode (USB-DATA via MD2)", isOn: $forceDataMode)
                        Toggle("Ensure LAN RX audio is running", isOn: $ensureLanAudio)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Advanced ─────────────────────────────────────────────────
                GroupBox("Advanced") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Hold live list updates (VoiceOver)", isOn: Binding(
                            get: { vm.holdDecodedListUpdates },
                            set: { vm.setHoldDecodedListUpdates($0) }
                        ))
                        .accessibilityLabel("Hold live decoded list updates for VoiceOver")

                        if vm.pendingDecodedMessagesCount > 0 {
                            Button("Load \(vm.pendingDecodedMessagesCount) queued decodes") {
                                vm.flushPendingDecodedMessages()
                            }
                            .accessibilityLabel("Load \(vm.pendingDecodedMessagesCount) queued decoded messages")
                        }

                        Toggle("Verbose FT8 logging", isOn: $vm.verboseFT8Logging)
                            .accessibilityLabel("Verbose FT8 logging")

                        if !vm.lastTxSummary.isEmpty {
                            Text("Last TX: \(vm.lastTxSummary)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        if !vm.activityLog.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Activity Log")
                                    .font(.headline)
                                Text(vm.activityLog.suffix(80).joined(separator: "\n"))
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("FT8 activity log")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}
