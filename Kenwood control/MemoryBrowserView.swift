//
//  MemoryBrowserView.swift
//  Kenwood control
//
//  Picker-based memory channel browser with in-place editing.
//  Opened as a sheet from MemoriesButton in TXRow.
//

import SwiftUI

struct MemoryBrowserView: View {
    var radio: RadioState

    @State private var selectedChannelID: Int = 0
    @State private var editFreqMHz: String = ""
    @State private var editName: String = ""
    @State private var editMode: KenwoodCAT.OperatingMode = .usb
    @State private var editFMNarrow: Bool = false

    private var selectedChannel: MemoryChannel? {
        radio.memoryChannels.first(where: { $0.id == selectedChannelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack {
                Text("Memory Channels").font(.title2)
                Spacer()
                if radio.isLoadingAllMemories {
                    ProgressView()
                        .scaleEffect(0.7)
                        .accessibilityLabel("Loading memory channels")
                }
                Button("Load All") { radio.loadAllMemoryChannels() }
                    .disabled(radio.isLoadingAllMemories)
                    .accessibilityHint("Reads all 120 memory channels from the radio")
            }

            Divider()

            // Channel selector
            HStack(spacing: 10) {
                Text("Channel:")

                Picker("Channel", selection: $selectedChannelID) {
                    ForEach(0..<120, id: \.self) { i in
                        Text(channelPickerLabel(i)).tag(i)
                    }
                }
                .frame(minWidth: 260)
                .accessibilityLabel("Memory channel")
                .onChange(of: selectedChannelID) { _, id in
                    if let ch = radio.memoryChannels.first(where: { $0.id == id }) {
                        loadEditFields(from: ch)
                    } else {
                        radio.queryMemoryChannel(id)
                        editFreqMHz = ""
                        editName = ""
                        editMode = .usb
                        editFMNarrow = false
                    }
                }

                Stepper("", value: $selectedChannelID, in: 0...119)
                    .labelsHidden()
                    .accessibilityLabel("Step channel number")

                Divider().frame(height: 18)

                Button("Recall") { radio.recallMemoryChannel(selectedChannelID) }
                    .accessibilityHint("Copies channel \(selectedChannelID) frequency to VFO")

                Button("Tune") {
                    radio.setMemoryMode(enabled: true)
                    radio.recallMemoryChannel(selectedChannelID)
                }
                .accessibilityHint("Switches to memory mode and tunes to channel \(selectedChannelID)")

                Button("Return to VFO") { radio.setMemoryMode(enabled: false) }
                    .accessibilityHint("Exits memory mode and returns to VFO")
            }

            // Current channel summary
            Group {
                if let ch = selectedChannel {
                    if ch.isEmpty {
                        Text("Channel \(String(format: "%03d", ch.id)): empty")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Channel \(String(format: "%03d", ch.id)): \(ch.frequencyMHz) MHz • \(ch.mode.label)\(ch.name.isEmpty ? "" : " • \"\(ch.name)\"")")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(radio.memoryChannels.isEmpty
                         ? "Press Load All to read memories from the radio."
                         : "Channel \(String(format: "%03d", selectedChannelID)): not loaded — press Load All or Recall to query.")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Channel info")

            Divider()

            // Editor
            Text("Edit Channel \(String(format: "%03d", selectedChannelID))")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Frequency (MHz):")
                TextField("e.g. 7.100000", text: $editFreqMHz)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .accessibilityLabel("Frequency in megahertz")
                Button("Use VFO A") {
                    if let hz = radio.vfoAFrequencyHz {
                        editFreqMHz = String(format: "%.6f", Double(hz) / 1_000_000.0)
                    }
                    if let m = radio.operatingMode { editMode = m }
                }
                .accessibilityHint("Fills frequency and mode from VFO A")
            }

            HStack(spacing: 12) {
                Text("Name (10 chars):")
                TextField("Up to 10", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: editName) { _, v in
                        if v.count > 10 { editName = String(v.prefix(10)) }
                    }
                    .accessibilityLabel("Channel name up to 10 characters")
            }

            HStack(spacing: 12) {
                Text("Mode:")
                Picker("Mode", selection: $editMode) {
                    ForEach(KenwoodCAT.OperatingMode.allCases, id: \.rawValue) { m in
                        Text(m.label).tag(m)
                    }
                }
                .frame(width: 160)
                .accessibilityLabel("Operating mode")
                Toggle("FM Narrow", isOn: $editFMNarrow)
                    .disabled(editMode != .fm)
            }

            HStack(spacing: 12) {
                Button("Save to Radio") { saveChannel(id: selectedChannelID) }
                    .accessibilityHint("Writes frequency, mode, and name to channel \(selectedChannelID)")
                Button("Revert") {
                    if let ch = selectedChannel { loadEditFields(from: ch) }
                }
                .disabled(selectedChannel == nil)
                .accessibilityHint("Restores editor to last received values")
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 340)
        .controlSize(.regular)
    }

    // Picker row label: "042  14.225000 MHz  USB  "DX Net""
    private func channelPickerLabel(_ i: Int) -> String {
        guard let ch = radio.memoryChannels.first(where: { $0.id == i }) else {
            return String(format: "%03d", i)
        }
        if ch.isEmpty { return String(format: "%03d  (empty)", i) }
        let namePart = ch.name.isEmpty ? "" : "  \"\(ch.name)\""
        return String(format: "%03d  %@ MHz  %@%@", i, ch.frequencyMHz, ch.mode.label, namePart)
    }

    private func loadEditFields(from ch: MemoryChannel) {
        editFreqMHz = ch.isEmpty ? "" : String(format: "%.6f", Double(ch.frequencyHz) / 1_000_000.0)
        editName = ch.name
        editMode = ch.mode
        editFMNarrow = false
    }

    private func saveChannel(id: Int) {
        let mhz = Double(editFreqMHz.replacingOccurrences(of: ",", with: ".")) ?? 0
        let hz  = Int((mhz * 1_000_000).rounded())
        radio.programMemoryChannel(channel: id, frequencyHz: hz,
                                   mode: editMode, fmNarrow: editFMNarrow, name: editName)
    }
}
