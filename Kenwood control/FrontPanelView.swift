//
//  FrontPanelView.swift
//  Kenwood control
//
//  TS-Control-style compact front panel.
//  Layout (top → bottom):
//    1. DSP toolbar  — NB/NR/BC/ATT/PRE/AGC toggles + inline meter bars + Connect
//    2. Mode row     — Band ops, mode picker, data mode, VOX, speech proc
//    3. VFO row      — Large VFO A (left) and VFO B (right)
//    4. Controls row — RF/AF/SQL/Mic gains, filter Lo/Hi, RIT/XIT
//    5. TX row       — PTT, power, monitor, ATU
//    6. Meters row   — expandable 4-gauge analog meters
//    7. Scope        — spectrum + waterfall (fills remaining space)
//
//  Performance note: each numbered row is its own @Observable-tracked struct so
//  that SwiftUI only re-renders the row(s) whose RadioState properties actually
//  changed. e.g. a VFO frequency tick does not re-layout the DSP toolbar or
//  controls row.

import SwiftUI
import Combine
import AppKit

// MARK: - File-private static data shared across row structs

private let fpBands: [(label: String, defaultHz: Int)] = [
    ("160m", 1_800_000), ("80m",  3_500_000), ("60m",  5_330_500),
    ("40m",  7_000_000), ("30m", 10_100_000), ("20m", 14_000_000),
    ("17m", 18_068_000), ("15m", 21_000_000), ("12m", 24_890_000),
    ("10m", 28_000_000), ("6m",  50_000_000),
]

private let fpBandRanges: [(String, ClosedRange<Int>)] = [
    ("160m",  1_800_000...2_000_000), ("80m",  3_500_000...4_000_000),
    ("60m",   5_330_000...5_410_000), ("40m",  7_000_000...7_300_000),
    ("30m",  10_100_000...10_150_000), ("20m", 14_000_000...14_350_000),
    ("17m",  18_068_000...18_168_000), ("15m", 21_000_000...21_450_000),
    ("12m",  24_890_000...24_990_000), ("10m", 28_000_000...29_700_000),
    ("6m",   50_000_000...54_000_000),
]

private let fpSlSSB: [String] = [
    "0 Hz",    "50 Hz",   "100 Hz",  "200 Hz",  "300 Hz",  "400 Hz",  "500 Hz",
    "600 Hz",  "700 Hz",  "800 Hz",  "900 Hz",  "1000 Hz", "1100 Hz", "1200 Hz",
    "1300 Hz", "1400 Hz", "1500 Hz", "1600 Hz", "1700 Hz", "1800 Hz", "1900 Hz", "2000 Hz",
]
private let fpSlCW: [String] = [
    "50 Hz",  "80 Hz",  "100 Hz", "150 Hz", "200 Hz", "250 Hz", "300 Hz",
    "400 Hz", "500 Hz", "600 Hz", "700 Hz", "800 Hz", "900 Hz", "1000 Hz",
    "1200 Hz","1500 Hz","2000 Hz","2500 Hz","3000 Hz",
]
private let fpShSSB: [String] = [
    "600 Hz",  "700 Hz",  "800 Hz",  "900 Hz",  "1000 Hz", "1100 Hz", "1200 Hz",
    "1300 Hz", "1400 Hz", "1500 Hz", "1600 Hz", "1700 Hz", "1800 Hz", "1900 Hz",
    "2000 Hz", "2100 Hz", "2200 Hz", "2300 Hz", "2400 Hz", "2500 Hz", "2600 Hz",
    "2700 Hz", "2800 Hz", "2900 Hz", "3000 Hz", "3400 Hz", "4000 Hz", "5000 Hz",
]
private let fpTF1Labels: [String] = ["10 Hz", "100 Hz", "200 Hz", "300 Hz", "400 Hz", "500 Hz"]
private let fpTF2Labels: [String] = ["2500 Hz","2600 Hz","2700 Hz","2800 Hz","2900 Hz","3000 Hz","3500 Hz","4000 Hz"]

private func fpAnnounce(_ message: String) {
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [
            NSAccessibility.NotificationUserInfoKey.announcement: message,
            NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high,
        ]
    )
}

private func fpCurrentBandLabel(hz: Int) -> String? {
    fpBandRanges.first { $0.1.contains(hz) }?.0
}

// MARK: - FrontPanelView
//
// Body is intentionally lean — it accesses no RadioState properties directly.
// Every radio subscription is handled inside the individual row structs so that
// changes to one group of properties (e.g. VFO frequency) cannot trigger layout
// passes on unrelated rows (e.g. DSP toolbar, controls row).

struct FrontPanelView: View {
    var radio: RadioState
    @State private var waterfallEngine = WaterfallEngine()
    @State private var metersExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            DSPToolbarRow(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            if radio.isMemoryMode == true {
                Divider()
                MemoryModeBanner(radio: radio)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            Divider()

            ModeRow(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            Divider()

            VFORow(radio: radio)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            ControlsRow(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            Divider()

            TXRow(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            Divider()

            ClockSyncRow(radio: radio)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            Divider()

            MetersStripRow(expanded: $metersExpanded)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            if metersExpanded {
                Divider()
                MeterGridView()
                    .frame(height: 110)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            // ScopePanel isolates the high-frequency vfoAFrequencyHz and
            // scopeStore.points subscriptions away from FrontPanelView.body.
            ScopePanel(radio: radio, engine: waterfallEngine)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Memory mode banner

private struct MemoryModeBanner: View {
    let radio: RadioState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text("Memory Mode")
                .fontWeight(.medium)
            if let ch = radio.memoryChannelNumber {
                Text("CH \(String(format: "%03d", ch))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Return to VFO") { radio.setMemoryMode(enabled: false) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory mode active\(radio.memoryChannelNumber != nil ? ", channel \(radio.memoryChannelNumber!)" : "")")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Row 1: DSP toolbar
//
// Subscribes to: noiseBlankerEnabled, transceiverNRMode, beatCancelMode,
//   attenuatorLevel, preampLevel, agcMode, isNoiseReductionEnabled.
// ConnectButton is a separate struct so connectionStatus changes only
// re-render that button, not the DSP toggles.

private struct DSPToolbarRow: View {
    let radio: RadioState

    var body: some View {
        HStack(spacing: 4) {
            dspToggle("NB", value: radio.noiseBlankerEnabled ?? false) {
                radio.setNoiseBlankerEnabled(!($0))
            }
            NRButton(radio: radio)
            dspCycle("BC", label: radio.beatCancelMode?.label ?? "Off") {
                radio.cycleBeatCancelMode()
            }
            dspCycle("ATT", label: radio.attenuatorLevel?.label ?? "Off") {
                radio.cycleAttenuatorLevel()
            }
            dspCycle("PRE", label: radio.preampLevel?.label ?? "Off") {
                radio.cyclePreampLevel()
            }
            dspCycle("AGC", label: radio.agcMode?.label ?? "SLOW") {
                radio.cycleAGCMode()
            }
            FilterSlotButton(radio: radio)
            APFButton(radio: radio)

            Spacer()

            // Isolated subview — MeterStore ticks only re-render DSPMeterBars
            DSPMeterBars()

            Divider().frame(height: 18)

            // Isolated subview — connectionStatus changes only re-render ConnectButton
            ConnectButton(radio: radio)
        }
        .controlSize(.small)
    }

    private func dspToggle(_ label: String, value: Bool,
                           action: @escaping (Bool) -> Void) -> some View {
        Button(label) { action(value) }
            .buttonStyle(CompactButtonStyle(isActive: value))
            .accessibilityLabel(label)
            .accessibilityValue(value ? "On" : "Off")
            .contextMenu {
                Button("Turn On")  { if !value { action(value) } }
                Button("Turn Off") { if  value { action(value) } }
            }
    }

    private func dspCycle(_ label: String, label currentLabel: String,
                          action: @escaping () -> Void) -> some View {
        Button("\(label): \(currentLabel)") { action() }
            .buttonStyle(CompactButtonStyle(isActive: currentLabel != "Off"))
            .accessibilityLabel(label)
            .accessibilityValue(currentLabel)
    }
}

// MARK: - Unified NR button

/// Single front-panel NR button.
/// Left-click cycles the active path (hardware NR1→NR2→Off or software Off→ANR→EMNR→Off).
/// Right-click opens a persistent popover to switch between Hardware and Software mode
/// and to set the exact state directly.
private struct NRButton: View {
    let radio: RadioState
    @State private var showPopover = false

    var body: some View {
        Button(radio.nrButtonLabel) { radio.cycleNRFrontPanel() }
            .buttonStyle(CompactButtonStyle(isActive: radio.nrButtonIsActive))
            .accessibilityLabel("Noise Reduction")
            .accessibilityValue(radio.nrButtonLabel)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                NRPopoverContent(radio: radio)
                    .padding(12)
                    .frame(minWidth: 300)
            }
            .contextMenu {
                Button("NR Settings…") { showPopover = true }
            }
    }
}

private struct NRPopoverContent: View {
    let radio: RadioState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noise Reduction")
                .font(.headline)

            Picker("Mode", selection: Binding(
                get: { radio.nrButtonMode },
                set: { radio.nrButtonMode = $0 }
            )) {
                Text("Hardware").tag(RadioState.NRButtonMode.hardware)
                Text("Software").tag(RadioState.NRButtonMode.software)
            }
            .pickerStyle(.segmented)

            Divider()

            if radio.nrButtonMode == .hardware {
                Text("Hardware NR").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([KenwoodCAT.NoiseReductionMode.off,
                             KenwoodCAT.NoiseReductionMode.nr1,
                             KenwoodCAT.NoiseReductionMode.nr2], id: \.self) { mode in
                        Button(mode.label) { radio.setTransceiverNRMode(mode) }
                            .buttonStyle(CompactButtonStyle(
                                isActive: (radio.transceiverNRMode ?? .off) == mode))
                    }
                }
            } else {
                Text("Software NR").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(RadioState.SoftwareNRState.allCases, id: \.self) { state in
                        Button(state.rawValue) {
                            radio.softwareNRState = state
                            radio.setNoiseReduction(enabled: state != .off)
                            switch state {
                            case .cascade: radio.setNoiseReductionBackend("RNNoise + ANR")
                            case .anr:     radio.setNoiseReductionBackend("WDSP ANR")
                            case .emnr:    radio.setNoiseReductionBackend("WDSP EMNR")
                            case .off:     break
                            }
                        }
                        .buttonStyle(CompactButtonStyle(isActive: radio.softwareNRState == state))
                    }
                }

                if radio.isNoiseReductionEnabled {
                    HStack(spacing: 8) {
                        Text("Strength")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { radio.noiseReductionStrength },
                            set: { radio.setNoiseReductionStrength($0) }
                        ), in: 0...1, step: 0.05)
                        .frame(minWidth: 120)
                        .accessibilityLabel("Noise reduction strength")
                        .accessibilityValue("\(Int(radio.noiseReductionStrength * 100)) percent")
                        Text("\(Int(radio.noiseReductionStrength * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .controlSize(.small)
    }
}

// MARK: - Filter slot button

/// FIL button with popover for per-slot Hi/Lo-cut or IF-Shift control.
/// Left-click cycles A→B→C; right-click opens the settings popover.
private struct FilterSlotButton: View {
    let radio: RadioState
    @State private var showPopover = false

    var body: some View {
        let label = radio.filterSlot?.label ?? "A"
        Button("FIL: \(label)") { radio.cycleFilterSlot() }
            .buttonStyle(CompactButtonStyle(isActive: false))
            .accessibilityLabel("Filter Slot")
            .accessibilityValue(label)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                FilterSlotPopoverContent(radio: radio)
                    .padding(12)
                    .frame(minWidth: 280)
            }
            .contextMenu {
                Button("Filter Settings…") { showPopover = true }
            }
    }
}

private struct FilterSlotPopoverContent: View {
    let radio: RadioState

    private var isCWMode: Bool {
        guard let m = radio.operatingMode else { return false }
        return m == .cw || m == .cwR || m == .fsk
    }

    private var slotIndex: Int { (radio.filterSlot ?? .a).rawValue }

    private var currentDisplayMode: RadioState.FilterSlotDisplayMode {
        radio.filterSlotDisplayModes[slotIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Settings")
                .font(.headline)

            // Slot selector
            HStack(spacing: 6) {
                Text("Slot:").foregroundStyle(.secondary)
                ForEach(KenwoodCAT.FilterSlot.allCases) { slot in
                    Button(slot.label) { radio.setFilterSlot(slot) }
                        .buttonStyle(CompactButtonStyle(isActive: radio.filterSlot == slot))
                }
            }

            Divider()

            // Per-slot display mode toggle
            Picker("Mode", selection: Binding(
                get: { currentDisplayMode },
                set: {
                    var modes = radio.filterSlotDisplayModes
                    modes[slotIndex] = $0
                    radio.filterSlotDisplayModes = modes
                }
            )) {
                Text("Hi/Lo Cut").tag(RadioState.FilterSlotDisplayMode.hiLoCut)
                Text("IF Shift").tag(RadioState.FilterSlotDisplayMode.ifShift)
            }
            .pickerStyle(.segmented)

            Divider()

            if currentDisplayMode == .hiLoCut {
                // Lo-cut slider (index into SL table)
                let loMax = isCWMode ? 18 : 21
                let loLabels = isCWMode ? fpSlCW : fpSlSSB
                let loVal = radio.rxFilterLowCutID ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isCWMode ? "PBW (Lo)" : "Lo Cut")
                        Spacer()
                        Text(loLabels[safe: loVal] ?? "\(loVal) Hz")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(loVal) },
                        set: { radio.setReceiveFilterLowCutIDDebounced(Int($0)) }
                    ), in: 0...Double(loMax), step: 1)
                }

                // Hi-cut slider (index into SH table)
                let hiVal = radio.rxFilterHighCutID ?? 14
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hi Cut")
                        Spacer()
                        Text(fpShSSB[safe: hiVal] ?? "\(hiVal) Hz")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(hiVal) },
                        set: { radio.setReceiveFilterHighCutIDDebounced(Int($0)) }
                    ), in: 0...27, step: 1)
                }
            } else {
                // IF Shift slider — range depends on mode
                let isMax  = isCWMode ? 800.0  : 2500.0
                let isStep = isCWMode ? 10.0   : 50.0
                let isHz   = radio.rxFilterShiftHz ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("IF Shift")
                        Spacer()
                        Text(isHz >= 0 ? "+\(isHz) Hz" : "\(isHz) Hz")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(isHz) },
                        set: { newVal in
                            let stepped = Int((newVal / isStep).rounded()) * Int(isStep)
                            var shifts = radio.filterSlotIFShiftHz
                            shifts[slotIndex] = stepped
                            radio.filterSlotIFShiftHz = shifts
                            radio.setReceiveFilterShiftHzDebounced(stepped)
                        }
                    ), in: -isMax...isMax, step: isStep)
                }
                .onAppear {
                    // Sync radio IS to this slot's stored value when popover opens
                    let stored = radio.filterSlotIFShiftHz[slotIndex]
                    if (radio.rxFilterShiftHz ?? 0) != stored {
                        radio.setReceiveFilterShiftHzDebounced(stored)
                    }
                }
            }
        }
        .controlSize(.small)
    }
}

// MARK: - APF button

/// Toggle button for the CW Audio Peak Filter. Long-press / right-click opens a popover
/// to adjust shift, bandwidth, and gain.
private struct APFButton: View {
    let radio: RadioState
    @State private var showPopover = false

    var body: some View {
        Button(radio.apfEnabled == true ? "APF: ON" : "APF") {
            radio.setAPFEnabled(!(radio.apfEnabled ?? false))
        }
        .buttonStyle(CompactButtonStyle(isActive: radio.apfEnabled == true))
        .accessibilityLabel("Audio Peak Filter")
        .accessibilityValue(radio.apfEnabled == true ? "On" : "Off")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            APFPopoverContent(radio: radio)
                .padding(12)
                .frame(minWidth: 280)
        }
        .contextMenu {
            Button("APF Settings…") { showPopover = true }
        }
    }
}

private struct APFPopoverContent: View {
    let radio: RadioState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Peak Filter")
                .font(.headline)

            Toggle("APF On", isOn: Binding(
                get: { radio.apfEnabled ?? false },
                set: { radio.setAPFEnabled($0) }
            ))

            Divider()

            // Shift: 0–80, 40 = center (CW pitch). Display as Hz offset from center.
            let shiftVal = radio.apfShift ?? 40
            let shiftHz = (shiftVal - 40) * 5
            Text("Shift: \(shiftHz >= 0 ? "+" : "")\(shiftHz) Hz")
                .font(.subheadline)
            Slider(value: Binding(
                get: { Double(shiftVal) },
                set: { radio.setAPFShift(Int($0)) }
            ), in: 0...80, step: 1)
            .accessibilityLabel("APF shift")
            .accessibilityValue("\(shiftHz >= 0 ? "+" : "")\(shiftHz) Hz")

            Button("Reset to Center") { radio.send(KenwoodCAT.resetAPFShift()) }
                .buttonStyle(.borderless)
                .font(.subheadline)

            Divider()

            Picker("Bandwidth", selection: Binding(
                get: { radio.apfBandwidth ?? .mid },
                set: { radio.setAPFBandwidth($0) }
            )) {
                ForEach(KenwoodCAT.APFBandwidth.allCases) { bw in
                    Text(bw.label).tag(bw)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            let gainVal = radio.apfGain ?? 3
            Text("Gain: \(gainVal)")
                .font(.subheadline)
            Slider(value: Binding(
                get: { Double(gainVal) },
                set: { radio.setAPFGain(Int($0)) }
            ), in: 0...6, step: 1)
            .accessibilityLabel("APF gain")
            .accessibilityValue("\(gainVal)")
        }
        .controlSize(.small)
    }
}

/// Scan toggle. Right-click / long-press opens a popover to set speed, type, and tone scan.
private struct ScanButton: View {
    let radio: RadioState
    @State private var showPopover = false

    var body: some View {
        Button(radio.scanActive ? "SCAN: ON" : "SCAN") {
            if radio.scanActive { radio.stopScan() } else { radio.startMemoryScan() }
        }
        .buttonStyle(CompactButtonStyle(isActive: radio.scanActive))
        .accessibilityLabel("Memory scan")
        .accessibilityValue(radio.scanActive ? "On" : "Off")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ScanPopoverContent(radio: radio)
                .padding(12)
                .frame(minWidth: 240)
        }
        .contextMenu {
            Button("Scan Settings…") { showPopover = true }
        }
    }
}

private struct ScanPopoverContent: View {
    let radio: RadioState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan Settings")
                .font(.headline)

            // Speed: 1–9
            let speed = radio.scanSpeed ?? 5
            Text("Speed: \(speed)")
                .font(.subheadline)
            Slider(value: Binding(
                get: { Double(speed) },
                set: { radio.setScanSpeed(Int($0)) }
            ), in: 1...9, step: 1)
            .accessibilityLabel("Scan speed")
            .accessibilityValue("\(speed)")

            Divider()

            // Scan type: Program / VFO
            Picker("Scan type", selection: Binding(
                get: { radio.scanType ?? .program },
                set: { radio.setScanType($0) }
            )) {
                ForEach(KenwoodCAT.ScanType.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            // Tone scan (FM only)
            Picker("Tone scan", selection: Binding(
                get: { radio.toneScanMode ?? .off },
                set: { radio.setToneScanMode($0) }
            )) {
                ForEach(KenwoodCAT.ToneScanMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tone/CTCSS scan mode")
        }
        .controlSize(.small)
    }
}

// MARK: - Connect button
// Isolated so connectionStatus changes don't invalidate DSPToolbarRow's layout.

private struct ConnectButton: View {
    let radio: RadioState
    @State private var lastAnnounced: String = ""

    var body: some View {
        let isConnected  = radio.connectionStatus == "Connected"
        let isConnecting = radio.connectionStatus == "Connecting"
                        || radio.connectionStatus == "Authenticating"
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : (isConnecting ? Color.yellow : Color.red))
                .frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : (isConnecting ? "Connecting…" : "Disconnected"))
                .font(.system(size: 10))
                .foregroundColor(isConnected ? .green : (isConnecting ? .yellow : .secondary))
            if isConnected {
                Button("Disconnect") { radio.disconnect() }
                    .buttonStyle(CompactButtonStyle(tint: .red))
            } else if !isConnecting {
                Button("Connect") { radio.reconnect() }
                    .buttonStyle(CompactButtonStyle(tint: .green))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(radio.connectionStatus)")
        .onChange(of: radio.connectionStatus) { _, status in
            guard status != lastAnnounced else { return }
            lastAnnounced = status
            switch status {
            case "Connected":    fpAnnounce("Connected to radio")
            case "Disconnected": fpAnnounce("Disconnected from radio")
            default: break
            }
        }
    }
}

// MARK: - Row 2: Mode row
// Subscribes to: txVFO, operatingMode, dataModeEnabled, voxEnabled, speechProcEnabled.

private struct ModeRow: View {
    let radio: RadioState
    @State private var lastAnnouncedMode: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Button("A=B") { radio.send("VV;") }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Copy VFO A to B")
            Button("A↔B") { radio.send("EX;") }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Swap VFO A and B")
            Button("Split") {
                if radio.txVFO == .b { radio.send(KenwoodCAT.setTransmitterVFO(.a)) }
                else                 { radio.send(KenwoodCAT.setTransmitterVFO(.b)) }
            }
            .buttonStyle(CompactButtonStyle(isActive: radio.txVFO == .b))
            .accessibilityLabel("Split: transmit on VFO B")
            .accessibilityValue(radio.txVFO == .b ? "On" : "Off")

            Divider().frame(height: 18)

            Picker("", selection: Binding(
                get: { radio.operatingMode ?? .usb },
                set: { radio.send(KenwoodCAT.setOperatingMode($0)) }
            )) {
                Text("LSB").tag(KenwoodCAT.OperatingMode.lsb)
                Text("USB").tag(KenwoodCAT.OperatingMode.usb)
                Text("CW").tag(KenwoodCAT.OperatingMode.cw)
                Text("CW-R").tag(KenwoodCAT.OperatingMode.cwR)
                Text("AM").tag(KenwoodCAT.OperatingMode.am)
                Text("FM").tag(KenwoodCAT.OperatingMode.fm)
                Text("FSK").tag(KenwoodCAT.OperatingMode.fsk)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Operating mode")
            .frame(maxWidth: 340)

            Divider().frame(height: 18)

            Button(radio.dataModeEnabled == true ? "DATA: ON" : "DATA: OFF") {
                let next = !(radio.dataModeEnabled ?? false)
                radio.send(next ? "DA1;" : "DA0;")
                radio.send("DA;")
            }
            .buttonStyle(CompactButtonStyle(isActive: radio.dataModeEnabled == true))
            .accessibilityLabel("Data mode")
            .accessibilityValue(radio.dataModeEnabled == true ? "On" : "Off")

            Divider().frame(height: 18)

            Button("VOX") { radio.setVOXEnabled(!(radio.voxEnabled ?? false)) }
                .buttonStyle(CompactButtonStyle(isActive: radio.voxEnabled == true))
                .accessibilityLabel("VOX")
                .accessibilityValue(radio.voxEnabled == true ? "On" : "Off")

            Button("SP") { radio.setSpeechProcEnabled(!(radio.speechProcEnabled ?? false)) }
                .buttonStyle(CompactButtonStyle(isActive: radio.speechProcEnabled == true))
                .accessibilityLabel("Speech processor")
                .accessibilityValue(radio.speechProcEnabled == true ? "On" : "Off")

            ScanButton(radio: radio)

            Spacer()
        }
        .controlSize(.small)
        .onChange(of: radio.operatingMode) { _, mode in
            if let mode {
                let label = mode.label
                guard label != lastAnnouncedMode else { return }
                lastAnnouncedMode = label
                fpAnnounce("Mode: \(label)")
            }
        }
    }
}

// MARK: - Row 3: VFO row
// Subscribes to: vfoAFrequencyHz, vfoBFrequencyHz, isTransmitting.
// Owns all frequency-entry state so it never bleeds into other rows.

private struct VFORow: View {
    let radio: RadioState
    @State private var freqAString: String = ""
    @State private var freqBString: String = ""
    @FocusState private var vfoAFocused: Bool
    @State private var vfoADebounceTask: Task<Void, Never>? = nil
    @State private var vfoBDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        HStack(spacing: 16) {
            // VFO A
            VStack(alignment: .leading, spacing: 1) {
                Text("VFO A")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    bandMenu(vfo: "A", currentHz: radio.vfoAFrequencyHz)
                    Button("◀") { radio.bandStepDown() }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityLabel("Band down")
                    Button("▶") { radio.bandStepUp() }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityLabel("Band up")
                    TextField("", text: $freqAString)
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                        .foregroundColor(.green)
                        .focused($vfoAFocused)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 160)
                        .accessibilityLabel("VFO A frequency — click to edit")
                        .accessibilityValue(vfoAAccessibleValue)
                        .onSubmit { commitFreqA() }
                    Button("Set") { commitFreqA() }
                        .buttonStyle(CompactButtonStyle())
                }
            }

            Divider()

            // VFO B
            VStack(alignment: .leading, spacing: 1) {
                Text("VFO B")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    bandMenu(vfo: "B", currentHz: radio.vfoBFrequencyHz)
                    TextField("", text: $freqBString)
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                        .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 160)
                        .accessibilityLabel("VFO B frequency — click to edit")
                        .accessibilityValue(vfoBAccessibleValue)
                        .onSubmit { commitFreqB() }
                    Button("Set") { commitFreqB() }
                        .buttonStyle(CompactButtonStyle())
                }
            }

            Spacer()

            // RX/TX indicator
            VStack(spacing: 2) {
                Circle()
                    .fill(radio.isTransmitting == true ? Color.red : Color(white: 0.2))
                    .frame(width: 14, height: 14)
                    .accessibilityLabel(radio.isTransmitting == true ? "Transmitting" : "Receiving")
                Text(radio.isTransmitting == true ? "TX" : "RX")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(radio.isTransmitting == true ? .red : .secondary)
            }
        }
        // Cmd+F focuses VFO A — placed here so the shortcut lives with the field
        .background(
            Button("") { vfoAFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        )
        .onAppear { syncFreqFields() }
        .onChange(of: radio.vfoAFrequencyHz) { _, hz in
            guard let hz else { return }
            freqAString = hzToMHz(hz)
            vfoADebounceTask?.cancel()
            vfoADebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let band = fpCurrentBandLabel(hz: hz) {
                    UserDefaults.standard.set(hz, forKey: "bandFreq_A_\(band)")
                }
            }
        }
        .onChange(of: radio.vfoBFrequencyHz) { _, hz in
            guard let hz else { return }
            freqBString = hzToMHz(hz)
            vfoBDebounceTask?.cancel()
            vfoBDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let band = fpCurrentBandLabel(hz: hz) {
                    UserDefaults.standard.set(hz, forKey: "bandFreq_B_\(band)")
                }
            }
        }
    }

    // MARK: Helpers

    private func syncFreqFields() {
        if let hz = radio.vfoAFrequencyHz { freqAString = hzToMHz(hz) }
        if let hz = radio.vfoBFrequencyHz { freqBString = hzToMHz(hz) }
    }

    private func commitFreqA() {
        if let mhz = Double(freqAString) {
            radio.send(KenwoodCAT.setVFOAFrequencyHz(Int(mhz * 1_000_000)))
        }
    }

    private func commitFreqB() {
        if let mhz = Double(freqBString) {
            radio.send(KenwoodCAT.setVFOBFrequencyHz(Int(mhz * 1_000_000)))
        }
    }

    private func hzToMHz(_ hz: Int) -> String {
        String(format: "%.6f", Double(hz) / 1_000_000.0)
    }

    private var vfoAAccessibleValue: String {
        guard let hz = radio.vfoAFrequencyHz else { return "Unknown" }
        return accessibleFrequency(hz)
    }

    private var vfoBAccessibleValue: String {
        guard let hz = radio.vfoBFrequencyHz else { return "Unknown" }
        return accessibleFrequency(hz)
    }

    private func accessibleFrequency(_ hz: Int) -> String {
        let mhz   = Double(hz) / 1_000_000.0
        let whole = Int(mhz)
        let frac  = Int((mhz - Double(whole)) * 1000)
        return "\(whole) point \(String(format: "%03d", frac)) megahertz"
    }

    private func switchBand(label: String, defaultHz: Int, vfo: String, currentHz: Int?) {
        if let hz = currentHz, let band = fpCurrentBandLabel(hz: hz) {
            UserDefaults.standard.set(hz, forKey: "bandFreq_\(vfo)_\(band)")
        }
        let stored   = UserDefaults.standard.integer(forKey: "bandFreq_\(vfo)_\(label)")
        let targetHz = stored > 0 ? stored : defaultHz
        radio.send(vfo == "A"
            ? String(format: "FA%011d;", targetHz)
            : String(format: "FB%011d;", targetHz))
        fpAnnounce("VFO \(vfo): \(label)")
    }

    private func bandMenu(vfo: String, currentHz: Int?) -> some View {
        Menu("Band") {
            ForEach(fpBands, id: \.label) { band in
                Button(band.label) {
                    switchBand(label: band.label, defaultHz: band.defaultHz,
                               vfo: vfo, currentHz: currentHz)
                }
            }
        }
        .controlSize(.small)
        .accessibilityLabel("Select band for VFO \(vfo)")
    }
}

// MARK: - Row 4: Controls row
// Subscribes to: rfGain, afGain, squelchLevel, micGain, operatingMode,
//   ritEnabled, xitEnabled, ritXitOffsetHz.
// Each KnobButton manages its own level-adjust sheet — no shared state needed.

private struct ControlsRow: View {
    let radio: RadioState

    var body: some View {
        // VStack so CWKeyerRow can appear below without FrontPanelView.body
        // reading operatingMode directly (ControlsRow already owns that subscription).
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                KnobButton(label: "RF",  value: radio.rfGain,       range: 0...255) { radio.setRFGainDebounced($0)    }
                KnobButton(label: "AF",  value: radio.afGain,       range: 0...255) { radio.setAFGainDebounced($0)    }
                KnobButton(label: "SQL", value: radio.squelchLevel, range: 0...255) { radio.setSquelchLevelDebounced($0) }
                KnobButton(label: "Mic", value: radio.micGain,      range: 0...100) { radio.setMicGainDebounced($0)   }

                Divider().frame(height: 18)

                ritXitControl
            }

            // CW keyer messages and break-in — visible when in CW or CW-R (not FSK)
            if radio.operatingMode == .cw || radio.operatingMode == .cwR {
                Divider().padding(.vertical, 1)
                HStack(spacing: 8) {
                    CWKeyerRow(radio: radio)
                    Divider().frame(height: 18)
                    Button("BK: \(radio.cwBreakInMode?.label ?? "---")") {
                        radio.cycleCWBreakInMode()
                    }
                    .buttonStyle(CompactButtonStyle(isActive: radio.cwBreakInMode == .on))
                    .accessibilityLabel("CW break-in mode")
                    .accessibilityValue(radio.cwBreakInMode?.label ?? "unknown")
                    .accessibilityHint("Tap to cycle: Off, Semi, Full")
                    .contextMenu {
                        ForEach(KenwoodCAT.CWBreakInMode.allCases) { mode in
                            Button("Break-in: \(mode.label)") { radio.setCWBreakInMode(mode) }
                        }
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private var ritXitControl: some View {
        HStack(spacing: 4) {
            Button(radio.ritEnabled == true ? "RIT: ON" : "RIT") {
                radio.setRITEnabled(!(radio.ritEnabled ?? false))
            }
            .buttonStyle(CompactButtonStyle(isActive: radio.ritEnabled == true))
            .accessibilityLabel("RIT")
            .accessibilityValue(radio.ritEnabled == true ? "On" : "Off")

            Button(radio.xitEnabled == true ? "XIT: ON" : "XIT") {
                radio.setXITEnabled(!(radio.xitEnabled ?? false))
            }
            .buttonStyle(CompactButtonStyle(isActive: radio.xitEnabled == true))
            .accessibilityLabel("XIT")
            .accessibilityValue(radio.xitEnabled == true ? "On" : "Off")

            let offsetText = radio.ritXitOffsetHz.map { "\($0) Hz" } ?? "0 Hz"
            Text(offsetText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
                .accessibilityLabel("RIT XIT offset")
                .accessibilityValue(offsetText)

            Button("CLR") { radio.clearRitXitOffset() }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Clear RIT and XIT offset")
        }
    }
}

// MARK: - CW Keyer Messages (M1–M4)
// Visible when operating mode is CW or CW-R.
// Messages stored in UserDefaults. Sent via KY command (24-char max per slot).

private struct CWKeyerRow: View {
    let radio: RadioState
    @AppStorage("CW.M1") private var m1: String = ""
    @AppStorage("CW.M2") private var m2: String = ""
    @AppStorage("CW.M3") private var m3: String = ""
    @AppStorage("CW.M4") private var m4: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Text("Keyer:").font(.system(size: 10)).foregroundStyle(.secondary)

            ForEach(Array(zip(["M1","M2","M3","M4"], [binding($m1), binding($m2), binding($m3), binding($m4)])), id: \.0) { label, msg in
                HStack(spacing: 2) {
                    TextField(label, text: msg)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("CW keyer \(label) message")
                        .accessibilityHint("Up to 24 characters. Radio sends as CW when you press Send.")
                        .onChange(of: msg.wrappedValue) { _, v in
                            // cap at 24 chars in real time
                            if v.count > 24 { msg.wrappedValue = String(v.prefix(24)) }
                        }
                    Button("Send") { radio.sendCWKeyer(text: msg.wrappedValue) }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityLabel("Send keyer \(label)")
                        .accessibilityHint(msg.wrappedValue.isEmpty ? "No message stored" : "Sends: \(msg.wrappedValue)")
                        .help("Send \(label): \(msg.wrappedValue)")
                }
                // Group field + button as one logical unit for VoiceOver
                .accessibilityElement(children: .contain)
                .accessibilityLabel("CW keyer \(label)")
            }

            Button("Stop") { radio.stopCWKeyer() }
                .buttonStyle(CompactButtonStyle(isActive: false, tint: .orange))
                .accessibilityLabel("Stop CW keyer")
                .accessibilityHint("Stops the radio keyer immediately")
        }
        .controlSize(.small)
        // Announce row availability when mode switches to CW
        .onAppear { fpAnnounce("CW keyer controls available") }
    }

    // Bridge @AppStorage to Binding<String> for ForEach
    private func binding(_ storage: Binding<String>) -> Binding<String> { storage }
}

// MARK: - Row 5: TX row
// Subscribes to: isTransmitting, outputPowerWatts, monitorLevel,
//   txFilterLowCutID, txFilterHighCutID, atuTxEnabled, atuTuningActive.

private struct TXRow: View {
    let radio: RadioState
    @State private var showAudioSettings = false

    var body: some View {
        HStack(spacing: 6) {
            Button("PTT: TX") { radio.setPTT(down: true) }
                .buttonStyle(CompactButtonStyle(isActive: radio.isTransmitting == true, tint: .red))
                .accessibilityLabel("Push to talk, transmit")

            Button("PTT: RX") { radio.setPTT(down: false) }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Push to talk, receive")

            Divider().frame(height: 18)

            KnobButton(label: "Power", value: radio.outputPowerWatts, range: 5...100) {
                radio.send(KenwoodCAT.setOutputPowerWatts($0))
            }
            KnobButton(label: "Mon", value: radio.monitorLevel, range: 0...20) {
                radio.setMonitorLevelDebounced($0)
            }
            KnobButton(label: "TF Lo", value: radio.txFilterLowCutID, range: 0...5,
                       valueLabel: { fpTF1Labels[safe: $0] ?? "\($0)" }) {
                radio.send("TF1\($0);")
            }
            KnobButton(label: "TF Hi", value: radio.txFilterHighCutID, range: 0...7,
                       valueLabel: { fpTF2Labels[safe: $0] ?? "\($0)" }) {
                radio.send("TF2\($0);")
            }

            Divider().frame(height: 18)

            Button("ATU") {
                radio.send(KenwoodCAT.setAntennaTuner(txEnabled: !(radio.atuTxEnabled ?? false)))
            }
            .buttonStyle(CompactButtonStyle(isActive: radio.atuTxEnabled == true))
            .accessibilityLabel("Antenna tuner")
            .accessibilityValue(radio.atuTxEnabled == true ? "On" : "Off")

            Button("Tune") { radio.send("AC111;") }
                .buttonStyle(CompactButtonStyle(isActive: radio.atuTuningActive == true))
                .accessibilityLabel("Start ATU tuning")

            Button("Stop") { radio.send("AC110;") }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Stop ATU tuning")

            Divider().frame(height: 18)

            Button("ANT: \(radio.antennaPort == 2 ? "2" : "1")") { radio.cycleAntennaPort() }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Antenna port")
                .accessibilityValue("ANT \(radio.antennaPort == 2 ? "2" : "1")")

            Spacer()

            Button("Operator Audio Settings") { showAudioSettings = true }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Operator Audio Settings")
                .accessibilityHint("Opens the audio routing panel to select TX and RX audio devices")

            Button("QM Store")  { radio.send("QM1;") }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Store quick memory")
            Button("QM Recall") { radio.send("QM0;") }
                .buttonStyle(CompactButtonStyle())
                .accessibilityLabel("Recall quick memory")
            MemoriesButton(radio: radio)
        }
        .controlSize(.small)
        .sheet(isPresented: $showAudioSettings) {
            AudioSectionView(radio: radio)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}

// MARK: - Memories button

/// Memories button in TXRow.
/// Left-click opens the MemoryBrowserView sheet.
/// Right-click opens a persistent popover to quick-store VFO A to a configurable channel.
private struct MemoriesButton: View {
    let radio: RadioState
    @State private var showSheet         = false
    @State private var showQuickPopover  = false
    @AppStorage("quickStoreChannel") private var quickStoreChannel: Int = 0

    var body: some View {
        Button("Memories") { showSheet = true }
            .buttonStyle(CompactButtonStyle())
            .accessibilityLabel("Memory channel browser")
            .accessibilityHint("Opens memory browser. Right-click to quick-store VFO A.")
            .sheet(isPresented: $showSheet) {
                MemoryBrowserView(radio: radio)
            }
            .popover(isPresented: $showQuickPopover, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Store").font(.headline)
                    HStack(spacing: 8) {
                        Text("Channel:")
                        Stepper(value: $quickStoreChannel, in: 0...119) {
                            Text(String(format: "%03d", quickStoreChannel))
                                .font(.system(.body, design: .monospaced))
                        }
                        .accessibilityLabel("Quick store channel \(quickStoreChannel)")
                    }
                    Button("Store VFO A → Ch \(String(format: "%03d", quickStoreChannel))") {
                        guard let hz   = radio.vfoAFrequencyHz,
                              let mode = radio.operatingMode else { return }
                        radio.programMemoryChannel(channel: quickStoreChannel,
                                                   frequencyHz: hz,
                                                   mode: mode,
                                                   fmNarrow: false,
                                                   name: "")
                        showQuickPopover = false
                    }
                    .disabled(radio.vfoAFrequencyHz == nil)
                    .accessibilityHint("Stores current VFO A frequency to channel \(quickStoreChannel)")
                }
                .padding(12)
                .frame(minWidth: 220)
                .controlSize(.small)
            }
            .contextMenu {
                Button("Quick Store VFO A…") { showQuickPopover = true }
                Button("Browse Memories…")   { showSheet = true }
            }
    }
}

// MARK: - Clock sync row

/// Dedicated row for syncing the radio clock from NTP.
/// Left-click syncs immediately using the stored server and timezone.
/// Right-click opens a persistent popover to change the NTP server and clock timezone.
private struct ClockSyncRow: View {
    let radio: RadioState

    @AppStorage("ntpServer")         private var ntpServer:         String = NTPClient.defaultServer
    @AppStorage("clockTimezoneID")   private var clockTimezoneID:   String = "UTC"
    @AppStorage("radioManagesNTP")   private var radioManagesNTP:   Bool   = false
    @State private var showPopover        = false
    @State private var statusMessage      = ""
    @State private var isSyncing          = false
    @State private var editServer         = ""
    @State private var editTimezoneID     = ""
    @State private var editRadioManagesNTP = false

    // Curated timezone list for the picker.
    // "System" resolves to TimeZone.current at sync time.
    private static let timezoneIDs = [
        "UTC", "System",
        "America/Anchorage", "America/Chicago", "America/Denver",
        "America/Honolulu", "America/Los_Angeles", "America/New_York",
        "America/Sao_Paulo",
        "Europe/London", "Europe/Paris", "Europe/Berlin",
        "Europe/Helsinki", "Europe/Moscow",
        "Asia/Dubai", "Asia/Kolkata", "Asia/Bangkok",
        "Asia/Shanghai", "Asia/Tokyo",
        "Australia/Perth", "Australia/Sydney",
        "Pacific/Auckland",
    ]

    private var buttonLabel: String {
        isSyncing ? "Syncing…" : (radioManagesNTP ? "Set Timezone" : "Sync Clock")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(buttonLabel) { syncNow() }
            .buttonStyle(CompactButtonStyle(isActive: isSyncing))
            .disabled(isSyncing || radio.connectionStatus != "Connected")
            .accessibilityLabel(radioManagesNTP ? "Set radio clock timezone" : "Sync radio clock from NTP")
            .accessibilityHint(radioManagesNTP
                ? "Sets timezone to \(timezoneLabel(clockTimezoneID)) and triggers radio NTP sync"
                : "Sets the radio clock from \(ntpServer), timezone \(timezoneLabel(clockTimezoneID))")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {

                    // --- Time source ---
                    Text("Time Source").font(.headline)
                    Toggle("Radio manages time via NTP", isOn: $editRadioManagesNTP)
                        .accessibilityLabel("Radio manages time via NTP")
                        .accessibilityHint("When on, the radio syncs its own clock. App only sets the timezone.")

                    if editRadioManagesNTP {
                        Text("The radio will use its configured NTP server. App sets timezone only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("Mac NTP server, e.g. pool.ntp.org", text: $editServer)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                            .accessibilityLabel("Mac NTP server address")
                            .onSubmit { commitAndClose() }
                    }

                    Divider()

                    // --- Timezone ---
                    Text("Clock Timezone").font(.headline)
                    Text("Radio local clock will be set to this timezone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Timezone", selection: $editTimezoneID) {
                        ForEach(Self.timezoneIDs, id: \.self) { id in
                            Text(timezoneLabel(id)).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Clock timezone")

                    HStack {
                        Button("Save") { commitAndClose() }
                        Button("Cancel") { showPopover = false }
                    }
                }
                .padding(12)
                .frame(minWidth: 300)
                .controlSize(.small)
                .onAppear {
                    editServer          = ntpServer
                    editTimezoneID      = clockTimezoneID
                    editRadioManagesNTP = radioManagesNTP
                }
            }
            .contextMenu {
                Button(radioManagesNTP ? "Mode: Radio NTP" : "NTP Server: \(ntpServer)") { showPopover = true }
                Button("Timezone: \(timezoneLabel(clockTimezoneID))") { showPopover = true }
                Button(radioManagesNTP ? "Set Timezone" : "Sync Now") { syncNow() }
                    .disabled(isSyncing || radio.connectionStatus != "Connected")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(statusMessage.hasPrefix("✓") ? .green : .red)
                    .accessibilityLabel(statusMessage)
            }

            Spacer()
        }
        .controlSize(.small)
    }

    private func commitAndClose() {
        let trimmed = editServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { ntpServer = trimmed }
        clockTimezoneID  = editTimezoneID
        radioManagesNTP  = editRadioManagesNTP
        showPopover = false
    }

    private func timezoneLabel(_ id: String) -> String {
        if id == "UTC"    { return "UTC (+00:00)" }
        if id == "System" { return "System — \(offsetLabel(for: TimeZone.current))" }
        guard let tz = TimeZone(identifier: id) else { return id }
        let city = id.components(separatedBy: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? id
        return "\(city) — \(offsetLabel(for: tz))"
    }

    private func offsetLabel(for tz: TimeZone) -> String {
        let sec = tz.secondsFromGMT()
        let sign = sec >= 0 ? "+" : "-"
        let h = abs(sec) / 3600
        let m = (abs(sec) % 3600) / 60
        return m > 0
            ? String(format: "UTC%@%d:%02d", sign, h, m)
            : String(format: "UTC%@%d:00", sign, h)
    }

    private func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = ""

        let tz: TimeZone = clockTimezoneID == "System"
            ? TimeZone.current
            : (TimeZone(identifier: clockTimezoneID) ?? .gmt)
        let offsetMin = tz.secondsFromGMT() / 60

        if radioManagesNTP {
            // Radio manages its own time via NTP.
            // Just set the timezone offset and trigger the radio's NTP sync.
            radio.send(KenwoodCAT.setLocalClockTimezone(offsetMinutes: offsetMin))
            radio.send(KenwoodCAT.triggerRadioNTPSync())
            isSyncing = false
            statusMessage = "✓ Timezone set, radio syncing"
            fpAnnounce("Timezone set to \(tz.identifier). Radio NTP sync triggered.")
            return
        }

        // App-managed: fetch time from Mac NTP, then set CK0 + CK2 with readback verification.
        NTPClient.queryTime(server: ntpServer) { result in
            switch result {
            case .success(let utcDate):
                let cal = Calendar(identifier: .gregorian)
                let comps = cal.dateComponents(in: tz, from: utcDate)
                guard let h = comps.hour, let m = comps.minute, let s = comps.second,
                      let yr = comps.year, let mo = comps.month, let d = comps.day else {
                    isSyncing = false
                    statusMessage = "✕ Bad date"
                    return
                }
                let tzOffsetMin = tz.secondsFromGMT(for: utcDate) / 60
                radio.send(KenwoodCAT.setClockDateTime(year: yr, month: mo, day: d,
                                                       hour: h, minute: m, second: s))
                radio.send(KenwoodCAT.setLocalClockTimezone(offsetMinutes: tzOffsetMin))

                // Verification: read back CK0 after 300 ms.
                let sentDate = utcDate

                let timeoutItem = DispatchWorkItem {
                    radio.pendingCKReadback = nil
                    isSyncing = false
                    statusMessage = "✕ No response from radio"
                    fpAnnounce("Clock sync: no response from radio")
                }

                radio.pendingCKReadback = { payload in
                    timeoutItem.cancel()
                    isSyncing = false
                    guard payload.count >= 12,
                          let rYY = Int(payload.prefix(2)),
                          let rMo = Int(payload.dropFirst(2).prefix(2)),
                          let rD  = Int(payload.dropFirst(4).prefix(2)),
                          let rH  = Int(payload.dropFirst(6).prefix(2)),
                          let rMi = Int(payload.dropFirst(8).prefix(2)),
                          let rS  = Int(payload.dropFirst(10).prefix(2)) else {
                        statusMessage = "✕ Unreadable response"
                        fpAnnounce("Clock sync: unreadable response")
                        return
                    }
                    var rc = DateComponents()
                    rc.year = 2000 + rYY; rc.month = rMo; rc.day = rD
                    rc.hour = rH; rc.minute = rMi; rc.second = rS
                    rc.timeZone = tz
                    if let returnedDate = Calendar(identifier: .gregorian).date(from: rc),
                       abs(returnedDate.timeIntervalSince(sentDate)) < 10 {
                        let sign = tzOffsetMin >= 0 ? "+" : "-"
                        let oh = abs(tzOffsetMin) / 60; let om2 = abs(tzOffsetMin) % 60
                        let tzSuffix = tzOffsetMin == 0 ? "Z"
                            : (om2 > 0 ? String(format: "%@%d:%02d", sign, oh, om2)
                                       : String(format: "%@%d:00", sign, oh))
                        statusMessage = String(format: "✓ %04d-%02d-%02d %02d:%02d:%02d%@",
                                               2000 + rYY, rMo, rD, rH, rMi, rS, tzSuffix)
                        fpAnnounce("Radio clock synced to \(String(format: "%02d:%02d:%02d", rH, rMi, rS)) \(tz.identifier)")
                    } else {
                        statusMessage = "✕ Radio rejected sync (NTP auto-sync may be on)"
                        fpAnnounce("Clock sync rejected by radio")
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    radio.send(KenwoodCAT.getClockDateTime())
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeoutItem)

            case .failure(let err):
                isSyncing = false
                statusMessage = "✕ \(err.localizedDescription)"
                fpAnnounce("Clock sync failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Meters strip (collapsible)
// No radio access — StripMeterBars subscribes to MeterStore independently.

private struct MetersStripRow: View {
    @Binding var expanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse meters" : "Expand meters")

            Text("Meters")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            StripMeterBars()
        }
        .controlSize(.small)
    }
}

// MARK: - Scope panel
// Isolates the high-frequency vfoAFrequencyHz subscription and the
// scopeStore.points push from FrontPanelView.body entirely.

private struct ScopePanel: View {
    let radio: RadioState
    let engine: WaterfallEngine
    private let scopeStore = ScopeStore.shared

    var body: some View {
        ScopeView(
            engine: engine,
            spanKHz: radio.scopeSpanKHz,
            centerHz: radio.vfoAFrequencyHz
        )
        .onChange(of: scopeStore.points) { _, pts in
            guard !pts.isEmpty else { return }
            Task { @MainActor in engine.push(pts) }
        }
    }
}

// MARK: - KnobButton
// Self-contained level-adjust control. Presents its own sheet so no parent
// view needs to hold level-sheet state.

private struct KnobButton: View {
    let label: String
    let value: Int?
    let range: ClosedRange<Int>
    var valueLabel: ((Int) -> String)? = nil
    let action: (Int) -> Void

    @State private var showSheet   = false
    @State private var sliderValue: Double = 0

    private var current:    Int    { value ?? range.lowerBound }
    private var displayVal: String { valueLabel?(current) ?? "\(current)" }

    var body: some View {
        Button("\(label): \(displayVal)") {
            sliderValue = Double(current)
            showSheet   = true
        }
        .buttonStyle(CompactButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(displayVal)
        .contextMenu {
            Button("Set \(label)…") {
                sliderValue = Double(current)
                showSheet   = true
            }
        }
        .sheet(isPresented: $showSheet) {
            LevelAdjustSheet(
                title: label,
                value: $sliderValue,
                range: Double(range.lowerBound)...Double(range.upperBound),
                valueLabel: valueLabel,
                onCommit: { action(Int(sliderValue)) }
            )
        }
    }
}

// MARK: - Compact button style

struct CompactButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive
                          ? tint.opacity(0.25)
                          : Color(white: 0.18).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? tint.opacity(0.6) : Color(white: 0.3), lineWidth: 0.5)
            )
            .foregroundColor(isActive ? tint : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Level adjust sheet

private struct LevelAdjustSheet: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var valueLabel: ((Int) -> String)? = nil
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var stepperFocused: Bool

    private var displayValue: String {
        valueLabel?(Int(value)) ?? "\(Int(value))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Set \(title)")
                .font(.headline)
            Slider(value: $value, in: range, step: 1)
                .frame(width: 300)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
            HStack {
                Stepper(displayValue, value: $value, in: range, step: 1)
                    .accessibilityLabel(title)
                    .accessibilityValue(displayValue)
                    .accessibilityFocused($stepperFocused)
                Spacer()
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Set") { onCommit(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { stepperFocused = true }
    }
}

// MARK: - 4-gauge analog meter grid

private struct MeterGridView: View {
    private let meters = MeterStore.shared

    private let slots: [(String, Int, Double)] = [
        ("S-Meter", 0, 30),
        ("TX Power", 5, 100),
        ("SWR",      3, 3),
        ("ALC",      2, 100),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(slots, id: \.0) { name, index, maxVal in
                analogGauge(name: name, value: meters.readings[index] ?? 0, maxVal: maxVal)
            }
        }
    }

    private func analogGauge(name: String, value: Double, maxVal: Double) -> some View {
        VStack(spacing: 2) {
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height * 0.92
                let r  = Swift.min(size.width, size.height) * 0.80

                let arcPath = Path { p in
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                }
                ctx.stroke(arcPath, with: .color(Color(white: 0.25)), lineWidth: 3)

                let norm    = Swift.min(1, Swift.max(0, value))
                let endDeg  = 180.0 - norm * 180.0
                let fillPath = Path { p in
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(endDeg), clockwise: false)
                }
                let meterColor: Color = norm > 0.8 ? .red : (norm > 0.5 ? .yellow : .green)
                ctx.stroke(fillPath, with: .color(meterColor), lineWidth: 3)

                let angle = Double.pi - norm * Double.pi
                let nx = cx + r * 0.85 * cos(angle)
                let ny = cy - r * 0.85 * sin(angle)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: nx, y: ny))
                }, with: .color(.white), lineWidth: 1.5)
            }
            .frame(height: 60)
            .accessibilityHidden(true)

            Text(name)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(String(format: "%.0f%%", value * 100))
    }
}

// MARK: - Isolated meter bar subviews

private struct InlineMeterBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(Swift.max(0, Swift.min(1, value))))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.0f%%", value * 100))
    }
}

/// Two-bar group used in the DSP toolbar row.
private struct DSPMeterBars: View {
    private let meters = MeterStore.shared

    var body: some View {
        HStack(spacing: 4) {
            InlineMeterBar(label: "S", value: meters.readings[0] ?? 0, color: .green)
                .frame(width: 70)
            InlineMeterBar(label: "P", value: meters.readings[5] ?? 0, color: .yellow)
                .frame(width: 50)
        }
    }
}

/// Four-bar group used in the meters strip row.
private struct StripMeterBars: View {
    private let meters = MeterStore.shared

    var body: some View {
        HStack(spacing: 4) {
            InlineMeterBar(label: "S",   value: meters.readings[0] ?? 0, color: .green)
                .frame(width: 80)
            InlineMeterBar(label: "Pwr", value: meters.readings[5] ?? 0, color: .yellow)
                .frame(width: 70)
            InlineMeterBar(label: "SWR", value: meters.readings[3] ?? 0, color: .orange)
                .frame(width: 60)
            InlineMeterBar(label: "ALC", value: meters.readings[2] ?? 0, color: .red)
                .frame(width: 60)
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
