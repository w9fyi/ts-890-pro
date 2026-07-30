//
//  ConnectionProfilesView.swift
//  Kenwood control
//
//  Saved KNS connection profiles — store multiple radio/account combinations
//  locally and connect to any with one tap.
//

import SwiftUI
import Observation

// MARK: - Model

struct ConnectionProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var useKNS: Bool
    var accountType: String   // KenwoodKNS.AccountType raw value
    var adminId: String
    // Password is stored in Keychain; only the admin ID is serialised here.

    /// Hint for the expected radio model. Auto-detected on connect via ID; command,
    /// but storing a hint lets the UI show the correct icon/label before connecting.
    var radioModelHint: String = KenwoodRadioModel.unknown.rawValue

    /// Preferred connection type. Profiles with .usb store the serial port path in `host`.
    var connectionType: ConnectionType = .lan

    /// Baud rate for USB serial profiles (ignored for LAN). Defaults to 115200 (TS-890S).
    var baudRate: Int = 115_200
}

// MARK: - Store

@Observable
final class ConnectionProfileStore {
    static let shared = ConnectionProfileStore()
    private let key = "ConnectionProfiles"

    var profiles: [ConnectionProfile] = []

    init() { load() }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) else { return }
        profiles = decoded
    }

    func add(_ profile: ConnectionProfile) {
        profiles.append(profile)
        save()
    }

    func remove(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        save()
    }

    func update(_ profile: ConnectionProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }
}

// MARK: - View

struct ConnectionProfilesView: View {
    var radio: RadioState
    private let store = ConnectionProfileStore.shared

    @State private var showingAddSheet = false
    @State private var editingProfile: ConnectionProfile? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connection Profiles")
                    .font(.title2)
                Spacer()
                Button("Add Profile") { showingAddSheet = true }
            }
            .padding()

            if store.profiles.isEmpty {
                Text("No saved profiles. Press Add Profile to save the current connection settings.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(store.profiles) { profile in
                        ProfileRowView(profile: profile) {
                            // Connect
                            applyProfile(profile)
                        } onEdit: {
                            editingProfile = profile
                        }
                    }
                    .onDelete { offsets in
                        store.remove(at: offsets)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ProfileEditorSheet(
                profile: currentConnectionAsProfile(),
                isNew: true
            ) { newProfile in
                store.add(newProfile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(
                profile: profile,
                isNew: false
            ) { updated in
                store.update(updated)
            }
        }
    }

    private func currentConnectionAsProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: "My Radio",
            host: radio.connectionType == .usb ? radio.selectedSerialPort : (KNSSettings.loadLastHost() ?? ""),
            port: KNSSettings.loadLastPort() ?? 60000,
            useKNS: radio.useKnsLogin,
            accountType: radio.knsAccountType,
            adminId: radio.adminId,
            radioModelHint: radio.radioModel.rawValue,
            connectionType: radio.connectionType
        )
    }

    private func applyProfile(_ profile: ConnectionProfile) {
        radio.useKnsLogin = profile.useKNS
        radio.knsAccountType = profile.accountType
        radio.adminId = profile.adminId
        // Load Keychain password for this host + account type + ID
        if profile.connectionType == .lan {
            if let pw = KNSSettings.loadPassword(
                host: profile.host,
                accountTypeRaw: profile.accountType,
                username: profile.adminId
            ) {
                radio.adminPassword = pw
            }
            let modelHint = KenwoodRadioModel(rawValue: profile.radioModelHint) ?? .unknown
            radio.connect(host: profile.host, port: profile.port, radioModelHint: modelHint)
        } else {
            // USB serial connection — host field stores the serial port path
            radio.usbBaudRate = profile.baudRate
            radio.connectUSB(portPath: profile.host)
        }
        AppFileLogger.shared.log("Profiles: connected via profile '\(profile.name)' type=\(profile.connectionType.rawValue) host=\(profile.host)")
    }
}

// MARK: - Profile Row

private struct ProfileRowView: View {
    let profile: ConnectionProfile
    let onConnect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .fontWeight(.medium)
                let modelName = KenwoodRadioModel(rawValue: profile.radioModelHint)?.description ?? "Unknown"
                let connLabel = profile.connectionType == .usb ? "USB" : (profile.useKNS ? "KNS" : "Direct LAN")
                Text("\(profile.connectionType == .usb ? profile.host : "\(profile.host):\(profile.port)")  •  \(connLabel)  •  \(modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(profile.name), \(profile.connectionType == .usb ? "USB \(profile.host)" : "\(profile.host) port \(profile.port)"), \(profile.connectionType == .usb ? "USB" : (profile.useKNS ? "KNS login" : "direct LAN")), \(KenwoodRadioModel(rawValue: profile.radioModelHint)?.description ?? "unknown radio")")

            Button("Edit") { onEdit() }
            Button("Connect") { onConnect() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / Edit Sheet

private struct ProfileEditorSheet: View {
    @State var profile: ConnectionProfile
    let isNew: Bool
    let onSave: (ConnectionProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var portString: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add Profile" : "Edit Profile")
                .font(.title2)
                .padding(.bottom, 4)

            Group {
                labeled("Profile Name:") {
                    TextField("e.g. Home Radio", text: $profile.name)
                }

                Picker("Connection Type", selection: $profile.connectionType) {
                    Text("LAN").tag(ConnectionType.lan)
                    Text("USB Serial").tag(ConnectionType.usb)
                }
                .pickerStyle(.segmented)

                Picker("Radio Model", selection: $profile.radioModelHint) {
                    Text("Auto-detect").tag(KenwoodRadioModel.unknown.rawValue)
                    Text("TS-890S").tag(KenwoodRadioModel.ts890s.rawValue)
                    Text("TS-990S").tag(KenwoodRadioModel.ts990s.rawValue)
                    Text("TS-590SG").tag(KenwoodRadioModel.ts590sg.rawValue)
                    Text("TS-590S").tag(KenwoodRadioModel.ts590s.rawValue)
                }

                if profile.connectionType == .usb {
                    labeled("Serial Port:") {
                        TextField("/dev/cu.SLAB_USBtoUART", text: $profile.host)
                    }
                    Picker("Baud Rate", selection: $profile.baudRate) {
                        Text("9600").tag(9_600)
                        Text("19200").tag(19_200)
                        Text("38400").tag(38_400)
                        Text("57600").tag(57_600)
                        Text("115200").tag(115_200)
                    }
                    .accessibilityLabel("USB baud rate")
                    .accessibilityHint("Must match the radio's COM menu setting")
                } else {
                    labeled("Host / IP:") {
                        TextField("192.168.1.x", text: $profile.host)
                    }
                    labeled("Port:") {
                        TextField("60000", text: $portString)
                            .frame(width: 100)
                    }
                    Toggle("Use KNS Login", isOn: $profile.useKNS)
                    Picker("Account Type", selection: $profile.accountType) {
                        Text("Admin").tag(KenwoodKNS.AccountType.administrator.rawValue)
                        Text("User").tag(KenwoodKNS.AccountType.user.rawValue)
                    }
                    .pickerStyle(.segmented)
                    labeled("Admin ID:") {
                        TextField("Admin ID", text: $profile.adminId)
                    }
                    labeled("Password:") {
                        SecureField("Password (stored in Keychain)", text: $password)
                    }
                }
            }

            Text("The password is saved in the macOS Keychain, not in the profile file.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Save") {
                    profile.port = Int(portString) ?? 60000
                    // Save password to Keychain if provided (LAN profiles only)
                    if profile.connectionType == .lan,
                       !password.isEmpty, !profile.adminId.isEmpty, !profile.host.isEmpty {
                        KNSSettings.saveUsername(profile.adminId, host: profile.host, accountTypeRaw: profile.accountType)
                        KNSSettings.savePassword(password, host: profile.host, accountTypeRaw: profile.accountType, username: profile.adminId)
                    }
                    onSave(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
            }
            .padding(.top, 4)
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(minWidth: 440, minHeight: 360)
        .onAppear {
            portString = String(profile.port)
            // Pre-fill password from Keychain
            if !profile.adminId.isEmpty, !profile.host.isEmpty {
                password = KNSSettings.loadPassword(
                    host: profile.host,
                    accountTypeRaw: profile.accountType,
                    username: profile.adminId
                ) ?? ""
            }
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
            content()
        }
    }
}
