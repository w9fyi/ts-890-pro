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

            RigctldSettingsView(radio: radio)
                .tabItem { Label("rigctld", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(9)

            LogbookSettingsView()
                .tabItem { Label("Logbook", systemImage: "book.closed") }
                .tag(10)
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

// MARK: - rigctld Settings Tab

struct RigctldSettingsView: View {
    @Bindable var radio: RadioState
    @State private var portString: String

    init(radio: RadioState) {
        self.radio = radio
        _portString = State(initialValue: String(radio.rigctldPort))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("rigctld Server")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)

                Text("Exposes a Hamlib-compatible TCP endpoint so WSJT-X, fldigi, JS8Call, flrig, and TillyMac can connect to TS-890 Pro as their radio backend.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle("Enable rigctld server", isOn: $radio.rigctldEnabled)
                    .accessibilityHint("When on, TS-890 Pro listens on the configured port for Hamlib rigctld commands.")

                HStack(spacing: 12) {
                    Text("Port:")
                    TextField("4532", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit { applyPort() }
                        .onChange(of: portString) { _, _ in applyPort() }
                    Text("(default: \(RigctldServer.defaultPort))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .disabled(!radio.rigctldEnabled)

                if radio.rigctldEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                        Text("Listening on localhost:\(radio.rigctldPort)")
                            .font(.callout)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("rigctld server active on port \(radio.rigctldPort)")
                }

                Divider()

                Text("How to connect WSJT-X:")
                    .font(.headline)
                Text("Radio → Rig: Hamlib NET rigctl  |  Network Server: localhost:\(radio.rigctldPort)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)

                Text("How to connect fldigi / JS8Call / flrig:")
                    .font(.headline)
                Text("Rig: rigctld  |  Host: localhost  |  Port: \(radio.rigctldPort)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)

                Text("How to connect TillyMac:")
                    .font(.headline)
                Text("In TillyMac settings, set rigctld host: localhost, port: \(radio.rigctldPort)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !radio.rigctldLog.isEmpty {
                    Divider()
                    Text("Server Log")
                        .font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(radio.rigctldLog.suffix(50), id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 140)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button("Clear Log") { radio.rigctldLog.removeAll() }
                        .font(.callout)
                }
            }
            .padding()
        }
        .frame(minWidth: 480)
    }

    private func applyPort() {
        guard let p = Int(portString), p > 0, p <= 65535 else { return }
        radio.rigctldPort = p
    }
}
