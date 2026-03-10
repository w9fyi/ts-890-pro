//
//  SettingsView.swift
//  Kenwood control
//
//  macOS Settings window (⌘,) — tabbed panel for all configuration.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var radio: RadioState

    var body: some View {
        TabView {
            ConnectionSettingsTab(radio: radio)
                .tabItem { Label("Connection", systemImage: "network") }
                .tag(0)

            AudioSectionView(radio: radio)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
                .tag(1)

            EqualizerSectionView(radio: radio)
                .tabItem { Label("Equalizer", systemImage: "slider.horizontal.3") }
                .tag(2)

            MIDISectionView(radio: radio)
                .tabItem { Label("MIDI", systemImage: "pianokeys") }
                .tag(3)

            KeyboardShortcutsSectionView(radio: radio)
                .tabItem { Label("Keys", systemImage: "keyboard") }
                .tag(4)

            ConnectionProfilesView(radio: radio)
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
                .tag(5)

            KNSAdminView(radio: radio)
                .tabItem { Label("KNS Admin", systemImage: "server.rack") }
                .tag(6)

            LogsSectionView(radio: radio)
                .tabItem { Label("Logs", systemImage: "doc.text") }
                .tag(7)

            RadioMenuView(radio: radio)
                .tabItem { Label("Menu Access", systemImage: "list.bullet") }
                .tag(8)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - Connection Settings Tab

struct ConnectionSettingsTab: View {
    @Bindable var radio: RadioState
    private let diagnostics = DiagnosticsStore.shared

    @State private var host: String
    @State private var portString: String
    @State private var showKnsWizard = false
    @State private var lastConnectedHost: String
    @State private var editingCredentials = false

    init(radio: RadioState) {
        self.radio = radio
        _host = State(initialValue: KNSSettings.loadLastHost() ?? "192.168.50.56")
        _portString = State(initialValue: KNSSettings.loadLastPort().map(String.init) ?? "60000")
        _lastConnectedHost = State(initialValue: UserDefaults.standard.string(forKey: "LastConnectedHost") ?? "")
    }

    private var hasCredentials: Bool { !radio.adminId.isEmpty && !radio.adminPassword.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connection")
                    .font(.title2)

                Picker("Connection Type", selection: $radio.connectionType) {
                    ForEach(ConnectionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Connection type")

                if radio.connectionType == .usb {
                    usbSection
                } else {
                    lanSection
                }

                Divider()

                Toggle("Play Morse CQ on connect, 73 on disconnect", isOn: $radio.cwGreetingEnabled)
                    .font(.footnote)
                    .accessibilityLabel("Play C Q in Morse code through speakers on connect, and 73 on disconnect")

                if let err = diagnostics.lastError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Connection error: \(err)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear { radio.loadSavedCredentials(host: host) }
        .onChange(of: host) { _, newHost in
            radio.loadSavedCredentials(host: newHost)
            editingCredentials = false
        }
        .onChange(of: radio.knsAccountType) { _, _ in
            radio.loadSavedCredentials(host: host)
        }
        .sheet(isPresented: $showKnsWizard) {
            KnsWizardSheetView(
                radio: radio,
                host: $host,
                portString: $portString,
                showKnsWizard: $showKnsWizard,
                lastConnectedHost: lastConnectedHost
            )
        }
    }

    @ViewBuilder
    private var usbSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Serial Port:")
                if radio.availableSerialPorts.isEmpty {
                    Text("No ports found").foregroundStyle(.secondary)
                } else {
                    Picker("Serial port", selection: $radio.selectedSerialPort) {
                        ForEach(radio.availableSerialPorts) { port in
                            Text(port.displayName).tag(port.path)
                        }
                    }
                    .frame(minWidth: 260)
                }
                Button("Refresh") { radio.scanSerialPorts() }
                    .accessibilityLabel("Refresh serial port list")
            }

            HStack(spacing: 12) {
                Button("Connect") {
                    guard !radio.selectedSerialPort.isEmpty else { return }
                    radio.connectUSB(portPath: radio.selectedSerialPort)
                }
                Button("Disconnect") { radio.disconnect() }
            }

            Text("Status: \(radio.connectionStatus)")
                .font(.system(.body, design: .monospaced))

            Divider()

            Toggle("Enable USB Audio Monitor", isOn: Binding(
                get: { radio.isAudioMonitorRunning },
                set: { enabled in
                    if enabled { radio.startAudioMonitor() } else { radio.stopAudioMonitor() }
                }
            ))
            .accessibilityLabel("Enable USB Audio Monitor")
            .accessibilityValue(radio.isAudioMonitorRunning ? "On" : "Off")
            .accessibilityHint("Plays radio audio through Mac speakers with optional noise reduction")

            if let err = radio.audioMonitorError {
                Text(err).foregroundStyle(.red).font(.system(.body, design: .monospaced))
            }
        }
        .onAppear { radio.scanSerialPorts() }
    }

    @ViewBuilder
    private var lanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Host:")
                TextField("Host/IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
            }

            if hasCredentials && !editingCredentials {
                Text("Credentials saved for \(radio.adminId) (\(radio.knsAccountType == KenwoodKNS.AccountType.administrator.rawValue ? "Admin" : "User"))")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Edit Credentials…") { editingCredentials = true }
                    .font(.footnote)
            } else {
                HStack(spacing: 12) {
                    Text("Port:")
                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                Toggle("Use KNS Login", isOn: $radio.useKnsLogin)

                Picker("KNS Account Type", selection: $radio.knsAccountType) {
                    Text("Admin").tag(KenwoodKNS.AccountType.administrator.rawValue)
                    Text("User").tag(KenwoodKNS.AccountType.user.rawValue)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Text("Admin ID:")
                    TextField("Admin ID", text: $radio.adminId)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260)
                }

                HStack(spacing: 12) {
                    Text("Password:")
                    SecureField("Password", text: $radio.adminPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260)
                }

                Text("Credentials are saved when you connect.")
                    .font(.footnote).foregroundStyle(.secondary)

                if editingCredentials {
                    Button("Done Editing") { editingCredentials = false }.font(.footnote)
                }
            }

            HStack(spacing: 12) {
                Button("Connect") {
                    let port = Int(portString) ?? 0
                    AppFileLogger.shared.log("Settings: Connect pressed host=\(host) port=\(port)")
                    radio.connect(host: host, port: port)
                    editingCredentials = false
                }
                Button("Disconnect") { radio.disconnect() }
                Button("KNS Setup Wizard") { showKnsWizard = true }
            }

            Text("Status: \(radio.connectionStatus)")
                .font(.system(.body, design: .monospaced))
        }
    }
}
