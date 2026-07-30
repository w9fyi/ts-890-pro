//
//  KNSAdminView.swift
//  Kenwood control
//
//  KNS server administration panel — configure the radio's built-in KNS server
//  without using the front panel.  Requires an active administrator login.
//

import SwiftUI

// MARK: - Main view

struct KNSAdminView: View {
    var radio: RadioState

    @State private var selectedTab: AdminTab = .kns

    enum AdminTab: String, CaseIterable {
        case kns   = "KNS"
        case voip  = "VoIP"
        case users = "Users"
        case admin = "Admin"
    }

    private var isAdmin: Bool {
        radio.knsAccountType == KenwoodKNS.AccountType.administrator.rawValue
    }
    private var isConnected: Bool {
        radio.connectionStatus == RadioState.ConnectionStatus.connected.rawValue
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            KNSSettingsTab(radio: radio, isAdmin: isAdmin)
                .tabItem { Label("KNS", systemImage: "network") }
                .tag(AdminTab.kns)

            KNSVoIPTab(radio: radio, isAdmin: isAdmin)
                .tabItem { Label("VoIP", systemImage: "mic.fill") }
                .tag(AdminTab.voip)

            KNSUsersTab(radio: radio, isAdmin: isAdmin)
                .tabItem { Label("Users", systemImage: "person.2") }
                .tag(AdminTab.users)

            KNSAdminTab(radio: radio, isAdmin: isAdmin)
                .tabItem { Label("Admin", systemImage: "key.fill") }
                .tag(AdminTab.admin)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Refresh") { radio.queryKNSAdminSettings() }
                    .disabled(!isConnected)
                    .accessibilityHint("Reads all KNS settings from the radio")
            }
        }
        .onAppear {
            if isConnected { radio.queryKNSAdminSettings() }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

// MARK: - KNS Settings tab

private struct KNSSettingsTab: View {
    var radio: RadioState
    var isAdmin: Bool

    var body: some View {
        Form {
            Section("KNS Operation Mode") {
                Picker("Mode", selection: Binding(
                    get: { KenwoodKNS.KNSMode(rawValue: radio.knsMode) ?? .off },
                    set: { radio.setKNSMode($0) }
                )) {
                    ForEach(KenwoodKNS.KNSMode.allCases, id: \.rawValue) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isAdmin)
                .accessibilityLabel("KNS Operation Mode")
            }

            Section("Session") {
                Picker("Session Timeout", selection: Binding(
                    get: { KenwoodKNS.SessionTimeout(rawValue: radio.knsSessionTimeout) ?? .unlimited },
                    set: { radio.setKNSSessionTimeout($0) }
                )) {
                    ForEach(KenwoodKNS.SessionTimeout.allCases, id: \.rawValue) { t in
                        Text(t.label).tag(t)
                    }
                }
                .disabled(!isAdmin)
            }

            Section("Options") {
                Toggle("Mute Speaker During Remote Operation", isOn: Binding(
                    get: { radio.knsSpeakerMute },
                    set: { radio.setKNSSpeakerMute($0) }
                ))
                .disabled(!isAdmin)

                Toggle("KNS Operation Access Log", isOn: Binding(
                    get: { radio.knsAccessLog },
                    set: { radio.setKNSAccessLog($0) }
                ))
                .disabled(!isAdmin)

                Toggle("Allow Registered User Remote Operations", isOn: Binding(
                    get: { radio.knsUserRemoteOps },
                    set: { radio.setKNSUserRemoteOps($0) }
                ))
                .disabled(!isAdmin)
            }

            Section("Welcome Message") {
                HStack(spacing: 8) {
                    TextField("Up to 128 characters", text: Binding(
                        get: { radio.knsWelcomeMessage },
                        set: { if $0.count <= 128 { radio.knsWelcomeMessage = $0 } }
                    ))
                    .accessibilityLabel("KNS welcome message")
                    Button("Save") { radio.setKNSWelcomeMessage(radio.knsWelcomeMessage) }
                    Button("Clear") { radio.setKNSWelcomeMessage("") }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - VoIP tab

private struct KNSVoIPTab: View {
    var radio: RadioState
    var isAdmin: Bool

    var body: some View {
        Form {
            Section("VoIP Function") {
                Toggle("Built-in VoIP Enabled", isOn: Binding(
                    get: { radio.knsVoipEnabled },
                    set: { radio.setKNSVoIPEnabled($0) }
                ))
                .disabled(!isAdmin)
            }

            Section("Audio Levels") {
                LabeledContent("VoIP Input Level: \(radio.voipInputLevel ?? 50)") {
                    Slider(value: Binding(
                        get: { Double(radio.voipInputLevel ?? 50) },
                        set: { radio.setVoipInputLevelDebounced(Int($0)) }
                    ), in: 0...100, step: 1)
                }
                .accessibilityLabel("VoIP audio input level, \(radio.voipInputLevel ?? 50)")

                LabeledContent("VoIP Output Level: \(radio.voipOutputLevel ?? 50)") {
                    Slider(value: Binding(
                        get: { Double(radio.voipOutputLevel ?? 50) },
                        set: { radio.setVoipOutputLevelDebounced(Int($0)) }
                    ), in: 0...100, step: 1)
                }
                .accessibilityLabel("VoIP audio output level, \(radio.voipOutputLevel ?? 50)")
            }

            Section("Jitter Buffer") {
                Picker("Jitter Buffer", selection: Binding(
                    get: { KenwoodKNS.JitterBuffer(rawValue: radio.knsJitterBuffer) ?? .ms200 },
                    set: { radio.setKNSJitterBuffer($0) }
                )) {
                    ForEach(KenwoodKNS.JitterBuffer.allCases, id: \.rawValue) { j in
                        Text(j.label).tag(j)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isAdmin)
                .accessibilityLabel("VoIP jitter buffer size")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Users tab

private struct KNSUsersTab: View {
    var radio: RadioState
    var isAdmin: Bool

    @State private var showAddSheet = false
    @State private var userToEdit: KNSUser? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text(radio.knsUsers.isEmpty
                     ? "\(radio.knsUserCount) registered user\(radio.knsUserCount == 1 ? "" : "s") — press Load to read"
                     : "\(radio.knsUserCount) registered user\(radio.knsUserCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                Button("Load Users") { radio.loadAllKNSUsers() }
                if isAdmin {
                    Button("Add User") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if radio.knsUsers.isEmpty {
                Text("No users loaded. Press Load Users to fetch the list from the radio.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(radio.knsUsers) { user in
                        KNSUserRow(user: user,
                                   canEdit: isAdmin,
                                   onEdit: { userToEdit = user },
                                   onDelete: { radio.deleteKNSUser(number: user.id) })
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            KNSUserEditorSheet(user: nil, isNew: true) { id, pw, desc, rxOnly, disabled in
                radio.addKNSUser(userID: id, password: pw, description: desc,
                                 rxOnly: rxOnly, disabled: disabled)
            }
        }
        .sheet(item: $userToEdit) { user in
            KNSUserEditorSheet(user: user, isNew: false) { id, pw, desc, rxOnly, disabled in
                radio.editKNSUser(number: user.id, userID: id, password: pw,
                                  description: desc, rxOnly: rxOnly, disabled: disabled)
            }
        }
    }
}

private struct KNSUserRow: View {
    let user: KNSUser
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(String(format: "%03d", user.id))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(user.userID.isEmpty ? "(no ID)" : user.userID)
                        .fontWeight(.medium)
                    if user.rxOnly   { badge("RX Only", .orange) }
                    if user.disabled { badge("Disabled", .red) }
                }
                if !user.description.isEmpty {
                    Text(user.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("User \(user.id): \(user.userID)\(user.rxOnly ? ", RX only" : "")\(user.disabled ? ", disabled" : "")\(user.description.isEmpty ? "" : ", \(user.description)")")

            if canEdit {
                Button("Edit")   { onEdit() }
                Button("Delete") { onDelete() }
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - User editor sheet

private struct KNSUserEditorSheet: View {
    let user: KNSUser?
    let isNew: Bool
    let onSave: (String, String, String, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var userID      = ""
    @State private var password    = ""
    @State private var description = ""
    @State private var rxOnly      = false
    @State private var disabled    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add KNS User" : "Edit User \(user.map { String(format: "%03d", $0.id) } ?? "")")
                .font(.title2)

            Group {
                labeled("User ID (max 32):") {
                    TextField("User ID", text: $userID)
                        .onChange(of: userID) { _, v in if v.count > 32 { userID = String(v.prefix(32)) } }
                }
                labeled("Password (max 32):") {
                    SecureField("Password", text: $password)
                        .onChange(of: password) { _, v in if v.count > 32 { password = String(v.prefix(32)) } }
                }
                labeled("Description (max 128):") {
                    TextField("Optional description", text: $description)
                        .onChange(of: description) { _, v in if v.count > 128 { description = String(v.prefix(128)) } }
                }
                Toggle("RX Only (no transmit)", isOn: $rxOnly)
                Toggle("Temporarily Disabled", isOn: $disabled)
            }

            HStack(spacing: 12) {
                Button("Save") {
                    onSave(userID, password, description, rxOnly, disabled)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(userID.isEmpty || password.isEmpty)
                Button("Cancel") { dismiss() }
            }
            .padding(.top, 4)
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            if let u = user {
                userID = u.userID; password = u.password
                description = u.description; rxOnly = u.rxOnly; disabled = u.disabled
            }
        }
    }

    @ViewBuilder
    private func labeled<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 160, alignment: .trailing)
            content()
        }
    }
}

// MARK: - Admin credentials / password tab

private struct KNSAdminTab: View {
    var radio: RadioState
    var isAdmin: Bool

    var body: some View {
        Form {
            if isAdmin {
                Section("Change Administrator Credentials") {
                    AdminCredentialChangeSection(radio: radio)
                }
            }
            Section("Change Your Password") {
                PasswordChangeSection(radio: radio)
            }
            if !radio.knsAdminChangeResult.isEmpty {
                Section {
                    Text(radio.knsAdminChangeResult)
                        .foregroundStyle(radio.knsAdminChangeResult.contains("Failed") ? .red : .green)
                        .accessibilityLabel(radio.knsAdminChangeResult)
                }
            }
            if !radio.knsPasswordChangeResult.isEmpty {
                Section {
                    Text(radio.knsPasswordChangeResult)
                        .foregroundStyle(radio.knsPasswordChangeResult.contains("Failed") ? .red : .green)
                        .accessibilityLabel(radio.knsPasswordChangeResult)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdminCredentialChangeSection: View {
    var radio: RadioState
    @State private var currentID = ""
    @State private var currentPW = ""
    @State private var newID     = ""
    @State private var newPW     = ""

    var body: some View {
        Group {
            SecureField("Current Admin ID",       text: $currentID)
            SecureField("Current Admin Password", text: $currentPW)
            TextField("New Admin ID",             text: $newID)
                .onChange(of: newID) { _, v in if v.count > 32 { newID = String(v.prefix(32)) } }
            SecureField("New Admin Password",     text: $newPW)
                .onChange(of: newPW) { _, v in if v.count > 32 { newPW = String(v.prefix(32)) } }
            Button("Apply") {
                radio.changeKNSAdminCredentials(currentID: currentID, currentPW: currentPW,
                                                newID: newID, newPW: newPW)
                currentID = ""; currentPW = ""; newID = ""; newPW = ""
            }
            .disabled(currentID.isEmpty || currentPW.isEmpty || newID.isEmpty || newPW.isEmpty)
            .accessibilityHint("Sends ##KN1 to update the administrator account on the radio")
        }
    }
}

private struct PasswordChangeSection: View {
    var radio: RadioState
    @State private var newPW = ""

    var body: some View {
        Group {
            SecureField("New Password", text: $newPW)
                .onChange(of: newPW) { _, v in if v.count > 32 { newPW = String(v.prefix(32)) } }
            Button("Change Password") {
                radio.changeKNSPassword(newPW)
                newPW = ""
            }
            .disabled(newPW.isEmpty)
            .accessibilityHint("Sends ##KNE to change the current logged-in user's password")
        }
    }
}
