//
//  ScopeView.swift
//  Kenwood control
//
//  Spectrum (top ~30%) + waterfall (bottom ~70%) display.
//  Spectrum drawn with SwiftUI Canvas; waterfall displayed as a CGImage from WaterfallEngine.
//  Scope controls bar provides span, mode, max hold, pause, attenuator, averaging,
//  waterfall speed, and reference level — matching the TS-890S bandscope options.
//

import SwiftUI

struct ScopeView: View {
    var engine: WaterfallEngine
    var radio: RadioState
    let spanKHz: Int          // current span from BS4
    let centerHz: Int?        // VFO A frequency in Hz (nil = no marker)

    // Controls popover
    @State private var showScopeSettings = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Spectrum ────────────────────────────────────────────────
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        drawBackground(ctx: ctx, size: size)
                        drawPassband(ctx: ctx, size: size)
                        drawSpectrum(ctx: ctx, size: size, points: engine.currentPoints)
                        if engine.maxHoldEnabled, !engine.maxHoldPoints.isEmpty {
                            drawMaxHold(ctx: ctx, size: size, points: engine.maxHoldPoints)
                        }
                        drawCenterMarker(ctx: ctx, size: size)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Band scope spectrum")
                    .accessibilityValue(spectrumAccessibilityValue)
                    .accessibilityAddTraits([.isImage, .updatesFrequently])

                    // Scope controls overlay (top)
                    VStack(spacing: 0) {
                        scopeControlsBar
                            .padding(4)
                        Spacer()
                    }
                }
                .frame(height: geo.size.height * 0.35)
                .background(Color.black)

                // ── Frequency ruler (TS-Control style band between scope and waterfall)
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(KenwoodTheme.scopeRulerBackground))
                    drawFreqAxis(ctx: ctx, size: size)
                }
                .frame(height: 16)
                .accessibilityHidden(true)

                // ── Waterfall ────────────────────────────────────────────────
                ZStack {
                    Color.black
                    if let img = engine.waterfallImage {
                        Image(img, scale: 1, label: Text("Waterfall"))
                            .resizable()
                            .interpolation(.none)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Waiting for scope data…")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    // Center frequency line over waterfall
                    if centerHz != nil {
                        centerMarkerOverlay
                            .accessibilityHidden(true)
                    }
                    // Pause overlay
                    if radio.scopePaused {
                        VStack {
                            Spacer()
                            Text("PAUSED")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(KenwoodTheme.digitsPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(KenwoodTheme.chassis.opacity(0.8))
                                .cornerRadius(4)
                                .padding(.bottom, 6)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Waterfall display")
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Spectrum drawing

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(KenwoodTheme.scopeBackground))
        let gridColor = KenwoodTheme.scopeGrid
        for frac in [0.25, 0.50, 0.75] as [Double] {
            let y = size.height * frac
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }, with: .color(gridColor), lineWidth: 0.5)
        }
        let segments = spanSegments
        for i in 1..<segments {
            let x = size.width * Double(i) / Double(segments)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawSpectrum(ctx: GraphicsContext, size: CGSize, points: [UInt8]) {
        guard points.count >= 2 else { return }
        let w = size.width
        let h = size.height
        let count = points.count

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, val) in points.enumerated() {
            let x = Double(i) / Double(count - 1) * w
            let norm = Double(val) / Double(0x8C)
            let y = norm * h
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        ctx.fill(path, with: .color(KenwoodTheme.spectrumFill))

        var outline = Path()
        for (i, val) in points.enumerated() {
            let x = Double(i) / Double(count - 1) * w
            let norm = Double(val) / Double(0x8C)
            let y = norm * h
            if i == 0 { outline.move(to: CGPoint(x: x, y: y)) }
            else       { outline.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(outline, with: .color(KenwoodTheme.spectrumOutline), lineWidth: 1.0)
    }

    /// Draw the max-hold peak envelope as a dashed amber line above the live spectrum.
    private func drawMaxHold(ctx: GraphicsContext, size: CGSize, points: [UInt8]) {
        guard points.count >= 2 else { return }
        let w = size.width
        let h = size.height
        let count = points.count

        var path = Path()
        for (i, val) in points.enumerated() {
            let x = Double(i) / Double(count - 1) * w
            let norm = Double(val) / Double(0x8C)
            let y = norm * h
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(KenwoodTheme.meterAmber.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
    }

    // RX filter cut frequencies in Hz, indexed by the radio's SL/SH IDs (SSB tables).
    private static let slHzSSB: [Int] = [
        0, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100,
        1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000,
    ]
    private static let shHzSSB: [Int] = [
        600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700,
        1800, 1900, 2000, 2100, 2200, 2300, 2400, 2500, 2600, 2700, 2800,
        2900, 3000, 3400, 4000, 5000,
    ]
    // CW: SL is a passband-width table.
    private static let slHzCW: [Int] = [
        50, 80, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 900,
        1000, 1200, 1500, 2000, 2500, 3000,
    ]

    /// Translucent blue RX passband overlay at the tuned frequency (TS-Control style).
    /// Approximate for CW (width table centered on the pitch).
    private func drawPassband(ctx: GraphicsContext, size: CGSize) {
        guard centerHz != nil, let mode = radio.operatingMode else { return }
        let spanHz = Double(spanKHz) * 1000.0
        guard spanHz > 0 else { return }

        let hiID = radio.rxFilterHighCutID ?? 14
        let loID = radio.rxFilterLowCutID ?? 0

        var fLow: Double
        var fHigh: Double
        switch mode {
        case .usb, .fsk:
            fLow  = Double(Self.slHzSSB.indices.contains(loID) ? Self.slHzSSB[loID] : 0)
            fHigh = Double(Self.shHzSSB.indices.contains(hiID) ? Self.shHzSSB[hiID] : 2800)
        case .lsb:
            fHigh = -Double(Self.slHzSSB.indices.contains(loID) ? Self.slHzSSB[loID] : 0)
            fLow  = -Double(Self.shHzSSB.indices.contains(hiID) ? Self.shHzSSB[hiID] : 2800)
        case .cw, .cwR:
            let width = Double(Self.slHzCW.indices.contains(loID) ? Self.slHzCW[loID] : 500)
            fLow  = -width / 2
            fHigh =  width / 2
        default:
            // AM/FM — symmetric around the carrier
            let width = Double(Self.shHzSSB.indices.contains(hiID) ? Self.shHzSSB[hiID] : 3000)
            fLow  = -width
            fHigh =  width
        }

        let x0 = size.width * (0.5 + fLow / spanHz)
        let x1 = size.width * (0.5 + fHigh / spanHz)
        guard x1 > x0 else { return }
        let rect = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
        ctx.fill(Path(rect), with: .color(KenwoodTheme.passbandBlue))
    }

    private func drawCenterMarker(ctx: GraphicsContext, size: CGSize) {
        guard centerHz != nil else { return }
        let cx = size.width / 2
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: cx, y: 0))
            p.addLine(to: CGPoint(x: cx, y: size.height))
        }, with: .color(KenwoodTheme.scopeCenterMarker), lineWidth: 1)
    }

    private func drawFreqAxis(ctx: GraphicsContext, size: CGSize) {
        guard let center = centerHz else { return }
        let segments = spanSegments
        let font = Font.system(size: 9).monospacedDigit()
        let attrs = AttributeContainer([.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                                        .foregroundColor: NSColor(red: 0.55, green: 0.55, blue: 0.50, alpha: 1)])

        for i in 0...segments {
            let x = size.width * Double(i) / Double(segments)
            let freqHz = Double(center) + (Double(i) / Double(segments) - 0.5) * Double(spanKHz) * 1000.0
            let freqMHz = freqHz / 1_000_000.0
            let label = String(format: "%.3f", freqMHz)
            let text = Text(label).font(font).foregroundColor(KenwoodTheme.scopeFreqText)
            ctx.draw(text, at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
        }
    }

    // MARK: - Scope controls bar

    private var scopeControlsBar: some View {
        HStack(spacing: 6) {
            // Span picker
            Menu {
                ForEach(KenwoodCAT.scopeSpanOptions, id: \.kHz) { opt in
                    Button("\(opt.kHz) kHz") { radio.setScopeSpan(kHz: opt.kHz) }
                }
            } label: {
                Text("Span: \(spanKHz) kHz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(KenwoodTheme.digitsPrimary)
                    .accessibilityHidden(true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Scope span")
            .accessibilityValue("\(spanKHz) kilohertz")

            scopeDivider

            // Mode picker
            Menu {
                ForEach(KenwoodCAT.ScopeMode.allCases) { mode in
                    Button(mode.label) { radio.setScopeMode(mode) }
                }
            } label: {
                Text(radio.scopeMode.label)
                    .font(.system(size: 10))
                    .foregroundColor(KenwoodTheme.digitsSecondary)
                    .accessibilityHidden(true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Scope mode")
            .accessibilityValue(radio.scopeMode.label)

            scopeDivider

            // Max Hold toggle
            Button(action: {
                let newVal = !radio.scopeMaxHold
                radio.setScopeMaxHold(newVal)
                engine.maxHoldEnabled = newVal
                if !newVal { engine.clearMaxHold() }
            }) {
                Text("MAX")
                    .font(.system(size: 9, weight: radio.scopeMaxHold ? .bold : .regular))
                    .foregroundColor(radio.scopeMaxHold ? KenwoodTheme.blueLight : KenwoodTheme.labelSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Max hold")
            .accessibilityValue(radio.scopeMaxHold ? "On" : "Off")

            // Pause toggle
            Button(action: { radio.setScopePaused(!radio.scopePaused) }) {
                Image(systemName: radio.scopePaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9))
                    .foregroundColor(radio.scopePaused ? KenwoodTheme.blueLight : KenwoodTheme.labelSecondary)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(radio.scopePaused ? "Resume scope" : "Pause scope")

            scopeDivider

            // Reference level — inline like TS-Control's waterfall slider
            Text("Ref")
                .font(.system(size: 9))
                .foregroundColor(KenwoodTheme.labelSecondary)
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { Double(radio.scopeRefLevel) },
                set: { radio.setScopeRefLevel(Int($0)) }
            ), in: 0...120, step: 1)
            .controlSize(.mini)
            .frame(width: 90)
            .accessibilityLabel("Reference level")
            .accessibilityValue(refLevelLabel)

            Spacer()

            // Settings gear — opens full controls popover
            Button(action: { showScopeSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundColor(KenwoodTheme.labelSecondary)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scope settings")
            .popover(isPresented: $showScopeSettings, arrowEdge: .bottom) {
                scopeSettingsPopover
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(KenwoodTheme.chassis.opacity(0.85))
        .cornerRadius(4)
    }

    private var scopeDivider: some View {
        Rectangle()
            .fill(KenwoodTheme.border)
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }

    // MARK: - Scope settings popover

    private var scopeSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scope Settings")
                .font(.headline)
                .foregroundColor(KenwoodTheme.digitsPrimary)

            // Attenuator
            HStack {
                Text("Attenuator:")
                    .frame(width: 100, alignment: .trailing)
                Picker("Attenuator", selection: Binding(
                    get: { radio.scopeAttenuator },
                    set: { radio.setScopeAttenuator($0) }
                )) {
                    ForEach(KenwoodCAT.ScopeAttenuator.allCases) { att in
                        Text(att.label).tag(att)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Averaging
            HStack {
                Text("Averaging:")
                    .frame(width: 100, alignment: .trailing)
                Picker("Averaging", selection: Binding(
                    get: { radio.scopeAveraging },
                    set: { radio.setScopeAveraging($0) }
                )) {
                    ForEach(KenwoodCAT.ScopeAveraging.allCases) { avg in
                        Text(avg.label).tag(avg)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Waterfall speed
            HStack {
                Text("Waterfall speed:")
                    .frame(width: 100, alignment: .trailing)
                Picker("Speed", selection: Binding(
                    get: { radio.scopeWaterfallSpeed },
                    set: { radio.setScopeWaterfallSpeed($0) }
                )) {
                    Text("1 (Slow)").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4 (Fast)").tag(4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Reference level
            HStack {
                Text("Ref level:")
                    .frame(width: 100, alignment: .trailing)
                Slider(value: Binding(
                    get: { Double(radio.scopeRefLevel) },
                    set: { radio.setScopeRefLevel(Int($0)) }
                ), in: 0...120, step: 1)
                .frame(width: 180)
                .accessibilityLabel("Reference level")
                .accessibilityValue(refLevelLabel)
                Text(refLevelLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(KenwoodTheme.digitsSecondary)
                    .frame(width: 50)
            }

            Divider()

            // Clear waterfall
            Button("Clear Waterfall") {
                radio.clearScopeWaterfall()
                engine.clear()
            }
            .accessibilityLabel("Clear waterfall display")
        }
        .padding(16)
        .frame(width: 380)
    }

    private var refLevelLabel: String {
        let db = Double(radio.scopeRefLevel) / 2.0
        return String(format: "%.1f dB", db)
    }

    // MARK: - Waterfall center marker overlay

    private var centerMarkerOverlay: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            Path { p in
                p.move(to: CGPoint(x: cx, y: 0))
                p.addLine(to: CGPoint(x: cx, y: geo.size.height))
            }
            .stroke(KenwoodTheme.scopeCenterMarker, lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private var spanSegments: Int {
        switch spanKHz {
        case 5:   return 5
        case 10:  return 5
        case 25:  return 5
        case 50:  return 5
        case 100: return 10
        case 200: return 10
        case 500: return 10
        default:  return 5
        }
    }

    private var spectrumAccessibilityValue: String {
        guard let center = centerHz else {
            return "Not connected, span \(spanKHz) kHz"
        }
        guard !engine.currentPoints.isEmpty else {
            return "No data yet, span \(spanKHz) kHz, mode \(radio.scopeMode.label)"
        }
        let points  = engine.currentPoints
        let count   = points.count
        let n       = 5
        let spanHz  = Double(spanKHz) * 1_000.0
        var parts   = [String]()
        for i in 0..<n {
            let lo    = i * count / n
            let hi    = Swift.min((i + 1) * count / n, count)
            let slice = points[lo..<hi]
            let sum   = slice.reduce(0) { $0 + Int($1) }
            let avg   = slice.isEmpty ? UInt8(0x8C) : UInt8(sum / slice.count)
            let db    = Int(Double(avg) / Double(0x8C) * -100)
            let mid   = (Double(center) + ((Double(i) + 0.5) / Double(n) - 0.5) * spanHz) / 1_000_000
            parts.append(String(format: "%.3f MHz: %d dB", mid, db))
        }
        let peak    = points.min() ?? 0x8C
        let peakDb  = Int(Double(peak) / Double(0x8C) * -100)
        let segs    = parts.joined(separator: ", ")
        return "Peak \(peakDb) dB, span \(spanKHz) kHz, mode \(radio.scopeMode.label). Segments: \(segs)"
    }

}
