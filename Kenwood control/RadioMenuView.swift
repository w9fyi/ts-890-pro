//
//  RadioMenuView.swift
//  Kenwood control
//
//  EX extended menu browser for TS-890S.
//  Full menu list with group-by-section disclosure groups, plus
//  a discovery scan and freeform custom entry.
//

import SwiftUI

struct RadioMenuView: View {
    var radio: RadioState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum MenuMode: String, CaseIterable, Identifiable {
        case full = "Full Menu"
        case discovery = "Discover"

        var id: String { rawValue }
    }

    @State private var menuMode: MenuMode = .full
    @State private var fullSearchText: String = ""
    @State private var fullMenuWriteValues: [Int: String] = [:]
    @State private var expandedFullMenuGroups: Set<String> = []

    @State private var customMenuNumber: String = ""
    @State private var customMenuValue: String = ""

    private var filteredFullMenuItems: [TS890MenuItem] {
        if fullSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ts890MenuItems }
        let lower = fullSearchText.lowercased()
        return ts890MenuItems.filter {
            $0.displayLabel.lowercased().contains(lower) ||
            $0.detail.lowercased().contains(lower) ||
            String($0.number).contains(lower) ||
            $0.group.lowercased().contains(lower)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Menu Access (EX)")
                    .font(.title2)

                Text("Read and write TS-890S extended menu (EX) settings. Values are saved to the radio immediately when you press Write. Query first to see the current value.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("View", selection: $menuMode) {
                    ForEach(MenuMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                // Search + batch refresh — hidden in discovery mode
                if menuMode != .discovery {
                    HStack(spacing: 12) {
                        TextField("Search menu (label, number, group)", text: $fullSearchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)

                        Button("Refresh Visible") {
                            for n in filteredFullMenuItems.map({ $0.number }) {
                                radio.readMenuValue(n)
                            }
                        }
                        .help("Query the radio for the current value of the visible menu items.")
                    }
                }

                if menuMode == .full {
                    // Full menu list based on the TS-890 menu definitions
                    let grouped = Dictionary(grouping: filteredFullMenuItems, by: { $0.group })
                        .sorted(by: { $0.key < $1.key })

                    ForEach(grouped, id: \.key) { group, items in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedFullMenuGroups.contains(group) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedFullMenuGroups.insert(group)
                                } else {
                                    expandedFullMenuGroups.remove(group)
                                }
                            }
                        )) {
                            ForEach(items) { item in
                                FullMenuItemRow(item: item, radio: radio, writeValues: $fullMenuWriteValues)
                                Divider()
                            }
                        } label: {
                            Text(group)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    // ── Discovery scan ──────────────────────────────────────────────
                    GroupBox("EX Menu Discovery Scan") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Scans EX items 0–1100 and records which ones the radio responds to. Takes about 25 seconds. Connect to the radio first. Previous menu values are cleared before the scan starts.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if radio.menuDiscoveryRunning {
                                    Button("Stop") { radio.stopMenuDiscovery() }
                                        .foregroundStyle(.red)
                                } else {
                                    Button("Start Scan") { radio.startMenuDiscovery() }
                                        .buttonStyle(.borderedProminent)
                                }

                                if !radio.menuDiscoverySnapshot.isEmpty && !radio.menuDiscoveryRunning {
                                    Button("Copy Results") {
                                        let lookup: [Int: String] = Dictionary(
                                            ts890MenuItems.map { ($0.number, $0.displayLabel) },
                                            uniquingKeysWith: { f, _ in f }
                                        )
                                        let lines = radio.menuDiscoverySnapshot.map { item in
                                            let exCmd: String
                                            if item.number >= 10000 {
                                                exCmd = String(format: "EX100%02d", item.number - 10000)
                                            } else {
                                                exCmd = String(format: "EX0%02d%02d", item.number / 100, item.number % 100)
                                            }
                                            let label = lookup[item.number].map { "  [\($0)]" } ?? ""
                                            return "\(exCmd) \(String(format: "%03d", item.value))\(label)"
                                        }.joined(separator: "\n")
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(lines, forType: .string)
                                    }
                                    .accessibilityHint("Copies all \(radio.menuDiscoverySnapshot.count) discovered items to the clipboard as plain text")
                                }
                            }

                            if radio.menuDiscoveryRunning {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: radio.menuDiscoveryProgress)
                                    Text("\(Int(radio.menuDiscoveryProgress * 100))%  — sent \(radio.menuDiscoverySentCount) of \(radio.menuDiscoveryTotalCount) queries, \(radio.menuDiscoveryResponseCount) responses")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Discovery scan \(Int(radio.menuDiscoveryProgress * 100)) percent complete, \(radio.menuDiscoverySentCount) of \(radio.menuDiscoveryTotalCount) queries sent, \(radio.menuDiscoveryResponseCount) responses received")
                            }

                            // Show empty-result warning after a completed scan with no responses.
                            if !radio.menuDiscoveryRunning && radio.menuDiscoveryProgress == 1.0 && radio.menuDiscoverySnapshot.isEmpty {
                                Text("No responses received — check that the radio is connected and try again.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Warning: no EX responses received. Check radio connection.")
                            }

                            if !radio.menuDiscoverySnapshot.isEmpty {
                                let lookup: [Int: String] = Dictionary(
                                    ts890MenuItems.map { ($0.number, $0.displayLabel) },
                                    uniquingKeysWith: { f, _ in f }
                                )

                                Text("Found \(radio.menuDiscoverySnapshot.count) valid EX items")
                                    .font(.footnote)
                                    .fontWeight(.medium)

                                Divider()

                                ForEach(radio.menuDiscoverySnapshot, id: \.number) { item in
                                    HStack(spacing: 12) {
                                        let exCmd: String = item.number >= 10000
                                            ? String(format: "EX100%02d", item.number - 10000)
                                            : String(format: "EX0%02d%02d", item.number / 100, item.number % 100)
                                        Text(exCmd)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 80, alignment: .leading)
                                        Text("\(item.value)")
                                            .font(.system(.body, design: .monospaced))
                                            .frame(width: 50, alignment: .leading)
                                        if let label = lookup[item.number] {
                                            Text(label)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        } else {
                                            Text("(not in definitions)")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("EX \(item.number), value \(item.value)\(lookup[item.number].map { ", \($0)" } ?? ", unknown")")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // Custom / freeform entry
                GroupBox("Custom Menu Number") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter any EX menu number to read or write it directly.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Text("Menu #:")
                            TextField("000–999", text: $customMenuNumber)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .accessibilityLabel("Custom EX menu number")

                            Button("Read") {
                                if let n = Int(customMenuNumber) {
                                    radio.readMenuValue(n)
                                    if let v = radio.exMenuValues[n] {
                                        customMenuValue = String(v)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Text("Value:")
                            TextField("integer", text: $customMenuValue)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .accessibilityLabel("Custom EX menu value")

                            Button("Write") {
                                if let n = Int(customMenuNumber), let v = Int(customMenuValue) {
                                    radio.writeMenuValue(n, value: v)
                                }
                            }
                        }

                        if let n = Int(customMenuNumber), let v = radio.exMenuValues[n] {
                            Text("Last received: \(v)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(.top, 4)
                }
                .onChange(of: radio.exMenuValues) { _, _ in
                    if let n = Int(customMenuNumber), let v = radio.exMenuValues[n] {
                        customMenuValue = String(v)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .accessibilityHidden(scenePhase != .active)
        .background(
            Button("") { dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        )
    }
}

private struct FullMenuItemRow: View {
    let item: TS890MenuItem
    var radio: RadioState
    @Binding var writeValues: [Int: String]

    private var currentValue: Int? { radio.exMenuValues[item.number] }

    private var binding: Binding<String> {
        Binding(
            get: { writeValues[item.number] ?? "" },
            set: { writeValues[item.number] = $0 }
        )
    }

    private var displayTitle: String {
        let words = item.displayLabel.split(separator: " ")
        guard words.count > 6 else { return item.displayLabel }
        return words.prefix(6).joined(separator: " ") + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("EX\(String(format: "%03d", item.number))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Button("Read") {
                    radio.readMenuValue(item.number)
                    // Auto-populate write field once value arrives
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let v = radio.exMenuValues[item.number] {
                            writeValues[item.number] = String(v)
                        }
                    }
                }
                .font(.caption)

                TextField("Value", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .accessibilityLabel("Value for EX\(item.number)")

                Button("Write") {
                    if let v = Int(binding.wrappedValue) {
                        radio.writeMenuValue(item.number, value: v)
                    }
                }
                .font(.caption)
            }

            if let value = currentValue {
                Text("Last received: \(value)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
