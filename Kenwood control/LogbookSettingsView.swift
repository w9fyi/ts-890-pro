//
//  LogbookSettingsView.swift
//  Kenwood control
//
//  Settings tab: credentials for QRZ lookup, HamQTH lookup, LOTW, and QRZ Logbook upload.
//

import SwiftUI

struct LogbookSettingsView: View {
    // QRZ XML lookup
    @State private var qrzUser      = ""
    @State private var qrzPass      = ""
    // HamQTH lookup
    @State private var hamqthUser   = ""
    @State private var hamqthPass   = ""
    // QRZ Logbook API key (username field is unused; password = API key)
    @State private var qrzLogKey    = ""
    // Club Log (clublog.org): email + API key (callsign from My Station)
    @State private var clubLogEmail = ""
    @State private var clubLogKey   = ""
    // eQSL (eqsl.cc): username + password
    @State private var eqslUser     = ""
    @State private var eqslPass     = ""
    // My callsign for ADIF station header
    @State private var myCallsign   = ""
    @State private var savedBanner  = false

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

                // Club Log
                GroupBox("Club Log (clublog.org)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upload contacts to Club Log for DX statistics and awards tracking. Your callsign comes from the My Station field above.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Email address", text: $clubLogEmail)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Club Log email address")
                        SecureField("API key", text: $clubLogKey)
                            .accessibilityLabel("Club Log API key")
                        Text("Find your API key at clublog.org → Settings.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                // eQSL
                GroupBox("eQSL (eqsl.cc)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upload contacts to eQSL for electronic QSL card exchange.")
                            .font(.caption).foregroundStyle(.secondary)
                        credentialFields(userLabel: "eQSL Username", user: $eqslUser, passLabel: "eQSL Password", pass: $eqslPass)
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
        if let c = KeychainHelper.shared.retrieve(service: .qrz)     { qrzUser      = c.username; qrzPass    = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .hamqth)   { hamqthUser   = c.username; hamqthPass = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .qrzLog)   { qrzLogKey    = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .clubLog)  { clubLogEmail = c.username; clubLogKey = c.password }
        if let c = KeychainHelper.shared.retrieve(service: .eqsl)     { eqslUser     = c.username; eqslPass   = c.password }
    }

    private func saveCredentials() {
        UserDefaults.standard.set(myCallsign.uppercased(), forKey: "logbook_myCallsign")
        if !qrzUser.isEmpty      { KeychainHelper.shared.save(username: qrzUser,      password: qrzPass,    service: .qrz)     }
        if !hamqthUser.isEmpty   { KeychainHelper.shared.save(username: hamqthUser,   password: hamqthPass, service: .hamqth)  }
        if !qrzLogKey.isEmpty    { KeychainHelper.shared.save(username: "apikey",     password: qrzLogKey,  service: .qrzLog)  }
        if !clubLogEmail.isEmpty { KeychainHelper.shared.save(username: clubLogEmail, password: clubLogKey, service: .clubLog) }
        if !eqslUser.isEmpty     { KeychainHelper.shared.save(username: eqslUser,     password: eqslPass,   service: .eqsl)    }
        withAnimation { savedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { savedBanner = false } }
    }

    private func tqslPath() -> String? {
        let candidates = ["/Applications/TQSL.app", "/usr/local/bin/tqsl"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
