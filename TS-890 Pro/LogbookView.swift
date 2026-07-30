//
//  LogbookView.swift
//  Kenwood control
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum LogbookUploadTarget { case qrz, clubLog, eqsl }

struct LogbookView: View {
    @Query(sort: \LogEntry.dateTime, order: .reverse) private var entries: [LogEntry]
    @Environment(\.modelContext) private var ctx
    @State private var showingNewQSO       = false
    @State private var searchText          = ""
    @State private var selectedEntry: LogEntry?
    @State private var uploadStatus        = ""
    @State private var showingUploadResult = false
    @State private var isUploading         = false
    @State private var showingImportPanel  = false
    @State private var importStatus        = ""
    @State private var showingImportResult = false
    @State private var showingUploadMenu   = false

    // Set from FrontPanelView so the new-QSO sheet pre-fills correctly.
    var radioFrequencyHz: Int    = 0
    var radioMode:        String = "SSB"
    var myCallsign:       String = ""

    private var filtered: [LogEntry] {
        guard !searchText.isEmpty else { return entries }
        let q = searchText.uppercased()
        return entries.filter {
            $0.callsign.contains(q) ||
            ($0.opName?.uppercased().contains(q) == true) ||
            ($0.mode.uppercased().contains(q)) ||
            ($0.country?.uppercased().contains(q) == true)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                logList
            }
            .navigationTitle("Logbook (\(entries.count))")
        } detail: {
            if let e = selectedEntry {
                LogEntryDetailView(entry: e, myCallsign: myCallsign, onUpload: uploadSingle)
            } else {
                Text("Select a contact")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNewQSO) {
            NavigationStack {
                QSOEntryView(
                    initialFrequencyHz: radioFrequencyHz,
                    initialMode:        radioMode
                )
            }
        }
        .alert("Upload Result", isPresented: $showingUploadResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadStatus)
        }
        .alert("Import Result", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importStatus)
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: Self.adifContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importADIF(from: url)
        }
    }

    private static let adifContentTypes: [UTType] = {
        var types: [UTType] = []
        if let adif = UTType(filenameExtension: "adif") { types.append(adif) }
        if let adi  = UTType(filenameExtension: "adi")  { types.append(adi) }
        if types.isEmpty { types = [.plainText] }
        return types
    }()

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                showingNewQSO = true
            } label: {
                Label("New QSO", systemImage: "plus")
            }
            .accessibilityLabel("Log new QSO")

            Button {
                showingImportPanel = true
            } label: {
                Label("Import ADIF", systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel("Import contacts from an ADIF file")

            Spacer()

            Button {
                exportADIF()
            } label: {
                Label("Export ADIF", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export log as ADIF file")

            if isUploading {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button("Upload to QRZ Logbook") { Task { await uploadAllPending(to: .qrz) } }
                    Button("Upload to Club Log")     { Task { await uploadAllPending(to: .clubLog) } }
                    Button("Upload to eQSL")         { Task { await uploadAllPending(to: .eqsl) } }
                    Divider()
                    Button(LOTWManager.hasCertificate() ? "Upload to LOTW" : "Sign & Upload to LOTW (TQSL)…") {
                        Task { await uploadToLOTW() }
                    }
                } label: {
                    Label("Upload…", systemImage: "arrow.up.to.line")
                }
                .accessibilityLabel("Upload contacts to online logging services")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .controlSize(.small)
    }

    // MARK: - List

    private var logList: some View {
        List(filtered, id: \.persistentModelID, selection: $selectedEntry) { e in
            LogEntryRow(entry: e)
                .accessibilityElement(children: .combine)
        }
        .searchable(text: $searchText, prompt: "Search callsign, mode, country…")
        .accessibilityLabel("Contacts list")
    }

    // MARK: - Actions

    private typealias UploadTarget = LogbookUploadTarget

    private func exportADIF() {
        let adif = LogbookManager.adif(from: entries, myCallsign: myCallsign.isEmpty ? nil : myCallsign)
        let panel = NSSavePanel()
        panel.title                = "Export ADIF"
        panel.nameFieldStringValue = "log.adif"
        panel.allowedContentTypes  = [.init(filenameExtension: "adif") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? adif.write(to: url, atomically: true, encoding: .utf8)
    }

    private func uploadToLOTW() async {
        let pending = entries.filter { !$0.uploadedLOTW }
        let toUpload = pending.isEmpty ? entries : pending

        if LOTWManager.hasCertificate() {
            isUploading = true
            defer { isUploading = false }
            do {
                let station = LOTWStationData.load()
                let result = try await LOTWManager.signAndUpload(
                    entries: toUpload,
                    station: station,
                    myCallsign: myCallsign
                )
                for e in toUpload { e.uploadedLOTW = true }
                uploadStatus = result
            } catch {
                uploadStatus = error.localizedDescription
            }
            showingUploadResult = true
        } else {
            // Fallback: open TQSL.app if installed
            let launched = LogbookManager.exportAndOpenWithTQSL(
                entries: toUpload,
                myCallsign: myCallsign.isEmpty ? nil : myCallsign
            )
            uploadStatus = launched
                ? "ADIF exported and opened in TQSL. Mark contacts as uploaded after TQSL confirms success. To skip this step, import your certificate in Settings → Logbook → LOTW."
                : "No LOTW certificate configured and TQSL is not installed. Import your .p12 in Settings → Logbook → LOTW."
            showingUploadResult = true
        }
    }

    private func uploadAllPending(to target: UploadTarget) async {
        let pending: [LogEntry]
        switch target {
        case .qrz:     pending = entries.filter { !$0.uploadedQRZLog }
        case .clubLog:  pending = entries.filter { !$0.uploadedClubLog }
        case .eqsl:    pending = entries.filter { !$0.uploadedEQSL }
        }
        guard !pending.isEmpty else {
            uploadStatus = "No pending contacts to upload."
            showingUploadResult = true
            return
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let count: Int
            switch target {
            case .qrz:
                count = try await LogbookManager.uploadToQRZ(entries: pending, myCallsign: myCallsign.isEmpty ? nil : myCallsign)
                for e in pending { e.uploadedQRZLog = true }
                uploadStatus = "Uploaded \(count) contact\(count == 1 ? "" : "s") to QRZ Logbook."
            case .clubLog:
                count = try await LogbookManager.uploadToClubLog(entries: pending, myCallsign: myCallsign)
                for e in pending { e.uploadedClubLog = true }
                uploadStatus = "Uploaded \(count) contact\(count == 1 ? "" : "s") to Club Log."
            case .eqsl:
                count = try await LogbookManager.uploadToEQSL(entries: pending, myCallsign: myCallsign.isEmpty ? nil : myCallsign)
                for e in pending { e.uploadedEQSL = true }
                uploadStatus = "Uploaded \(count) contact\(count == 1 ? "" : "s") to eQSL."
            }
        } catch {
            uploadStatus = error.localizedDescription
        }
        showingUploadResult = true
    }

    private func uploadSingle(entry: LogEntry, to target: UploadTarget) {
        Task {
            isUploading = true
            defer { isUploading = false }
            do {
                switch target {
                case .qrz:
                    let n = try await LogbookManager.uploadToQRZ(entries: [entry], myCallsign: myCallsign.isEmpty ? nil : myCallsign)
                    if n > 0 { entry.uploadedQRZLog = true }
                    uploadStatus = n > 0 ? "Uploaded to QRZ Logbook." : "QRZ returned 0 records."
                case .clubLog:
                    try await LogbookManager.uploadToClubLog(entries: [entry], myCallsign: myCallsign)
                    entry.uploadedClubLog = true
                    uploadStatus = "Uploaded to Club Log."
                case .eqsl:
                    try await LogbookManager.uploadToEQSL(entries: [entry], myCallsign: myCallsign.isEmpty ? nil : myCallsign)
                    entry.uploadedEQSL = true
                    uploadStatus = "Uploaded to eQSL."
                }
            } catch {
                uploadStatus = error.localizedDescription
            }
            showingUploadResult = true
        }
    }

    private func importADIF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = latin1
        } else {
            importStatus = "Could not read the selected file."
            showingImportResult = true
            return
        }
        let imported = LogbookManager.importADIF(text)
        guard !imported.isEmpty else {
            importStatus = "No valid QSO records found in the file."
            showingImportResult = true
            return
        }
        // Deduplicate: skip entries whose callsign+date already exist
        let existingKeys = Set(entries.map { "\($0.callsign)|\($0.adifDate)|\($0.adifTime)" })
        var added = 0
        for entry in imported {
            let key = "\(entry.callsign)|\(entry.adifDate)|\(entry.adifTime)"
            guard !existingKeys.contains(key) else { continue }
            ctx.insert(entry)
            added += 1
        }
        importStatus = added == imported.count
            ? "Imported \(added) contact\(added == 1 ? "" : "s")."
            : "Imported \(added) of \(imported.count) contacts (\(imported.count - added) duplicates skipped)."
        showingImportResult = true
    }
}

// MARK: - Row

private struct LogEntryRow: View {
    let entry: LogEntry

    private static let rowDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.timeZone  = TimeZone(abbreviation: "UTC")
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.callsign)
                    .font(.headline)
                Text(entry.opName ?? entry.country ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.rowDateFmt.string(from: entry.dateTime))
                    .font(.caption)
                HStack(spacing: 4) {
                    Text(entry.mode).font(.caption2)
                    Text(entry.frequencyMHz).font(.caption2)
                    if entry.uploadedLOTW {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to LOTW")
                    }
                    if entry.uploadedQRZLog {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to QRZ")
                    }
                    if entry.uploadedClubLog {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to Club Log")
                    }
                    if entry.uploadedEQSL {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(.purple)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to eQSL")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct LogEntryDetailView: View {
    @Bindable var entry: LogEntry
    let myCallsign: String
    let onUpload: (LogEntry, LogbookUploadTarget) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var confirmDelete = false

    private static let fullDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        f.timeZone  = TimeZone(abbreviation: "UTC")
        return f
    }()

    var body: some View {
        Form {
            Section("Contact") {
                LabeledContent("Callsign",    value: entry.callsign)
                LabeledContent("Date/Time",   value: Self.fullDateFmt.string(from: entry.dateTime) + " UTC")
                LabeledContent("Frequency",   value: "\(entry.frequencyMHz) MHz")
                LabeledContent("Mode",        value: entry.mode)
                LabeledContent("RST Sent",    value: entry.rstSent)
                LabeledContent("RST Rcvd",    value: entry.rstReceived)
            }
            if entry.opName != nil || entry.grid != nil || entry.country != nil {
                Section("Station") {
                    if let v = entry.opName  { LabeledContent("Name",    value: v) }
                    if let v = entry.grid    { LabeledContent("Grid",    value: v) }
                    if let v = entry.country { LabeledContent("Country", value: v) }
                    if let v = entry.state   { LabeledContent("State",   value: v) }
                    if let v = entry.city    { LabeledContent("City",    value: v) }
                }
            }
            if let notes = entry.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).font(.body)
                }
            }
            Section("Upload Status") {
                Toggle("LOTW", isOn: $entry.uploadedLOTW)
                    .accessibilityLabel("Marked as uploaded to LOTW")
                Toggle("QRZ Logbook", isOn: $entry.uploadedQRZLog)
                    .accessibilityLabel("Marked as uploaded to QRZ Logbook")
                Toggle("Club Log", isOn: $entry.uploadedClubLog)
                    .accessibilityLabel("Marked as uploaded to Club Log")
                Toggle("eQSL", isOn: $entry.uploadedEQSL)
                    .accessibilityLabel("Marked as uploaded to eQSL")
            }
            Section("Upload Now") {
                Button("Upload to LOTW") {
                    Task { await uploadSingleToLOTW(entry) }
                }
                .disabled(entry.uploadedLOTW)
                .accessibilityLabel("Upload this contact to LOTW")
                Button("Upload to QRZ Logbook") { onUpload(entry, .qrz) }
                    .disabled(entry.uploadedQRZLog)
                    .accessibilityLabel("Upload this contact to QRZ Logbook")
                Button("Upload to Club Log") { onUpload(entry, .clubLog) }
                    .disabled(entry.uploadedClubLog)
                    .accessibilityLabel("Upload this contact to Club Log")
                Button("Upload to eQSL") { onUpload(entry, .eqsl) }
                    .disabled(entry.uploadedEQSL)
                    .accessibilityLabel("Upload this contact to eQSL")
            }
            Section {
                Button("Delete Contact", role: .destructive) { confirmDelete = true }
                    .accessibilityLabel("Delete this contact from log")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.callsign)
        .confirmationDialog(
            "Delete \(entry.callsign)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { ctx.delete(entry) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func uploadSingleToLOTW(_ entry: LogEntry) async {
        do {
            let station = LOTWStationData.load()
            let result = try await LOTWManager.signAndUpload(
                entries: [entry],
                station: station,
                myCallsign: myCallsign
            )
            entry.uploadedLOTW = true
            _ = result
        } catch {
            // Surface error via accessibility announcement; detail pane has no alert state
            AccessibilityNotification.Announcement("LOTW upload failed: \(error.localizedDescription)").post()
        }
    }
}
