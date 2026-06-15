//
//  LogbookSettingsView.swift
//  Kenwood control
//
//  Settings tab: credentials for QRZ lookup, HamQTH lookup, LOTW, and QRZ Logbook upload.
//

import SwiftUI

struct LogbookSettingsView: View {
    // QRZ XML lookup
    @State private var qrzUser     = ""
    @State private var qrzPass     = ""
    // HamQTH lookup
    @State private var hamqthUser  = ""
    @State private var hamqthPass  = ""
    // QRZ Logbook API key (username field is unused; password = API key)
    @State private var qrzLogKey   = ""
    // My callsign for ADIF station header
    @State private var myCallsign  = ""
    @State private var savedBanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                infoBox

                // My callsign
                GroupBox("My Station") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Used in ADIF exports and QRZ uploads as STATION_CALLSIGN.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("My callsign (e.g. AI5OS)", text: $myCallsign)
                            .textCase(.uppercase)
                            .autocorrectionDisabled()
                            .accessibilityLabel("My callsign")
                    }
                    .padding(8)
                }

                // QRZ.com lookup
                GroupBox("QRZ.com Callsign Lookup") {
                    credentialFields(userLabel: "Username", user: $qrzUser, passLabel: "Password", pass: $qrzPass)
                        .padding(8)
                }

                // HamQTH lookup
                GroupBox("HamQTH.com Callsign Lookup") {
                    credentialFields(userLabel: "Username", user: $hamqthUser, passLabel: "Password", pass: $hamqthPass)
                        .padding(8)
                }

                // QRZ Logbook
                GroupBox("QRZ Logbook Upload") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter your QRZ Logbook API key. Find it at qrz.com → Log → Settings → API.")
                            .font(.caption).foregroundStyle(.secondary)
                        SecureField("QRZ Logbook API key", text: $qrzLogKey)
                            .accessibilityLabel("QRZ Logbook API key")
                    }
                    .padding(8)
                }

                // LOTW
                GroupBox("LOTW (Logbook of the World)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TS-890 Pro exports ADIF files. Use TQSL to sign and upload to LOTW.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("After exporting an ADIF log, open it in TQSL.app to submit to LOTW.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let tqsl = tqslPath() {
                            Label("TQSL found: \(tqsl)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        } else {
                            Label("TQSL not found — download from lotw.arrl.org", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .padding(8)
                }

                saveButton
            }
            .padding(20)
        }
        .onAppear(perform: loadCredentials)
    }

    // MARK: - Sub-views

    private var infoBox: some View {
        Text("Credentials are stored in the system Keychain and never leave your Mac except to authenticate with the respective service.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func credentialFields(userLabel: String, user: Binding<String>,
                                  passLabel: String, pass: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(userLabel, text: user)
                .textContentType(.username)
                .autocorrectionDisabled()
                .accessibilityLabel(userLabel)
            SecureField(passLabel, text: pass)
                .textContentType(.password)
                .accessibilityLabel(passLabel)
        }
    }

    private var saveButton: some View {
        HStack {
            Button("Save Credentials") { saveCredentials() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Save all credentials to Keychain")

            if savedBanner {
                Label("Saved", systemImage: "checkmark")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Persistence

    private func loadCredentials() {
        myCallsign = UserDefaults.standard.string(forKey: "logbook_myCallsign") ?? ""
        if let c = KeychainHelper.shared.retrieve(service: .qrz)    { qrzUser    = c.username; qrzPass    = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .hamqth)  { hamqthUser = c.username; hamqthPass = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .qrzLog)  { qrzLogKey  = c.password }
    }

    private func saveCredentials() {
        UserDefaults.standard.set(myCallsign.uppercased(), forKey: "logbook_myCallsign")
        if !qrzUser.isEmpty    { KeychainHelper.shared.save(username: qrzUser,    password: qrzPass,    service: .qrz)    }
        if !hamqthUser.isEmpty { KeychainHelper.shared.save(username: hamqthUser, password: hamqthPass, service: .hamqth) }
        if !qrzLogKey.isEmpty  { KeychainHelper.shared.save(username: "apikey",   password: qrzLogKey,  service: .qrzLog) }
        withAnimation { savedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { savedBanner = false } }
    }

    private func tqslPath() -> String? {
        let candidates = ["/Applications/TQSL.app", "/usr/local/bin/tqsl"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
