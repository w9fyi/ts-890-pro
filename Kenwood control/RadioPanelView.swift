//
//  RadioPanelView.swift
//  Kenwood control
//
//  TS-890 Pro Radio Panel — ARCP-890 feature parity, VoiceOver-first.
//
//  Sections (front-panel order):
//    1. Meters (2×2 configurable analog gauge grid)
//    2. VFO / Tuning  (Cmd+F focuses VFO A)
//    3. Mode + Data Mode
//    4. Receive DSP (NB, Notch, BC, radio NR, AGC, ATT, PRE, SW NR)
//    5. RX Filter (Low Cut, High Cut, Shift)
//    6. Gains (RF, AF, SQL, Mic)
//    7. RIT / XIT
//    8. CW Controls (CW/CW-R modes only)
//    9. TX / VOX / Monitor
//   10. TX Modulation Sources (MS + DV)
//   11. Split Offset
//   12. EQ (DisclosureGroup)
//   13. Menu Settings (DisclosureGroup + link)
//   14. Memory (channel recall, program)
//

import SwiftUI
import Combine

// MARK: - Top-level panel

struct RadioPanelView: View {
    var radio: RadioState
    @Environment(\.openWindow) private var openWindow

    // Cmd+F → VFO A field focus
    @FocusState private var vfoAFocused: Bool

    // Local editable strings that mirror radio state
    @State private var freqAString: String = ""
    @State private var freqBString: String = ""
    @State private var memoryChannelString: String = "000"
    @State private var memoryProgramFreqString: String = "7.100"
    @State private var memoryProgramNameString: String = ""
    @State private var memoryProgramMode: KenwoodCAT.OperatingMode = .usb
    @State private var memoryProgramFMNarrow: Bool = false
    @State private var splitKHzString: String = "2"

    // Navigate to another sidebar section (Audio tab for NR detail)
    private func navigateToAudio() {
        NotificationCenter.default.post(
            name: KenwoodSelectSectionNotification,
            object: nil,
            userInfo: [KenwoodSelectSectionUserInfoKey: "audio"]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Hidden button captures Cmd+F globally and focuses VFO A field.
                Button("") { vfoAFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)

                Text("TS-890 Pro")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)

                // Section 1: Meters
                metersSection

                Divider()

                // Section 2: VFO / Tuning
                vfoSection

                Divider()

                // Section 3: Mode
                modeSection

                Divider()

                // Section 4: Receive DSP
                receiveDSPSection

                Divider()

                // Section 5: RX Filter
                rxFilterSection

                Divider()

                // Section 6: Gains
                gainsSection

                Divider()

                // Section 7: RIT / XIT
                ritXitSection

                // Section 8: CW Controls (conditional)
                if let mode = radio.operatingMode, (mode == .cw || mode == .cwR) {
                    Divider()
                    cwSection
                }

                Divider()

                // Section 9: TX / VOX / Monitor
                txSection

                Divider()

                // Section 10: TX Modulation Sources
                txModulationSection

                Divider()

                // Section 11: Split Offset
                splitOffsetSection

                Divider()

                // Section 12: EQ
                DisclosureGroup("Equalizer") {
                    eqSection
                        .padding(.top, 8)
                }
                .accessibilityLabel("Equalizer, expandable group")

                Divider()

                // Section 13: Menu Settings
                DisclosureGroup("Menu Settings") {
                    menuSettingsSection
                        .padding(.top, 8)
                }
                .accessibilityLabel("Menu settings, expandable group")

                Divider()

                // Section 14: Memory
                memorySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear { syncFromRadio() }
        .onChange(of: radio.vfoAFrequencyHz) { _, hz in
            if let hz { freqAString = hzToMHz(hz) }
        }
        .onChange(of: radio.vfoBFrequencyHz) { _, hz in
            if let hz { freqBString = hzToMHz(hz) }
        }
        .onChange(of: radio.memoryChannelNumber) { _, ch in
            if let ch { memoryChannelString = String(format: "%03d", ch) }
        }
        .onChange(of: radio.outputPowerWatts) { _, _ in }
    }

    private func syncFromRadio() {
        if let hz = radio.vfoAFrequencyHz { freqAString = hzToMHz(hz) }
        if let hz = radio.vfoBFrequencyHz { freqBString = hzToMHz(hz) }
        if let ch = radio.memoryChannelNumber { memoryChannelString = String(format: "%03d", ch) }
    }

    private func hzToMHz(_ hz: Int) -> String {
        String(format: "%.6f", Double(hz) / 1_000_000.0)
    }

    private func mhzStringToHz(_ s: String) -> Int {
        let clean = s.replacingOccurrences(of: ",", with: ".")
        let mhz = Double(clean) ?? 0
        return Int((mhz * 1_000_000).rounded())
    }
}

// MARK: - Section 1: Meters

extension RadioPanelView {
    var metersSection: some View {
        GroupBox("Meters") {
            ConfigurableMeterGrid(radio: radio)
                .padding(.top, 4)
        }
    }
}

// MARK: - Section 2: VFO / Tuning

extension RadioPanelView {
    var vfoSection: some View {
        GroupBox("VFO / Tuning") {
            VStack(alignment: .leading, spacing: 10) {

                // VFO A
                HStack(spacing: 8) {
                    Text("VFO A:")
                        .frame(width: 55, alignment: .trailing)
                    TextField("MHz", text: $freqAString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .focused($vfoAFocused)
                        .accessibilityLabel("VFO A frequency, in megahertz. Press Command F to focus here.")
                        .onSubmit { submitVFOA() }
                    Button("Set") { submitVFOA() }
                        .accessibilityLabel("Set VFO A frequency")
                }

                // VFO B
                HStack(spacing: 8) {
                    Text("VFO B:")
                        .frame(width: 55, alignment: .trailing)
                    TextField("MHz", text: $freqBString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityLabel("VFO B frequency, in megahertz")
                        .onSubmit { submitVFOB() }
                    Button("Set") { submitVFOB() }
                        .accessibilityLabel("Set VFO B frequency")
                }

                // Band + VFO ops
                HStack(spacing: 8) {
                    Button("Band ▼") { radio.bandStepDown() }
                        .accessibilityHint("Step band down")
                    Button("Band ▲") { radio.bandStepUp() }
                        .accessibilityHint("Step band up")
                    Button("A=B") {
                        radio.send("VV;")
                        radio.send(KenwoodCAT.getVFOBFrequency())
                    }
                    .accessibilityHint("Copy VFO A frequency to VFO B")
                    Button("A↔B") {
                        radio.send("EX;")   // TS-890 Exchange VFO = EX
                        radio.send(KenwoodCAT.getVFOAFrequency())
                        radio.send(KenwoodCAT.getVFOBFrequency())
                    }
                    .accessibilityHint("Swap VFO A and VFO B frequencies")
                    Button(radio.rxVFO != radio.txVFO ? "Split: ON" : "Split: OFF") {
                        radio.setSplitEnabled(!(radio.rxVFO != radio.txVFO))
                    }
                    .accessibilityLabel(radio.rxVFO != radio.txVFO ? "Split mode on" : "Split mode off")
                    .accessibilityHint("Toggle split operation (TX on VFO B)")
                }
            }
            .padding(.top, 4)
        }
    }

    private func submitVFOA() {
        radio.send(KenwoodCAT.setVFOAFrequencyHz(mhzStringToHz(freqAString)))
        radio.send(KenwoodCAT.getVFOAFrequency())
    }

    private func submitVFOB() {
        radio.setVFOBFrequencyHz(mhzStringToHz(freqBString))
    }
}

// MARK: - Section 3: Mode

extension RadioPanelView {
    var modeSection: some View {
        GroupBox("Mode") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(KenwoodCAT.OperatingMode.allCases, id: \.rawValue) { mode in
                        PanelModeButton(
                            label: mode.label,
                            isSelected: radio.operatingMode == mode
                        ) {
                            radio.send(KenwoodCAT.setOperatingMode(mode))
                            radio.send(KenwoodCAT.getOperatingMode(.left))
                        }
                    }
                }

                // Data mode toggle
                PanelToggleButton(
                    label: "DATA",
                    isOn: radio.dataModeEnabled ?? false,
                    onToggle: { radio.setDataMode(!( radio.dataModeEnabled ?? false)) }
                )
                .accessibilityHint("Toggles data mode (DATA-LSB, DATA-USB, etc. depending on current mode)")
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 4: Receive DSP

extension RadioPanelView {
    var receiveDSPSection: some View {
        GroupBox("Receive DSP") {
            VStack(alignment: .leading, spacing: 10) {

                // Row 1: NB, NB2, Notch, BC
                HStack(spacing: 8) {
                    PanelToggleButton(label: "NB", isOn: radio.noiseBlankerEnabled ?? false) {
                        radio.setNoiseBlankerEnabled(!(radio.noiseBlankerEnabled ?? false))
                    }
                    PanelToggleButton(label: "NB2", isOn: radio.noiseBlanker2Enabled ?? false) {
                        radio.setNoiseBlanker2Enabled(!(radio.noiseBlanker2Enabled ?? false))
                    }
                    .accessibilityHint("Noise blanker 2 on/off")
                    PanelToggleButton(label: "NOTCH", isOn: radio.isNotchEnabled ?? false) {
                        radio.setNotchEnabled(!(radio.isNotchEnabled ?? false))
                    }
                    PanelCycleButton(
                        label: "BC",
                        value: radio.beatCancelMode?.label ?? "---"
                    ) {
                        radio.cycleBeatCancelMode()
                    } contextItems: {
                        ForEach(KenwoodCAT.BeatCancelMode.allCases) { mode in
                            Button("BC: \(mode.label)") { radio.setBeatCancelMode(mode) }
                        }
                    }
                    .accessibilityHint("Beat cancel. Right-click or VO+Shift+M to jump to a value.")
                }

                // Row 2: Radio NR, AGC
                HStack(spacing: 8) {
                    PanelCycleButton(
                        label: "NR",
                        value: radio.transceiverNRMode?.label ?? "---"
                    ) {
                        radio.cycleTransceiverNRMode()
                    } contextItems: {
                        Button("NR: Off") { radio.setTransceiverNRMode(.off) }
                        Button("NR: NR1") { radio.setTransceiverNRMode(.nr1) }
                        Button("NR: NR2") { radio.setTransceiverNRMode(.nr2) }
                    }
                    .accessibilityHint("Radio DSP noise reduction. Right-click or VO+Shift+M to jump to a value.")

                    PanelCycleButton(
                        label: "AGC",
                        value: radio.agcMode?.label ?? "---"
                    ) {
                        radio.cycleAGCMode()
                    } contextItems: {
                        ForEach(KenwoodCAT.AGCMode.allCases) { mode in
                            Button("AGC: \(mode.label)") { radio.setAGCMode(mode) }
                        }
                    }
                    .accessibilityHint("Automatic gain control. Right-click or VO+Shift+M to jump to a value.")
                }

                // Row 3: ATT, PRE
                HStack(spacing: 8) {
                    PanelCycleButton(
                        label: "ATT",
                        value: radio.attenuatorLevel?.label ?? "---"
                    ) {
                        radio.cycleAttenuatorLevel()
                    } contextItems: {
                        ForEach(KenwoodCAT.AttenuatorLevel.allCases) { level in
                            Button("ATT: \(level.label)") { radio.setAttenuatorLevel(level) }
                        }
                    }
                    .accessibilityHint("RF attenuator. Right-click or VO+Shift+M to jump to a value.")

                    PanelCycleButton(
                        label: "PRE",
                        value: radio.preampLevel?.label ?? "---"
                    ) {
                        radio.cyclePreampLevel()
                    } contextItems: {
                        ForEach(KenwoodCAT.PreampLevel.allCases) { level in
                            Button("PRE: \(level.label)") { radio.setPreampLevel(level) }
                        }
                    }
                    .accessibilityHint("Preamplifier. Right-click or VO+Shift+M to jump to a value.")
                }

                // Row 4: Software NR quick-toggle
                HStack(spacing: 8) {
                    PanelToggleButton(
                        label: "SW NR",
                        isOn: radio.isNoiseReductionEnabled
                    ) {
                        radio.setNoiseReduction(enabled: !radio.isNoiseReductionEnabled)
                    }
                    .accessibilityHint("Software noise reduction (WDSP/RNNoise). Right-click to cycle backend or open Audio tab for full settings.")
                    .contextMenu {
                        Button("Cycle NR Backend") { radio.cycleNoiseReductionBackend() }
                        Divider()
                        Button("Configure in Audio Tab") { navigateToAudio() }
                    }

                    Text(radio.isNoiseReductionEnabled ? radio.noiseReductionBackend : "SW NR off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Software NR backend: \(radio.noiseReductionBackend)")
                }

                // Row 5: Notch frequency + bandwidth (when notch is on)
                if radio.isNotchEnabled == true {
                    SliderWithSteppers(
                        label: "Notch Freq",
                        value: Binding(
                            get: { Double(radio.notchFrequency ?? 128) },
                            set: { radio.setNotchFrequencyDebounced(Int($0)) }
                        ),
                        range: 0...255,
                        fineStep: 1,
                        coarseStep: 16,
                        displayFormat: { "\(Int($0))" },
                        accessibilityUnit: "raw position"
                    )

                    PanelCycleButton(
                        label: "Notch BW",
                        value: radio.notchBandwidth?.label ?? "---"
                    ) {
                        let bw = radio.notchBandwidth ?? .normal
                        let next = KenwoodCAT.NotchBandwidth(rawValue: (bw.rawValue + 1) % 3) ?? .normal
                        radio.setNotchBandwidth(next)
                    } contextItems: {
                        ForEach(KenwoodCAT.NotchBandwidth.allCases) { bw in
                            Button("Notch BW: \(bw.label)") { radio.setNotchBandwidth(bw) }
                        }
                    }
                    .accessibilityHint("Notch bandwidth. Right-click or VO+Shift+M to jump to a value.")
                }

                // Row 6: NR level parameters
                SliderWithSteppers(
                    label: "NR Level",
                    value: Binding(
                        get: { Double(radio.nrLevel ?? 5) },
                        set: { radio.setNRLevelDebounced(Int($0)) }
                    ),
                    range: 1...10,
                    fineStep: 1,
                    coarseStep: 3,
                    displayFormat: { "\(Int($0))" },
                    accessibilityUnit: "level"
                )

                SliderWithSteppers(
                    label: "NR2 Time",
                    value: Binding(
                        get: { Double(radio.nr2TimeConstant ?? 4) },
                        set: { radio.setNR2TimeConstantDebounced(Int($0)) }
                    ),
                    range: 0...9,
                    fineStep: 1,
                    coarseStep: 3,
                    displayFormat: { "\(Int($0))" },
                    accessibilityUnit: "time constant"
                )

                // Row 7: NB1 level
                SliderWithSteppers(
                    label: "NB1 Level",
                    value: Binding(
                        get: { Double(radio.noiseBlanker1Level ?? 10) },
                        set: { radio.setNoiseBlanker1LevelDebounced(Int($0)) }
                    ),
                    range: 1...20,
                    fineStep: 1,
                    coarseStep: 5,
                    displayFormat: { "\(Int($0))" },
                    accessibilityUnit: "level"
                )

                // Row 8: NB2 detail (when NB2 is on)
                if radio.noiseBlanker2Enabled == true {
                    DisclosureGroup("NB2 Settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            PanelCycleButton(
                                label: "NB2 Type",
                                value: radio.noiseBlanker2Type?.label ?? "---"
                            ) {
                                let t = radio.noiseBlanker2Type ?? .typeA
                                let next = KenwoodCAT.NoiseBlanker2Type(rawValue: (t.rawValue + 1) % 2) ?? .typeA
                                radio.setNoiseBlanker2Type(next)
                            } contextItems: {
                                ForEach(KenwoodCAT.NoiseBlanker2Type.allCases) { t in
                                    Button("NB2 Type: \(t.label)") { radio.setNoiseBlanker2Type(t) }
                                }
                            }
                            .accessibilityHint("NB2 type A or B. Right-click or VO+Shift+M to jump to a value.")

                            SliderWithSteppers(
                                label: "NB2 Level",
                                value: Binding(
                                    get: { Double(radio.noiseBlanker2Level ?? 5) },
                                    set: { radio.setNoiseBlanker2LevelDebounced(Int($0)) }
                                ),
                                range: 1...10,
                                fineStep: 1,
                                coarseStep: 3,
                                displayFormat: { "\(Int($0))" },
                                accessibilityUnit: "level"
                            )

                            SliderWithSteppers(
                                label: "NB2 Depth",
                                value: Binding(
                                    get: { Double(radio.noiseBlanker2Depth ?? 10) },
                                    set: { radio.setNoiseBlanker2DepthDebounced(Int($0)) }
                                ),
                                range: 1...20,
                                fineStep: 1,
                                coarseStep: 5,
                                displayFormat: { "\(Int($0))" },
                                accessibilityUnit: "depth"
                            )

                            SliderWithSteppers(
                                label: "NB2 Width",
                                value: Binding(
                                    get: { Double(radio.noiseBlanker2Width ?? 5) },
                                    set: { radio.setNoiseBlanker2WidthDebounced(Int($0)) }
                                ),
                                range: 1...20,
                                fineStep: 1,
                                coarseStep: 5,
                                displayFormat: { "\(Int($0))" },
                                accessibilityUnit: "width"
                            )
                        }
                        .padding(.top, 6)
                    }
                    .accessibilityLabel("N B 2 settings, expandable group")
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 5: RX Filter

extension RadioPanelView {
    var rxFilterSection: some View {
        GroupBox("RX Filter") {
            VStack(alignment: .leading, spacing: 10) {
                SliderWithSteppers(
                    label: "Low Cut",
                    value: Binding(
                        get: { Double(radio.rxFilterLowCutID ?? 0) },
                        set: { radio.setReceiveFilterLowCutID(Int($0)) }
                    ),
                    range: 0...35,
                    fineStep: 1,
                    coarseStep: 5,
                    displayFormat: { "ID \(Int($0))" },
                    accessibilityUnit: "setting ID"
                )

                SliderWithSteppers(
                    label: "High Cut",
                    value: Binding(
                        get: { Double(radio.rxFilterHighCutID ?? 0) },
                        set: { radio.setReceiveFilterHighCutID(Int($0)) }
                    ),
                    range: 0...27,
                    fineStep: 1,
                    coarseStep: 5,
                    displayFormat: { "ID \(Int($0))" },
                    accessibilityUnit: "setting ID"
                )

                SliderWithSteppers(
                    label: "Shift",
                    value: Binding(
                        get: { Double(radio.rxFilterShiftHz ?? 0) },
                        set: { v in
                            let hz = Int(v.rounded())
                            radio.send(KenwoodCAT.setReceiveFilterShiftHz(hz))
                            radio.send(KenwoodCAT.getReceiveFilterShift())
                        }
                    ),
                    range: -9999...9999,
                    fineStep: 10,
                    coarseStep: 100,
                    displayFormat: { "\(Int($0)) Hz" },
                    accessibilityUnit: "hertz"
                )
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 6: Gains

extension RadioPanelView {
    var gainsSection: some View {
        GroupBox("Gains") {
            VStack(alignment: .leading, spacing: 10) {
                SliderWithSteppers(
                    label: "RF Gain",
                    value: Binding(
                        get: { Double(radio.rfGain ?? 255) },
                        set: { v in
                            let clamped = max(0, min(Int(v), 255))
                            radio.send(KenwoodCAT.setRFGain(clamped))
                            radio.send(KenwoodCAT.getRFGain())
                        }
                    ),
                    range: 0...255,
                    fineStep: 5,
                    coarseStep: 20,
                    displayFormat: { String(Int($0)) },
                    accessibilityUnit: "level"
                )

                SliderWithSteppers(
                    label: "AF Gain",
                    value: Binding(
                        get: { Double(radio.afGain ?? 150) },
                        set: { v in
                            let clamped = max(0, min(Int(v), 255))
                            radio.send(KenwoodCAT.setAFGain(clamped))
                            radio.send(KenwoodCAT.getAFGain())
                        }
                    ),
                    range: 0...255,
                    fineStep: 5,
                    coarseStep: 20,
                    displayFormat: { String(Int($0)) },
                    accessibilityUnit: "level"
                )

                SliderWithSteppers(
                    label: "Squelch",
                    value: Binding(
                        get: { Double(radio.squelchLevel ?? 0) },
                        set: { v in
                            let clamped = max(0, min(Int(v), 255))
                            radio.send(KenwoodCAT.setSquelchLevel(clamped))
                            radio.send(KenwoodCAT.getSquelchLevel())
                        }
                    ),
                    range: 0...255,
                    fineStep: 5,
                    coarseStep: 20,
                    displayFormat: { String(Int($0)) },
                    accessibilityUnit: "level"
                )

                SliderWithSteppers(
                    label: "Mic Gain",
                    value: Binding(
                        get: { Double(radio.micGain ?? 50) },
                        set: { radio.setMicGainDebounced(Int($0)) }
                    ),
                    range: 0...100,
                    fineStep: 1,
                    coarseStep: 10,
                    displayFormat: { String(Int($0)) },
                    accessibilityUnit: "percent"
                )
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 7: RIT / XIT

extension RadioPanelView {
    var ritXitSection: some View {
        GroupBox("RIT / XIT") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PanelToggleButton(label: "RIT", isOn: radio.ritEnabled ?? false) {
                        radio.setRITEnabled(!(radio.ritEnabled ?? false))
                    }
                    PanelToggleButton(label: "XIT", isOn: radio.xitEnabled ?? false) {
                        radio.setXITEnabled(!(radio.xitEnabled ?? false))
                    }
                    Button("Clear") { radio.clearRitXitOffset() }
                        .accessibilityHint("Resets RIT and XIT offset to zero")
                }

                SliderWithSteppers(
                    label: "Offset",
                    value: Binding(
                        get: { Double(radio.ritXitOffsetHz ?? 0) },
                        set: { radio.setRitXitOffsetHz(Int($0.rounded())) }
                    ),
                    range: -9999...9999,
                    fineStep: 10,
                    coarseStep: 100,
                    displayFormat: { "\(Int($0)) Hz" },
                    accessibilityUnit: "hertz"
                )
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 8: CW Controls

extension RadioPanelView {
    var cwSection: some View {
        GroupBox("CW Controls") {
            VStack(alignment: .leading, spacing: 10) {
                SliderWithSteppers(
                    label: "Key Speed",
                    value: Binding(
                        get: { Double(radio.cwKeySpeedWPM ?? 20) },
                        set: { radio.setCWKeySpeedWPMDebounced(Int($0)) }
                    ),
                    range: 4...100,
                    fineStep: 1,
                    coarseStep: 5,
                    displayFormat: { "\(Int($0)) WPM" },
                    accessibilityUnit: "words per minute"
                )

                PanelCycleButton(
                    label: "Break-in",
                    value: radio.cwBreakInMode?.label ?? "---"
                ) {
                    radio.cycleCWBreakInMode()
                } contextItems: {
                    ForEach(KenwoodCAT.CWBreakInMode.allCases) { mode in
                        Button("Break-in: \(mode.label)") { radio.setCWBreakInMode(mode) }
                    }
                }
                .accessibilityHint("CW break-in mode. Right-click or VO+Shift+M to jump to a value.")

                HStack(spacing: 8) {
                    PanelToggleButton(label: "AUTO TUNE", isOn: radio.cwAutotuneActive ?? false) {
                        radio.setCWAutotuneActive(!(radio.cwAutotuneActive ?? false))
                    }
                    .accessibilityHint("CW autotune on/off")
                }

                SliderWithSteppers(
                    label: "CW Pitch",
                    value: Binding(
                        get: { Double(radio.cwPitchHz ?? 700) },
                        set: { radio.setCWPitchHzDebounced(Int($0)) }
                    ),
                    range: 300...1100,
                    fineStep: 5,
                    coarseStep: 50,
                    displayFormat: { "\(Int($0)) Hz" },
                    accessibilityUnit: "hertz"
                )

                SliderWithSteppers(
                    label: "Break-in Delay",
                    value: Binding(
                        get: { Double(radio.cwBreakInDelayMs ?? 200) },
                        set: { radio.setCWBreakInDelayMsDebounced(Int($0)) }
                    ),
                    range: 0...1000,
                    fineStep: 50,
                    coarseStep: 100,
                    displayFormat: { "\(Int($0)) ms" },
                    accessibilityUnit: "milliseconds"
                )
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 9: TX / VOX / Monitor

extension RadioPanelView {
    var txSection: some View {
        GroupBox("TX / VOX / Monitor") {
            VStack(alignment: .leading, spacing: 10) {

                SliderWithSteppers(
                    label: "TX Power",
                    value: Binding(
                        get: { Double(radio.outputPowerWatts ?? 100) },
                        set: { radio.setOutputPowerWattsDebounced(Int($0)) }
                    ),
                    range: 5...100,
                    fineStep: 1,
                    coarseStep: 10,
                    displayFormat: { "\(Int($0)) W" },
                    accessibilityUnit: "watts"
                )

                HStack(spacing: 8) {
                    PanelToggleButton(label: "PROC", isOn: radio.speechProcEnabled ?? false) {
                        radio.setSpeechProcEnabled(!(radio.speechProcEnabled ?? false))
                    }
                    .accessibilityHint("Speech processor on/off")

                    PanelToggleButton(label: "VOX", isOn: radio.voxEnabled ?? false) {
                        radio.setVOXEnabled(!(radio.voxEnabled ?? false))
                    }
                    .accessibilityHint("VOX (voice-operated transmit) on/off")

                    PanelToggleButton(label: "LOCK", isOn: radio.isLocked ?? false) {
                        radio.setLocked(!(radio.isLocked ?? false))
                    }
                    .accessibilityHint("Radio lock on/off")

                    PanelToggleButton(label: "MUTE", isOn: radio.isMuted ?? false) {
                        radio.setMuted(!(radio.isMuted ?? false))
                    }
                    .accessibilityHint("Audio mute on/off")

                    PanelToggleButton(label: "SPK", isOn: !(radio.isSpeakerMuted ?? false)) {
                        radio.setSpeakerMuted(!(radio.isSpeakerMuted ?? false))
                    }
                    .accessibilityHint("Speaker mute — lit when speaker is active")
                }

                // TX/RX/DSP Monitor toggles
                HStack(spacing: 8) {
                    PanelToggleButton(label: "TX MON", isOn: radio.txMonitorEnabled ?? false) {
                        radio.setTXMonitorEnabled(!(radio.txMonitorEnabled ?? false))
                    }
                    .accessibilityHint("TX monitor on/off")

                    PanelToggleButton(label: "RX MON", isOn: radio.rxMonitorEnabled ?? false) {
                        radio.setRXMonitorEnabled(!(radio.rxMonitorEnabled ?? false))
                    }
                    .accessibilityHint("RX monitor on/off")

                    PanelToggleButton(label: "DSP MON", isOn: radio.dspMonitorEnabled ?? false) {
                        radio.setDSPMonitorEnabled(!(radio.dspMonitorEnabled ?? false))
                    }
                    .accessibilityHint("DSP monitor on/off")
                }

                SliderWithSteppers(
                    label: "Monitor",
                    value: Binding(
                        get: { Double(radio.monitorLevel ?? 0) },
                        set: { radio.setMonitorLevelDebounced(Int($0)) }
                    ),
                    range: 0...100,
                    fineStep: 5,
                    coarseStep: 20,
                    displayFormat: { $0 == 0 ? "Off" : "\(Int($0))" },
                    accessibilityUnit: "level, zero means off"
                )

                // PTT
                HStack(spacing: 12) {
                    Button("PTT: TX") {
                        radio.setPTT(down: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityHint("Start transmitting. Hold and release, or tap again to stop.")

                    Button("PTT: RX") {
                        radio.setPTT(down: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityHint("Return to receive mode")
                }

                // ATU
                HStack(spacing: 8) {
                    PanelToggleButton(label: "ATU", isOn: radio.atuTxEnabled ?? false) {
                        radio.setATUTxEnabled(!(radio.atuTxEnabled ?? false))
                    }
                    .accessibilityHint("Antenna tuner on/off")

                    Button("Tune") {
                        radio.startATUTuning()
                    }
                    .disabled(radio.atuTuningActive ?? false)
                    .accessibilityHint("Starts antenna tuner matching sequence")

                    Button("Stop Tune") {
                        radio.stopATUTuning()
                    }
                    .disabled(!(radio.atuTuningActive ?? false))
                    .accessibilityHint("Stops antenna tuner matching sequence")

                    if radio.atuTuningActive == true {
                        ProgressView()
                            .scaleEffect(0.6)
                            .accessibilityLabel("Tuning in progress")
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 10: TX Modulation Sources

extension RadioPanelView {
    var txModulationSection: some View {
        GroupBox("TX Modulation Sources") {
            VStack(alignment: .leading, spacing: 10) {

                Text("Controls which audio inputs the radio uses for TX and data auto-keying.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                let frontOptions = [(0, "Off"), (1, "Mic")]
                let rearOptions  = [(0, "Off"), (1, "ACC 2"), (2, "USB Audio"), (3, "LAN")]

                // PTT / SEND keying row
                HStack(spacing: 8) {
                    Text("PTT keying:")
                        .frame(minWidth: 100, alignment: .leading)
                        .font(.callout)

                    Text("Front:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Menu(frontOptions.first(where: { $0.0 == (radio.msPttFront ?? 1) })?.1 ?? "—") {
                        ForEach(frontOptions, id: \.0) { v, label in
                            Button(label) {
                                radio.setTxModulationSource(
                                    txMeans: 0,
                                    front: v,
                                    rear: radio.msPttRear ?? 0
                                )
                            }
                        }
                    }
                    .accessibilityLabel("PTT keying front source: \(frontOptions.first(where: { $0.0 == (radio.msPttFront ?? 1) })?.1 ?? "unknown")")

                    Text("Rear:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Menu(rearOptions.first(where: { $0.0 == (radio.msPttRear ?? 0) })?.1 ?? "—") {
                        ForEach(rearOptions, id: \.0) { v, label in
                            Button(label) {
                                radio.setTxModulationSource(
                                    txMeans: 0,
                                    front: radio.msPttFront ?? 1,
                                    rear: v
                                )
                            }
                        }
                    }
                    .accessibilityLabel("PTT keying rear source: \(rearOptions.first(where: { $0.0 == (radio.msPttRear ?? 0) })?.1 ?? "unknown")")
                }

                // DATA SEND keying row
                HStack(spacing: 8) {
                    Text("DATA SEND:")
                        .frame(minWidth: 100, alignment: .leading)
                        .font(.callout)

                    Text("Front:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Menu(frontOptions.first(where: { $0.0 == (radio.msDataFront ?? 0) })?.1 ?? "—") {
                        ForEach(frontOptions, id: \.0) { v, label in
                            Button(label) {
                                radio.setTxModulationSource(
                                    txMeans: 1,
                                    front: v,
                                    rear: radio.msDataRear ?? 2
                                )
                            }
                        }
                    }
                    .accessibilityLabel("DATA SEND front source: \(frontOptions.first(where: { $0.0 == (radio.msDataFront ?? 0) })?.1 ?? "unknown")")

                    Text("Rear:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Menu(rearOptions.first(where: { $0.0 == (radio.msDataRear ?? 2) })?.1 ?? "—") {
                        ForEach(rearOptions, id: \.0) { v, label in
                            Button(label) {
                                radio.setTxModulationSource(
                                    txMeans: 1,
                                    front: radio.msDataFront ?? 0,
                                    rear: v
                                )
                            }
                        }
                    }
                    .accessibilityLabel("DATA SEND rear source: \(rearOptions.first(where: { $0.0 == (radio.msDataRear ?? 2) })?.1 ?? "unknown")")
                }

                Divider()

                // DATA Auto-TX (DV) — which input auto-keys TX in DATA mode
                HStack(spacing: 8) {
                    Text("DATA Auto-TX:")
                        .frame(minWidth: 100, alignment: .leading)
                        .font(.callout)
                    Menu(radio.dataVOXMode?.label ?? "—") {
                        ForEach(KenwoodCAT.DataVOXMode.allCases) { mode in
                            Button(mode.label) { radio.setDataVOXMode(mode) }
                        }
                    }
                    .accessibilityLabel("DATA auto-TX source: \(radio.dataVOXMode?.label ?? "unknown")")
                    Text("(auto-keys TX when audio present)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Section 11: Split Offset


extension RadioPanelView {
    var splitOffsetSection: some View {
        GroupBox("Split Offset") {
            HStack(spacing: 8) {
                Button("−") { setSplitOffset(plus: false) }
                    .accessibilityLabel("Split offset minus")
                Button("+") { setSplitOffset(plus: true) }
                    .accessibilityLabel("Split offset plus")
                TextField("kHz", text: $splitKHzString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .accessibilityLabel("Split offset in kilohertz, 1 to 9")
                Text("kHz")
            }
            .padding(.top, 4)
        }
    }

    private func setSplitOffset(plus: Bool) {
        let khz = max(1, min(Int(splitKHzString) ?? 2, 9))
        splitKHzString = String(khz)
        radio.setSplitOffset(plus: plus, khz: khz)
    }
}

// MARK: - Section 12: EQ

extension RadioPanelView {
    var eqSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eqPresetRow(label: "TX EQ", preset: radio.txEQPreset) { radio.loadTXEQPreset($0) }
            eqPresetRow(label: "RX EQ", preset: radio.rxEQPreset) { radio.loadRXEQPreset($0) }
            Text("Full 18-band editing available in the EQ tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func eqPresetRow(
        label: String,
        preset: KenwoodCAT.EQPreset?,
        onSelect: @escaping (KenwoodCAT.EQPreset) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            Menu(preset?.label ?? "—") {
                ForEach(KenwoodCAT.EQPreset.allCases) { p in
                    Button(p.label) { onSelect(p) }
                }
            }
            .accessibilityLabel("\(label): \(preset?.label ?? "none")")
        }
    }
}

// MARK: - Section 13: Menu Settings

extension RadioPanelView {
    var menuSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Common menu settings. Right-click for VO+Shift+M access on each.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // NB Level (EX menu — approximate; varies by firmware)
            menuStepperRow(label: "NB Level (0-10)", menuNum: 12, range: 0...10)
            menuStepperRow(label: "NB Width (0-10)", menuNum: 13, range: 0...10)
            menuStepperRow(label: "CW Pitch Hz", menuNum: 51, range: 400...1000)
            menuStepperRow(label: "CW Rise Time", menuNum: 52, range: 1...10)
            menuStepperRow(label: "Vox Delay (0-30)", menuNum: 23, range: 0...30)

            Divider()

            Button("All Settings in Menu Access →") {
                openWindow(id: "menuAccess")
            }
            .accessibilityHint("Opens the full Menu Access section with all EX menu items")
        }
    }

    private func menuStepperRow(label: String, menuNum: Int, range: ClosedRange<Int>) -> some View {
        let value = radio.exMenuValues[menuNum] ?? range.lowerBound
        return HStack(spacing: 8) {
            Text(label)
                .frame(minWidth: 180, alignment: .leading)
            Stepper(value: Binding(
                get: { value },
                set: { radio.writeMenuValue(menuNum, value: $0) }
            ), in: range) {
                Text(String(value))
                    .frame(width: 40, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .onAppear { radio.readMenuValue(menuNum) }
    }
}

// MARK: - Section 14: Memory

extension RadioPanelView {
    var memorySection: some View {
        GroupBox("Memory") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Toggle("Memory Mode", isOn: Binding(
                        get: { radio.isMemoryMode ?? false },
                        set: { radio.setMemoryMode(enabled: $0) }
                    ))
                    .accessibilityLabel("Memory channel mode")
                }

                HStack(spacing: 8) {
                    Text("Channel:")
                    TextField("000-119", text: $memoryChannelString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityLabel("Memory channel number, 0 to 119")
                        .onSubmit {
                            if let ch = Int(memoryChannelString.trimmingCharacters(in: .whitespaces)) {
                                radio.recallMemoryChannel(ch)
                            }
                        }
                    Stepper(value: Binding(
                        get: { Int(memoryChannelString) ?? (radio.memoryChannelNumber ?? 0) },
                        set: { v in
                            memoryChannelString = String(format: "%03d", v)
                            radio.recallMemoryChannel(v)
                        }
                    ), in: 0...119) {
                        Text(radio.memoryChannelNumber != nil
                             ? String(format: "%03d", radio.memoryChannelNumber!)
                             : "n/a")
                        .font(.system(.body, design: .monospaced))
                    }
                    Button("Recall") {
                        if let ch = Int(memoryChannelString.trimmingCharacters(in: .whitespaces)) {
                            radio.recallMemoryChannel(ch)
                        }
                    }
                }

                if let name = radio.memoryChannelName, !name.isEmpty {
                    Text("Name: \(name)  Freq: \(radio.memoryChannelFrequencyHz.map { hzToMHz($0) + " MHz" } ?? "?")  Mode: \(radio.memoryChannelMode?.label ?? "?")")
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityLabel("Channel name \(name), frequency \(radio.memoryChannelFrequencyHz.map { hzToMHz($0) + " megahertz" } ?? "unknown"), mode \(radio.memoryChannelMode?.label ?? "unknown")")
                }

                Divider()

                Text("Program Memory")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("Freq MHz:")
                    TextField("e.g. 7.100", text: $memoryProgramFreqString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .accessibilityLabel("Program frequency in megahertz")
                    Picker("Mode", selection: $memoryProgramMode) {
                        ForEach(KenwoodCAT.OperatingMode.allCases, id: \.rawValue) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .frame(width: 140)
                    Toggle("FM Narrow", isOn: $memoryProgramFMNarrow)
                        .disabled(memoryProgramMode != .fm)
                }

                HStack(spacing: 8) {
                    Text("Name:")
                    TextField("Up to 10 chars", text: $memoryProgramNameString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .accessibilityLabel("Memory channel name, up to 10 characters")
                }

                HStack(spacing: 8) {
                    Button("Program This Channel") {
                        let ch = Int(memoryChannelString.trimmingCharacters(in: .whitespaces)) ?? (radio.memoryChannelNumber ?? 0)
                        let hz = mhzStringToHz(memoryProgramFreqString)
                        radio.programMemoryChannel(channel: ch, frequencyHz: hz, mode: memoryProgramMode, fmNarrow: memoryProgramFMNarrow, name: memoryProgramNameString)
                    }
                    .accessibilityHint("Writes frequency, mode, and name into the selected memory channel")

                    Button("Use VFO A") {
                        if let hz = radio.vfoAFrequencyHz {
                            memoryProgramFreqString = hzToMHz(hz)
                        }
                        if let mode = radio.operatingMode {
                            memoryProgramMode = mode
                        }
                    }
                    .accessibilityHint("Copies current VFO A frequency and mode to the program fields")
                }

                Divider()

                // Scan controls
                HStack(spacing: 8) {
                    Button(radio.scanActive ? "Scanning…" : "Memory Scan") {
                        radio.startMemoryScan()
                    }
                    .accessibilityLabel("Start memory scan")
                    .accessibilityValue(radio.scanActive ? "Scanning" : "Stopped")

                    Button("Stop Scan") { radio.stopScan() }
                        .disabled(!radio.scanActive)
                        .accessibilityLabel("Stop scan")
                        .accessibilityValue(radio.scanActive ? "Active" : "Inactive")
                        .accessibilityHint("Only available while scan is running")
                }
                .onChange(of: radio.scanActive) { _, isActive in
                    NSAccessibility.post(element: NSApp as Any,
                                        notification: .announcementRequested,
                                        userInfo: [.announcement: isActive ? "Memory scan started" : "Memory scan stopped",
                                                   .priority: NSAccessibilityPriorityLevel.high.rawValue])
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Reusable: PanelModeButton

private struct PanelModeButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Mode \(label)\(isSelected ? ", selected" : "")")
    }
}

// MARK: - Reusable: PanelToggleButton

struct PanelToggleButton: View {
    let label: String
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text("\(label): \(isOn ? "ON" : "OFF")")
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(isOn ? "on" : "off")")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("Turn On")  { if !isOn { onToggle() } }
            Button("Turn Off") { if isOn { onToggle() } }
        }
    }
}

// MARK: - Reusable: PanelCycleButton

struct PanelCycleButton<Content: View>: View {
    let label: String
    let value: String
    let onCycle: () -> Void
    @ViewBuilder let contextItems: () -> Content

    var body: some View {
        Button(action: onCycle) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint("Tap to cycle to next value")
        .accessibilityAddTraits(.isButton)
        .contextMenu { contextItems() }
    }
}

// MARK: - Reusable: SliderWithSteppers

struct SliderWithSteppers: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fineStep: Double
    let coarseStep: Double
    let displayFormat: (Double) -> String
    let accessibilityUnit: String

    @State private var showAdjustSheet = false

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        fineStep: Double,
        coarseStep: Double,
        displayFormat: @escaping (Double) -> String,
        accessibilityUnit: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.fineStep = fineStep
        self.coarseStep = coarseStep
        self.displayFormat = displayFormat
        self.accessibilityUnit = accessibilityUnit
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .frame(minWidth: 80, alignment: .leading)
                    .font(.body)

                Slider(value: $value, in: range, step: fineStep)
                    .accessibilityLabel(label)
                    .accessibilityValue("\(displayFormat(value)) \(accessibilityUnit)")

                Button("▼") { step(by: -fineStep) }
                    .frame(width: 28)
                    .accessibilityLabel("\(label) decrease by \(displayFormat(fineStep))")

                Button("▲") { step(by: fineStep) }
                    .frame(width: 28)
                    .accessibilityLabel("\(label) increase by \(displayFormat(fineStep))")

                Text(displayFormat(value))
                    .frame(minWidth: 60, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityHidden(true)  // already on slider
            }
            .contextMenu {
                Button("Increase (\(displayFormat(coarseStep)))") { step(by: coarseStep) }
                Button("Decrease (\(displayFormat(coarseStep)))") { step(by: -coarseStep) }
                Divider()
                Button("Adjust Level\u{2026}") { showAdjustSheet = true }
            }
        }
        .sheet(isPresented: $showAdjustSheet) {
            LevelAdjustSheet(
                label: label,
                value: $value,
                range: range,
                fineStep: fineStep,
                displayFormat: displayFormat,
                accessibilityUnit: accessibilityUnit,
                isPresented: $showAdjustSheet
            )
        }
    }

    private func step(by delta: Double) {
        value = max(range.lowerBound, min(range.upperBound, value + delta))
    }
}

// MARK: - Reusable: LevelAdjustSheet

private struct LevelAdjustSheet: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fineStep: Double
    let displayFormat: (Double) -> String
    let accessibilityUnit: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(displayFormat(value))
                    .font(.system(.largeTitle, design: .monospaced))
                    .accessibilityLabel("\(label): \(displayFormat(value)) \(accessibilityUnit)")

                Slider(value: $value, in: range, step: fineStep)
                    .padding(.horizontal, 32)
                    .accessibilityLabel(label)
                    .accessibilityValue("\(displayFormat(value)) \(accessibilityUnit)")

                HStack(spacing: 24) {
                    Button("▼ \(displayFormat(fineStep))") {
                        value = max(range.lowerBound, value - fineStep)
                    }
                    .font(.title2)
                    .accessibilityLabel("Decrease \(label) by \(displayFormat(fineStep))")

                    Button("▲ \(displayFormat(fineStep))") {
                        value = min(range.upperBound, value + fineStep)
                    }
                    .font(.title2)
                    .accessibilityLabel("Increase \(label) by \(displayFormat(fineStep))")
                }
            }
            .padding(32)
            .navigationTitle(label)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Configurable Meter Grid

struct ConfigurableMeterGrid: View {
    var radio: RadioState
    private let meters = MeterStore.shared

    @AppStorage("Meter.slot0") private var slot0Raw: String = KenwoodCAT.MeterType.smeter.rawValue
    @AppStorage("Meter.slot1") private var slot1Raw: String = KenwoodCAT.MeterType.power.rawValue
    @AppStorage("Meter.slot2") private var slot2Raw: String = KenwoodCAT.MeterType.swr.rawValue
    @AppStorage("Meter.slot3") private var slot3Raw: String = KenwoodCAT.MeterType.alc.rawValue

    private var slot0: KenwoodCAT.MeterType { KenwoodCAT.MeterType(rawValue: slot0Raw) ?? .smeter }
    private var slot1: KenwoodCAT.MeterType { KenwoodCAT.MeterType(rawValue: slot1Raw) ?? .power }
    private var slot2: KenwoodCAT.MeterType { KenwoodCAT.MeterType(rawValue: slot2Raw) ?? .swr }
    private var slot3: KenwoodCAT.MeterType { KenwoodCAT.MeterType(rawValue: slot3Raw) ?? .alc }

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            AnalogMeterView(type: slot0, rawValue: meters.readings[slot0.smIndex] ?? 0) {
                slot0Raw = $0.rawValue
            }
            AnalogMeterView(type: slot1, rawValue: meters.readings[slot1.smIndex] ?? 0) {
                slot1Raw = $0.rawValue
            }
            AnalogMeterView(type: slot2, rawValue: meters.readings[slot2.smIndex] ?? 0) {
                slot2Raw = $0.rawValue
            }
            AnalogMeterView(type: slot3, rawValue: meters.readings[slot3.smIndex] ?? 0) {
                slot3Raw = $0.rawValue
            }
        }
        .onReceive(timer) { _ in
            let slots = [slot0, slot1, slot2, slot3]
            radio.pollMeters(slots)
        }
    }
}

// MARK: - Analog Meter View

struct AnalogMeterView: View {
    let type: KenwoodCAT.MeterType
    let rawValue: Double
    let onTypeChange: (KenwoodCAT.MeterType) -> Void

    private var normalized: Double {
        guard type.rawMax > 0 else { return 0 }
        return max(0, min(1, rawValue / type.rawMax))
    }

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                drawMeter(ctx: ctx, size: size, normalized: normalized)
            }
            .frame(height: 70)
            .accessibilityHidden(true)

            Text(type.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(type == .none_ ? "---" : type.formatValue(rawValue))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
        }
        .padding(8)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(type.label)
        .accessibilityValue(type == .none_ ? "off" : type.formatValue(rawValue))
        .contextMenu {
            ForEach(KenwoodCAT.MeterType.allCases) { t in
                Button(t.label) { onTypeChange(t) }
            }
        }
    }

    private func drawMeter(ctx: GraphicsContext, size: CGSize, normalized: Double) {
        let cx = size.width / 2
        let cy = size.height - 8
        let r = min(cx, cy) - 4

        // Background arc
        let startAngle: Double = 200  // degrees from +x axis (SwiftUI uses degrees)
        let endAngle: Double = 340
        var bg = Path()
        bg.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                  startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        ctx.stroke(bg, with: .color(.secondary.opacity(0.25)), lineWidth: 6)

        // Color zones: green 0-0.6, yellow 0.6-0.8, red 0.8-1.0
        let totalArc = endAngle - startAngle
        let zones: [(Double, Double, Color)] = [(0, 0.6, .green), (0.6, 0.8, .yellow), (0.8, 1.0, .red)]
        for (lo, hi, color) in zones {
            var arc = Path()
            arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: .degrees(startAngle + lo * totalArc),
                       endAngle: .degrees(startAngle + hi * totalArc),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color.opacity(0.5)), lineWidth: 6)
        }

        // Needle
        let needleAngle = startAngle + normalized * totalArc
        let rad = needleAngle * .pi / 180
        let nx = cx + r * 0.85 * cos(rad)
        let ny = cy + r * 0.85 * sin(rad)
        var needle = Path()
        needle.move(to: CGPoint(x: cx, y: cy))
        needle.addLine(to: CGPoint(x: nx, y: ny))
        ctx.stroke(needle, with: .color(.primary), lineWidth: 1.5)

        // Pivot dot
        ctx.fill(Circle().path(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)),
                 with: .color(.primary))
    }
}
