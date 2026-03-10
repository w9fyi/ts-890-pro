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

@Observable
final class FT8ViewModel {
    var isAutoReplyEnabled: Bool = false
    var simulateDecodedText: String = ""
    var decodedMessages: [DecodedMessage] = []
    var holdDecodedListUpdates: Bool = true
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

    struct DecodedMessage: Identifiable {
        let id = UUID()
        let receivedAt: Date
        let raw: String
        let caller: String
        let to: String
        let payload: String
        let isDirectedToMe: Bool
    }

    func appendLog(_ line: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        activityLog.append("[\(ts)] \(line)")
        if activityLog.count > 400 {
            activityLog.removeFirst(activityLog.count - 400)
        }
    }

    func processDecodedLine(_ line: String, myCall: String, myGrid: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.uppercased()
        if verboseFT8Logging {
            appendLog("RX: \(normalized)")
        }

        let upperCall = myCall.uppercased()
        let upperGrid = myGrid.uppercased()

        let parsed = parseDecodedLine(normalized, myCall: upperCall)
        if let msg = parsed {
            ingestDecodedMessage(msg)
        }

        guard !myCall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if isAutoReplyEnabled { appendLog("Auto-reply skipped: set your callsign first.") }
            return
        }

        // Drive the QSO state machine if global auto-reply is on,
        // OR if this message came from our manually-queued target (user explicitly chose to call them).
        let fromQueuedTarget = queuedTarget != nil && parsed?.caller == queuedTarget
        guard isAutoReplyEnabled || fromQueuedTarget else { return }

        if let reply = autoReply(forDecodedLine: normalized, myCall: upperCall, myGrid: upperGrid) {
            plannedTxText = reply
            txText = reply
            appendLog("Plan TX: \(reply)")
        }
    }

    private func ingestDecodedMessage(_ msg: DecodedMessage) {
        // Play Radar alert the first time a new station answers our CQ.
        if msg.isDirectedToMe && !alertedCallers.contains(msg.caller) {
            alertedCallers.insert(msg.caller)
            (NSSound(named: NSSound.Name("Radar"))
                ?? NSSound(named: NSSound.Name("Ping")))?.play()
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
        let r = "\(call) \(msg.caller) \(grid)"
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

        // Expect at least: CALLER MYCALL <X>
        guard tokens.count >= 2 else { return nil }
        let caller = tokens[0]
        let to = tokens[1]
        guard to == myCall else { return nil }

        let third = tokens.count >= 3 ? tokens[2] : ""
        let stage = qsoStageByCaller[caller] ?? .none

        // If caller sends us their grid (often the first directed call),
        // respond with our grid.
        if isGrid(third), stage == .none || stage == .sentGrid {
            qsoStageByCaller[caller] = .sentGrid
            return "\(myCall) \(caller) \(myGrid)"
        }

        // Signal report forms: "-10", "+02", "R-05", "R+00"
        if isReport(third) {
            // If they gave us a plain report, we respond with "R<report>".
            // If they gave "R<report>", we respond with "RRR".
            if third.hasPrefix("R") {
                if stage != .sentRRR {
                    qsoStageByCaller[caller] = .sentRRR
                    return "\(myCall) \(caller) RRR"
                }
                return nil
            } else {
                if stage != .sentRReport {
                    qsoStageByCaller[caller] = .sentRReport
                    return "\(myCall) \(caller) R\(third)"
                }
                return nil
            }
        }

        if third == "RRR" {
            if stage != .sent73 {
                qsoStageByCaller[caller] = .sent73
                if queuedTarget == caller { queuedTarget = nil }
                return "\(myCall) \(caller) 73"
            }
            return nil
        }

        if third == "73" {
            qsoStageByCaller[caller] = .sent73
            if queuedTarget == caller { queuedTarget = nil }
            return nil
        }

        // Unknown payload; ignore.
        return nil
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
        let caller = tokens[0]
        let to = tokens[1]
        guard Self.looksLikeHamCallsign(caller) else { return nil }
        guard Self.looksLikeHamCallsign(to) || to == "CQ" else { return nil }
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
                    } else {
                        self.lastDecodeSummary = "Decoded \(results.count) message\(results.count == 1 ? "" : "s")"
                        self.appendLog("\(proto.rawValue) decode: \(results.count) message(s)")
                        for r in results {
                            self.processDecodedLine(r.message, myCall: myCall, myGrid: myGrid)
                        }
                    }
                }
            }
        }
    }

    func setAutoDecodeEnabled(_ enabled: Bool, myCall: String, myGrid: String) {
        isAutoDecodeEnabled = enabled
        autoDecodeMyCall = myCall
        autoDecodeMyGrid = myGrid
        if enabled {
            appendLog("Auto-decode enabled (\(selectedProtocol.rawValue) \(Int(selectedProtocol.slotDuration))s slots)")
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
            .padding(.vertical, 12)

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
                selectedPresetID: $selectedPresetID,
                frequencyOverrideMHz: $frequencyOverrideMHz,
                forceUSB: $forceUSB,
                forceDataMode: $forceDataMode,
                ensureLanAudio: $ensureLanAudio,
                isPresented: $showSettings,
                startCQ: startCQ,
                stopCQ: stopCQ
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
        let trimmed = frequencyOverrideMHz.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let mhz = Double(trimmed) {
            return Int((mhz * 1_000_000.0).rounded())
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
        vm.preFT8Mode = radio.operatingMode
        vm.preFT8DataModeEnabled = radio.dataModeEnabled
        vm.preFT8MDMode = radio.mdMode
        vm.preFT8Summary = [
            vm.preFT8FrequencyHz != nil ? "freq=\(dialFrequencyLabelHz(vm.preFT8FrequencyHz!))" : nil,
            vm.preFT8Mode != nil ? "mode=\(vm.preFT8Mode!.label)" : nil,
            vm.preFT8MDMode != nil ? "md=\(vm.preFT8MDMode!)" : nil
        ].compactMap { $0 }.joined(separator: ", ")

        vm.clearDecodedMessages()   // fresh list on each Start
        vm.isFT8Running = true
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
        vm.isCQRunning = true
        vm.appendLog("CQ loop started parity=\(vm.cqParityRaw) txArmed=\(vm.isTxArmed)")
        AppFileLogger.shared.log("FT8: CQ start parity=\(vm.cqParityRaw) txArmed=\(vm.isTxArmed)")
        scheduleNextCQTick()
    }

    private func stopCQ() {
        vm.isCQRunning = false
        vm.nextCQTxAt = nil
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

        // Fire once at the next matching boundary; reschedule after each tick.
        let dt = max(0.01, next.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + dt) {
            guard vm.isCQRunning else { return }
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
        } else {
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
    @Binding var selectedPresetID: String
    @Binding var frequencyOverrideMHz: String
    @Binding var forceUSB: Bool
    @Binding var forceDataMode: Bool
    @Binding var ensureLanAudio: Bool
    @Binding var isPresented: Bool
    let startCQ: () -> Void
    let stopCQ: () -> Void

    private var selectedFrequencyHz: Int {
        let trimmed = frequencyOverrideMHz.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let mhz = Double(trimmed) {
            return Int((mhz * 1_000_000.0).rounded())
        }
        return FT8BandPreset.allPresets.first(where: { $0.id == selectedPresetID })?.frequencyHz ?? 14_074_000
    }

    private func dialLabel(_ hz: Int) -> String {
        String(format: "%.6f MHz", Double(hz) / 1_000_000.0)
    }

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

                // ── Auto-Reply ───────────────────────────────────────────────
                GroupBox("Auto-Reply") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Auto-reply to directed calls", isOn: $vm.isAutoReplyEnabled)
                            .accessibilityLabel("Auto-reply to directed calls")
                        Text("When enabled, the app generates and queues exchange replies automatically each slot.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── CQ ───────────────────────────────────────────────────────
                GroupBox("CQ") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button(vm.isCQRunning ? "Stop CQ" : "Start CQ") {
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
                            .frame(width: 160)
                            .accessibilityLabel("CQ cycle parity, even or odd")
                        }

                        Toggle("TX Armed (enables RF transmission)", isOn: $vm.isTxArmed)
                            .accessibilityLabel("Transmit armed")

                        if let next = vm.nextCQTxAt {
                            Text("Next TX: \(next.formatted(date: .omitted, time: .standard))")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Text("CQ message: CQ \(myCallsign.uppercased()) \(myGrid.uppercased())")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .accessibilityLabel("CQ message preview: CQ \(myCallsign.uppercased()) \(myGrid.uppercased())")
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

                // ── Band / Frequency ─────────────────────────────────────────
                GroupBox("Band / Frequency") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Picker("Band", selection: $selectedPresetID) {
                                ForEach(FT8BandPreset.allPresets) { p in
                                    Text(p.label).tag(p.id)
                                }
                            }
                            .frame(minWidth: 180)
                            .accessibilityLabel("FT8 band")

                            Text(dialLabel(selectedFrequencyHz))
                                .font(.system(.body, design: .monospaced))
                                .accessibilityLabel("Dial frequency \(dialLabel(selectedFrequencyHz))")
                        }

                        HStack(spacing: 12) {
                            Text("Override (MHz):")
                            TextField("e.g. 14.074", text: $frequencyOverrideMHz)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .accessibilityLabel("Frequency override in megahertz")
                            if !frequencyOverrideMHz.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Clear") { frequencyOverrideMHz = "" }
                            }
                        }

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
