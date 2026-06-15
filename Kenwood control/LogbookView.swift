//
//  LogbookView.swift
//  Kenwood control
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LogbookView: View {
    @Query(sort: \LogEntry.dateTime, order: .reverse) private var entries: [LogEntry]
    @Environment(\.modelContext) private var ctx
    @State private var showingNewQSO     = false
    @State private var searchText        = ""
    @State private var selectedEntry: LogEntry?
    @State private var exportPanel       = false
    @State private var uploadStatus      = ""
    @State private var showingUploadResult = false
    @State private var isUploading       = false

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
                LogEntryDetailView(entry: e, myCallsign: myCallsign, onUploadQRZ: uploadToQRZ)
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                showingNewQSO = true
            } label: {
                Label("New QSO", systemImage: "plus")
            }
            .accessibilityLabel("Log new QSO")

            Spacer()

            Button {
                exportADIF()
            } label: {
                Label("Export ADIF", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export log as ADIF")

            if isUploading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await uploadAllPending() }
                } label: {
                    Label("Upload to QRZ", systemImage: "arrow.up.to.line")
                }
                .accessibilityLabel("Upload pending contacts to QRZ Logbook")
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

    private func exportADIF() {
        let adif = LogbookManager.adif(from: entries, myCallsign: myCallsign.isEmpty ? nil : myCallsign)
        let panel = NSSavePanel()
        panel.title               = "Export ADIF"
        panel.nameFieldStringValue = "log.adif"
        panel.allowedContentTypes = [.init(filenameExtension: "adif") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? adif.write(to: url, atomically: true, encoding: .utf8)
    }

    private func uploadAllPending() async {
        let pending = entries.filter { !$0.uploadedQRZLog }
        guard !pending.isEmpty else {
            uploadStatus = "No pending contacts to upload."
            showingUploadResult = true
            return
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let count = try await LogbookManager.uploadToQRZ(
                entries: pending,
                myCallsign: myCallsign.isEmpty ? nil : myCallsign
            )
            for e in pending { e.uploadedQRZLog = true }
            uploadStatus = "Uploaded \(count) contact\(count == 1 ? "" : "s") to QRZ Logbook."
        } catch {
            uploadStatus = error.localizedDescription
        }
        showingUploadResult = true
    }

    private func uploadToQRZ(entry: LogEntry) {
        Task {
            isUploading = true
            defer { isUploading = false }
            do {
                let count = try await LogbookManager.uploadToQRZ(
                    entries: [entry],
                    myCallsign: myCallsign.isEmpty ? nil : myCallsign
                )
                if count > 0 { entry.uploadedQRZLog = true }
                uploadStatus = count > 0 ? "Contact uploaded to QRZ Logbook." : "Upload returned 0 records."
            } catch {
                uploadStatus = error.localizedDescription
            }
            showingUploadResult = true
        }
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
                    if entry.uploadedQRZLog {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to QRZ")
                    }
                    if entry.uploadedLOTW {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .font(.caption2)
                            .accessibilityLabel("Uploaded to LOTW")
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
    let onUploadQRZ: (LogEntry) -> Void
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
                Toggle("LOTW (exported via ADIF)", isOn: $entry.uploadedLOTW)
                    .accessibilityLabel("Marked as uploaded to LOTW")
                Toggle("QRZ Logbook", isOn: $entry.uploadedQRZLog)
                    .accessibilityLabel("Marked as uploaded to QRZ Logbook")
                Button("Upload to QRZ Now") { onUploadQRZ(entry) }
                    .disabled(entry.uploadedQRZLog)
                    .accessibilityLabel("Upload this contact to QRZ Logbook")
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
}
