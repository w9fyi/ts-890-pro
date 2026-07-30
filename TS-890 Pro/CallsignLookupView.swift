//
//  CallsignLookupView.swift
//  Kenwood control
//
//  Standalone callsign lookup sheet — accessible from anywhere in the UI.
//

import SwiftUI

struct CallsignLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CallsignLookupService()

    @State private var callsign       = ""
    @State private var source: CallsignLookupSource = .qrz
    @State private var result: CallsignInfo?
    @State private var errorMsg: String?

    var body: some View {
        Form {
            Section("Lookup") {
                HStack(spacing: 8) {
                    TextField("Callsign", text: $callsign)
                        .textCase(.uppercase)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Callsign to look up")
                        .onSubmit { Task { await doLookup() } }
                        .onChange(of: callsign) { _, _ in result = nil; errorMsg = nil }

                    if service.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Look Up") { Task { await doLookup() } }
                            .disabled(callsign.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Perform lookup")
                    }
                }

                Picker("Source", selection: $source) {
                    ForEach(CallsignLookupSource.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Lookup source")

                if let err = errorMsg {
                    Text(err).foregroundStyle(.red).font(.caption)
                        .accessibilityLabel("Error: \(err)")
                }
            }

            if let info = result {
                Section("Result from \(info.source.rawValue)") {
                    row("Callsign",    info.callsign)
                    if let v = info.name         { row("Name",         v) }
                    if let v = info.licenseClass { row("Class",        v) }
                    if let v = info.grid         { row("Grid",         v) }
                    if let v = info.country      { row("Country",      v) }
                    if let v = info.state        { row("State",        v) }
                    if let v = info.city         { row("City",         v) }
                    if let v = info.address      { row("Address",      v) }
                    if let v = info.zip          { row("ZIP",          v) }
                    if let v = info.email        { row("Email",        v) }
                    if let la = info.latitude, let lo = info.longitude {
                        row("Coords", String(format: "%.4f, %.4f", la, lo))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 480)
        .navigationTitle("Callsign Lookup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .accessibilityLabel("Close lookup")
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private func doLookup() async {
        errorMsg = nil
        do {
            result = try await service.lookup(
                callsign: callsign.uppercased().trimmingCharacters(in: .whitespaces),
                source: source
            )
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
