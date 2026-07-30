//
//  QSOEntryView.swift
//  Kenwood control
//
//  New-QSO sheet — pre-fills frequency and mode from the live radio state,
//  integrates callsign lookup, and saves to SwiftData.
//

import SwiftUI
import SwiftData

struct QSOEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @StateObject private var lookup = CallsignLookupService()

    // Optionally pre-seed from live radio state.
    var initialFrequencyHz: Int    = 0
    var initialMode:        String = "SSB"

    // QSO fields
    @State private var callsign    = ""
    @State private var frequencyHz = 0
    @State private var mode        = "SSB"
    @State private var rstSent     = "59"
    @State private var rstReceived = "59"
    @State private var notes       = ""
    @State private var dateTime    = Date()

    // Lookup state
    @State private var lookupResult: CallsignInfo?
    @State private var lookupSource: CallsignLookupSource = .qrz
    @State private var lookupError: String?
    @State private var freqString  = ""

    private let modes = ["SSB","CW","FM","AM","FSK","FT8","FT4","PSK31","RTTY","FREEDV","RADE"]

    var body: some View {
        Form {
            callsignSection
            contactSection
            lookupInfoSection
            notesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 540)
        .navigationTitle("Log New QSO")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityLabel("Cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveQSO() }
                    .disabled(callsign.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Save QSO")
            }
        }
        .onAppear {
            frequencyHz = initialFrequencyHz
            freqString  = initialFrequencyHz > 0
                ? String(format: "%.3f", Double(initialFrequencyHz) / 1_000_000)
                : ""
            mode        = initialMode
        }
    }

    // MARK: - Sections

    private var callsignSection: some View {
        Section("Callsign Lookup") {
            HStack(spacing: 8) {
                TextField("Callsign", text: $callsign)
                    .textCase(.uppercase)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Callsign")
                    .onChange(of: callsign) { _, _ in lookupResult = nil; lookupError = nil }

                if lookup.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await performLookup() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(callsign.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Look up callsign")
                }
            }

            Picker("Source", selection: $lookupSource) {
                ForEach(CallsignLookupSource.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .accessibilityLabel("Lookup source")

            if let err = lookupError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel("Lookup error: \(err)")
            }
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            DatePicker("Date / Time (UTC)", selection: $dateTime)
                .environment(\.timeZone, TimeZone(abbreviation: "UTC")!)
                .accessibilityLabel("Date and time in UTC")

            HStack {
                TextField("Frequency (MHz)", text: $freqString)
                    .accessibilityLabel("Frequency in megahertz")
                    .onSubmit { parseFreq() }
                Text("MHz").foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $mode) {
                ForEach(modes, id: \.self) { Text($0).tag($0) }
            }
            .accessibilityLabel("Operating mode")

            HStack {
                TextField("RST Sent", text: $rstSent)
                    .frame(width: 80)
                    .accessibilityLabel("RST sent")
                Spacer()
                TextField("RST Rcvd", text: $rstReceived)
                    .frame(width: 80)
                    .accessibilityLabel("RST received")
            }
        }
    }

    @ViewBuilder
    private var lookupInfoSection: some View {
        if let info = lookupResult {
            Section("Station Info (from \(info.source.rawValue))") {
                if let v = info.name        { LabeledContent("Name",    value: v) }
                if let v = info.grid        { LabeledContent("Grid",    value: v) }
                if let v = info.licenseClass { LabeledContent("Class",  value: v) }
                if let v = info.country     { LabeledContent("Country", value: v) }
                if let state = info.state   { LabeledContent("State",   value: state) }
                if let v = info.city        { LabeledContent("City",    value: v) }
                if let v = info.email       { LabeledContent("Email",   value: v) }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
                .accessibilityLabel("Notes")
        }
    }

    // MARK: - Actions

    private func performLookup() async {
        lookupError = nil
        do {
            lookupResult = try await lookup.lookup(
                callsign: callsign.uppercased().trimmingCharacters(in: .whitespaces),
                source: lookupSource
            )
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func parseFreq() {
        let s = freqString.trimmingCharacters(in: .whitespaces)
        if let mhz = Double(s) {
            frequencyHz = Int(mhz * 1_000_000)
        }
    }

    private func saveQSO() {
        parseFreq()
        let entry = LogEntry(
            callsign:    callsign.uppercased().trimmingCharacters(in: .whitespaces),
            dateTime:    dateTime,
            frequencyHz: frequencyHz,
            mode:        mode,
            rstSent:     rstSent,
            rstReceived: rstReceived,
            opName:      lookupResult?.name,
            grid:        lookupResult?.grid,
            country:     lookupResult?.country,
            state:       lookupResult?.state,
            city:        lookupResult?.city,
            notes:       notes.isEmpty ? nil : notes
        )
        ctx.insert(entry)
        dismiss()
    }
}
