//
//  EqualizerSectionView.swift
//  Kenwood control
//
//  18-band parametric EQ for the TS-890S.
//  TX bands controlled via UT command; RX bands via UR command.
//  Preset loading via EQT1n (TX) / EQR1n (RX).
//  18 linear bands: P1=0 Hz, P2=300 Hz … P18=5100 Hz (300 Hz steps).
//  Band value encoding: raw = 6 − dB  (raw 00=+6 dB, 06=0 dB, 30=−24 dB).
//

import SwiftUI

struct EqualizerSectionView: View {
    var radio: RadioState

    @State private var showingTX = true
    @State private var liveUpdate = false
    @State private var localBands: [Int] = Array(repeating: 0, count: 18)
    @State private var showFactoryWarning = false

    private var currentPreset: KenwoodCAT.EQPreset? {
        showingTX ? radio.txEQPreset : radio.rxEQPreset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // TX / RX selector
                Picker("EQ Channel", selection: $showingTX) {
                    Text("TX").tag(true)
                    Text("RX").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: showingTX) { _, _ in syncLocalBands() }

                // Preset
                HStack {
                    Text("Preset")
                        .font(.callout)
                    Spacer()
                    Menu(currentPreset?.label ?? "—") {
                        ForEach(KenwoodCAT.EQPreset.allCases) { preset in
                            Button(preset.label) { applyPreset(preset) }
                        }
                    }
                    .accessibilityLabel("EQ Preset: \(currentPreset?.label ?? "none")")
                }

                // Live update
                Toggle("Apply Changes Live", isOn: $liveUpdate)
                    .toggleStyle(.checkbox)
                    .accessibilityHint("When checked, every slider change is sent to the radio immediately")

                Divider()

                Text(showingTX ? "TX EQ Bands" : "RX EQ Bands")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(0..<18, id: \.self) { i in
                    EQBandRow(
                        label: KenwoodCAT.eqBandLabels[i],
                        value: Binding(
                            get: { localBands[i] },
                            set: { v in
                                localBands[i] = v
                                if liveUpdate { sendBands() }
                            }
                        )
                    )
                }

                Divider()

                Button("Save EQ to Radio") {
                    if let preset = currentPreset, preset.isFactory {
                        showFactoryWarning = true
                    } else {
                        sendBands()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Sends all 18 band values to the radio")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear {
            radio.queryAllEQ()
            syncLocalBands()
        }
        .onChange(of: radio.txEQBands) { _, _ in if showingTX { syncLocalBands() } }
        .onChange(of: radio.rxEQBands) { _, _ in if !showingTX { syncLocalBands() } }
        .confirmationDialog(
            "Overwrite Factory Preset?",
            isPresented: $showFactoryWarning,
            titleVisibility: .visible
        ) {
            Button("Save Anyway", role: .destructive) { sendBands() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The preset \(currentPreset?.label ?? "this preset") is a factory preset. The radio will use your custom values, but the factory preset remains unchanged in memory.")
        }
    }

    private func syncLocalBands() {
        localBands = showingTX ? radio.txEQBands : radio.rxEQBands
    }

    private func sendBands() {
        if showingTX {
            radio.setTXEQBands(localBands)
        } else {
            radio.setRXEQBands(localBands)
        }
    }

    private func applyPreset(_ preset: KenwoodCAT.EQPreset) {
        if showingTX {
            radio.loadTXEQPreset(preset)
        } else {
            radio.loadRXEQPreset(preset)
        }
    }
}

/// A single EQ band row: label, dB readout, and a −24…+6 dB slider.
private struct EQBandRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value >= 0 ? "+\(value) dB" : "\(value) dB")
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 64, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }
            ), in: -24...6, step: 1)
            .accessibilityLabel(label)
            .accessibilityValue(value >= 0 ? "plus \(value) decibels" : "minus \(abs(value)) decibels")
        }
    }
}
