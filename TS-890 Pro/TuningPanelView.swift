//
//  TuningPanelView.swift
//  Kenwood control
//
//  Floating direct-entry + step-tuning panel — separate window (id: "tuning").
//  Opens with focus in the frequency entry field.
//  Accepts MHz (14.225) or kHz (14225).
//  Return commits frequency; Cmd+W or Escape closes.
//

import SwiftUI

struct TuningPanelView: View {
    var radio: RadioState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let steps: [(label: String, hz: Int)] = [
        ("1 Hz",    1),
        ("10 Hz",   10),
        ("100 Hz",  100),
        ("1 kHz",   1_000),
        ("10 kHz",  10_000),
        ("100 kHz", 100_000),
        ("1 MHz",   1_000_000),
    ]

    enum ActiveVFO: String, CaseIterable {
        case a = "A"
        case b = "B"
    }

    @State private var selectedStep: Int = 1_000
    @State private var freqEntry: String = ""
    @State private var activeVFO: ActiveVFO = .a
    @FocusState private var entryFocused: Bool
    @AccessibilityFocusState private var entryVOFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            // Header + VFO selector
            HStack {
                Text("Tuning Panel")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("VFO", selection: $activeVFO) {
                    ForEach(ActiveVFO.allCases, id: \.self) { v in
                        Text("VFO \(v.rawValue)").tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .accessibilityLabel("VFO to tune")
            }

            // Current frequency display
            Text(currentFreqDisplay)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundStyle(activeVFO == .a
                    ? Color.green
                    : Color(red: 0.6, green: 0.8, blue: 1.0))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(currentFreqAccessible)

            Divider()

            // Direct frequency entry — focused automatically on open
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter frequency (MHz or kHz), press Return to set:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 14.225 or 14225", text: $freqEntry)
                    .textFieldStyle(.roundedBorder)
                    .focused($entryFocused)
                    .accessibilityFocused($entryVOFocused)
                    .accessibilityLabel("Direct frequency entry")
                    .onSubmit { commitEntry() }
            }

            Divider()

            // Step size
            Picker("Step", selection: $selectedStep) {
                ForEach(steps, id: \.hz) { step in
                    Text(step.label).tag(step.hz)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tuning step size")

            // Up / Down buttons
            HStack(spacing: 32) {
                Button {
                    tune(by: -selectedStep)
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tune down \(stepLabel)")
                .keyboardShortcut(.downArrow, modifiers: [])

                Button {
                    tune(by: selectedStep)
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tune up \(stepLabel)")
                .keyboardShortcut(.upArrow, modifiers: [])
            }
        }
        .padding(16)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 260)
        .accessibilityHidden(scenePhase != .active)
        .onAppear {
            entryFocused = true
            entryVOFocused = true
        }
        // Escape and Cmd+W both close the window.
        .background(Group {
            Button("") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            Button("") { dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        })
    }

    // MARK: - Helpers

    private var currentFreqHz: Int? {
        activeVFO == .a ? radio.vfoAFrequencyHz : radio.vfoBFrequencyHz
    }

    private var currentFreqDisplay: String {
        guard let hz = currentFreqHz else { return "—" }
        return String(format: "%.6f MHz", Double(hz) / 1_000_000.0)
    }

    private var currentFreqAccessible: String {
        guard let hz = currentFreqHz else {
            return "VFO \(activeVFO.rawValue) frequency unknown"
        }
        let mhz = Double(hz) / 1_000_000.0
        let whole = Int(mhz)
        let frac = String(format: "%06d", Int((mhz - Double(whole)) * 1_000_000))
        return "VFO \(activeVFO.rawValue): \(whole) point \(frac) megahertz"
    }

    private var stepLabel: String {
        steps.first(where: { $0.hz == selectedStep })?.label ?? "\(selectedStep) Hz"
    }

    private func commitEntry() {
        let trimmed = freqEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return }
        // Has a decimal or is ≤ 30 → MHz; otherwise → kHz
        let hz: Int
        if trimmed.contains(".") || value <= 30 {
            hz = Int(value * 1_000_000)
        } else {
            hz = Int(value * 1_000)
        }
        guard hz > 0 else { return }
        radio.send(activeVFO == .a
            ? String(format: "FA%011d;", hz)
            : String(format: "FB%011d;", hz))
        radio.send(activeVFO == .a ? "FA;" : "FB;")
        freqEntry = ""
    }

    private func tune(by hz: Int) {
        if activeVFO == .a {
            guard let current = radio.vfoAFrequencyHz else { return }
            radio.send(String(format: "FA%011d;", max(0, current + hz)))
        } else {
            guard let current = radio.vfoBFrequencyHz else { return }
            radio.send(String(format: "FB%011d;", max(0, current + hz)))
        }
    }
}
