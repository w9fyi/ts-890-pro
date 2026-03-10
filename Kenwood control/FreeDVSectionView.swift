import SwiftUI

struct FreeDVSectionView: View {
    @Bindable var radio: RadioState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Mode & Path
                GroupBox("FreeDV Mode") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $radio.freedvMode) {
                            ForEach(FreeDVEngine.Mode.allCases) { mode in
                                Text("\(mode.label) — \(mode.details)").tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(radio.freedvIsActive)
                        .accessibilityLabel("FreeDV mode")
                        .accessibilityHint(radio.freedvIsActive ? "Deactivate FreeDV to change mode" : "Select FreeDV operating mode")

                        Picker("Audio path", selection: $radio.freedvAudioPath) {
                            ForEach(RadioState.FreeDVAudioPath.allCases, id: \.self) { path in
                                Text(path.rawValue).tag(path)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(radio.freedvIsActive)
                        .accessibilityLabel("FreeDV audio path")
                        .accessibilityHint(radio.freedvIsActive ? "Deactivate FreeDV to change audio path" : "LAN uses KNS network audio. USB uses the TS-890 USB Audio Codec.")
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - TX Callsign
                GroupBox("TX Text Channel") {
                    HStack {
                        Text("Callsign:")
                        TextField("Callsign", text: $radio.freedvTxCallsign)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                            .onChange(of: radio.freedvTxCallsign) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "freedv_callsign")
                            }
                        Text("(transmitted in text channel)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Activate / Deactivate
                GroupBox {
                    HStack(spacing: 16) {
                        if radio.freedvIsActive {
                            Button("Deactivate FreeDV") {
                                radio.deactivateFreeDV()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .accessibilityLabel("Deactivate FreeDV")
                            .accessibilityHint("Stops FreeDV mode and restores previous radio mode")
                        } else {
                            Button("Activate FreeDV") {
                                radio.activateFreeDV(mode: radio.freedvMode, audioPath: radio.freedvAudioPath)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(radio.connectionStatus != RadioState.ConnectionStatus.connected.rawValue)
                            .accessibilityLabel("Activate FreeDV")
                            .accessibilityHint("Switches radio to USB-DATA mode and starts FreeDV \(radio.freedvMode.label) on \(radio.freedvAudioPath.rawValue)")
                        }

                        if let err = radio.freedvError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                                .accessibilityLabel("FreeDV error: \(err)")
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - RX Status (shown when active)
                if radio.freedvIsActive {
                    GroupBox("RX Status") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 20) {
                                Label(
                                    radio.freedvSync ? "Sync" : "No Sync",
                                    systemImage: radio.freedvSync ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .foregroundColor(radio.freedvSync ? .green : .secondary)
                                .accessibilityLabel(radio.freedvSync ? "Synchronized" : "Not synchronized")

                                Text(String(format: "SNR %.1f dB", radio.freedvSnrDB))
                                    .monospacedDigit()
                                    .accessibilityLabel(String(format: "Signal to noise ratio %.1f decibels", radio.freedvSnrDB))

                                Text(String(format: "BER %.4f", radio.freedvBer))
                                    .monospacedDigit()
                                    .accessibilityLabel(String(format: "Bit error rate %.4f", radio.freedvBer))
                            }

                            if radio.freedvTotalBits > 0 {
                                Text("\(radio.freedvTotalBitErrors) errors / \(radio.freedvTotalBits) bits")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("\(radio.freedvTotalBitErrors) bit errors out of \(radio.freedvTotalBits) bits")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: - Received Text
                    GroupBox("Received Text") {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView {
                                Text(radio.freedvReceivedText.isEmpty ? "(none)" : radio.freedvReceivedText)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .accessibilityLabel(radio.freedvReceivedText.isEmpty
                                        ? "No text received"
                                        : "Received text: \(radio.freedvReceivedText)")
                            }
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)

                            HStack {
                                Spacer()
                                Button("Clear") {
                                    radio.freedvReceivedText = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Clear received text")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: - PTT hint
                    GroupBox("Transmit") {
                        Text("Use Option+Space to toggle PTT. When PTT is down, your microphone audio is encoded as FreeDV \(radio.freedvMode.label) and transmitted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Press Option Space to toggle push-to-talk. Your microphone is encoded as FreeDV \(radio.freedvMode.label) when transmitting.")
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("FreeDV")
    }
}
