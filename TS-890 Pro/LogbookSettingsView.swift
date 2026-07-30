//
//  LogbookSettingsView.swift
//  Kenwood control
//
//  Settings tab: credentials for QRZ lookup, HamQTH lookup, LOTW, and QRZ Logbook upload.
//

import SwiftUI
import UniformTypeIdentifiers

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
    // LOTW native credentials + station data
    @State private var lotwUser         = ""
    @State private var lotwPass         = ""
    @State private var lotwCertSubject  = ""
    @State private var lotwCertPass     = ""
    @State private var lotwShowingPicker = false
    @State private var lotwCertError    = ""
    @State private var lotwDXCC         = 291
    @State private var lotwITU          = 7
    @State private var lotwCQ           = 4
    @State private var lotwARRL         = ""
    @State private var lotwState        = ""
    @State private var lotwGrid         = ""
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

                // LOTW — native signing
                GroupBox("LOTW (Logbook of the World)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Import your TQSL certificate once — TS-890 Pro will sign and upload directly to LOTW without any external tools.")
                            .font(.caption).foregroundStyle(.secondary)

                        // Certificate status
                        if !lotwCertSubject.isEmpty {
                            Label("Certificate: \(lotwCertSubject)", systemImage: "lock.fill")
                                .foregroundStyle(.green).font(.caption)
                        } else {
                            Label("No certificate imported", systemImage: "lock.open")
                                .foregroundStyle(.secondary).font(.caption)
                        }

                        // Import button + password
                        HStack(spacing: 8) {
                            SecureField(".p12 password", text: $lotwCertPass)
                                .accessibilityLabel("Certificate file password")
                                .frame(maxWidth: 180)
                            Button("Import .p12…") { lotwShowingPicker = true }
                                .accessibilityLabel("Import TQSL certificate file")
                            if !lotwCertSubject.isEmpty {
                                Button("Remove") {
                                    LOTWManager.deleteCertificate()
                                    lotwCertSubject = ""
                                }
                                .foregroundStyle(.red)
                                .accessibilityLabel("Remove stored LOTW certificate")
                            }
                        }
                        if !lotwCertError.isEmpty {
                            Text(lotwCertError).font(.caption).foregroundStyle(.red)
                        }
                        Text("Export your certificate from TQSL: Certificates menu → Save Certificate to File.")
                            .font(.caption2).foregroundStyle(.secondary)

                        Divider()

                        // LOTW credentials
                        Text("LOTW Account").font(.caption).fontWeight(.semibold)
                        credentialFields(userLabel: "LOTW Username", user: $lotwUser, passLabel: "LOTW Password", pass: $lotwPass)

                        Divider()

                        // Station data
                        Text("Station Location").font(.caption).fontWeight(.semibold)
                        Text("Required for LOTW. These match the station location configured in TQSL.")
                            .font(.caption2).foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            LabeledContent("DXCC Code") {
                                TextField("291", value: $lotwDXCC, format: .number)
                                    .frame(width: 60)
                                    .accessibilityLabel("DXCC entity code — 291 for USA")
                            }
                            LabeledContent("ITU Zone") {
                                TextField("7", value: $lotwITU, format: .number)
                                    .frame(width: 50)
                                    .accessibilityLabel("ITU zone")
                            }
                            LabeledContent("CQ Zone") {
                                TextField("4", value: $lotwCQ, format: .number)
                                    .frame(width: 50)
                                    .accessibilityLabel("CQ zone")
                            }
                        }
                        HStack(spacing: 12) {
                            LabeledContent("ARRL Section") {
                                TextField("e.g. STX", text: $lotwARRL)
                                    .frame(width: 80)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("ARRL section — required for US stations")
                            }
                            LabeledContent("State") {
                                TextField("e.g. TX", text: $lotwState)
                                    .frame(width: 50)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("US state — two-letter code")
                            }
                            LabeledContent("Grid") {
                                TextField("e.g. EM10", text: $lotwGrid)
                                    .frame(width: 70)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Grid locator")
                            }
                        }
                    }
                    .padding(8)
                }
                .fileImporter(
                    isPresented: $lotwShowingPicker,
                    allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data],
                    allowsMultipleSelection: false
                ) { result in
                    guard case .success(let urls) = result, let url = urls.first else { return }
                    importLOTWCert(from: url)
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
        if let c = KeychainHelper.shared.retrieve(service: .lotw)     { lotwUser     = c.username; lotwPass   = c.password }
        lotwCertSubject = LOTWManager.certificateSubject() ?? ""
        let station = LOTWStationData.load()
        lotwDXCC  = station.dxccEntityCode
        lotwITU   = station.ituZone
        lotwCQ    = station.cqZone
        lotwARRL  = station.arrlSection
        lotwState = station.usState
        lotwGrid  = station.gridLocator
    }

    private func saveCredentials() {
        UserDefaults.standard.set(myCallsign.uppercased(), forKey: "logbook_myCallsign")
        if !qrzUser.isEmpty      { KeychainHelper.shared.save(username: qrzUser,      password: qrzPass,    service: .qrz)     }
        if !hamqthUser.isEmpty   { KeychainHelper.shared.save(username: hamqthUser,   password: hamqthPass, service: .hamqth)  }
        if !qrzLogKey.isEmpty    { KeychainHelper.shared.save(username: "apikey",     password: qrzLogKey,  service: .qrzLog)  }
        if !clubLogEmail.isEmpty { KeychainHelper.shared.save(username: clubLogEmail, password: clubLogKey, service: .clubLog) }
        if !eqslUser.isEmpty     { KeychainHelper.shared.save(username: eqslUser,     password: eqslPass,   service: .eqsl)    }
        if !lotwUser.isEmpty     { KeychainHelper.shared.save(username: lotwUser,     password: lotwPass,   service: .lotw)    }
        var station = LOTWStationData()
        station.dxccEntityCode = lotwDXCC
        station.ituZone        = lotwITU
        station.cqZone         = lotwCQ
        station.arrlSection    = lotwARRL.uppercased()
        station.usState        = lotwState.uppercased()
        station.gridLocator    = lotwGrid.uppercased()
        station.save()
        withAnimation { savedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { savedBanner = false } }
    }

    private func importLOTWCert(from url: URL) {
        lotwCertError = ""
        guard url.startAccessingSecurityScopedResource() else {
            lotwCertError = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            lotwCertError = "Could not read the file."
            return
        }
        do {
            try LOTWManager.importCertificate(p12Data: data, password: lotwCertPass)
            lotwCertSubject = LOTWManager.certificateSubject() ?? "Imported"
            lotwCertPass = ""
        } catch {
            lotwCertError = error.localizedDescription
        }
    }
}
