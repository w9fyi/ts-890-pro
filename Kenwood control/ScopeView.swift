//
//  ScopeView.swift
//  Kenwood control
//
//  Spectrum (top ~30%) + waterfall (bottom ~70%) display.
//  Spectrum drawn with SwiftUI Canvas; waterfall displayed as a CGImage from WaterfallEngine.
//

import SwiftUI

struct ScopeView: View {
    var engine: WaterfallEngine
    let spanKHz: Int          // current span from BS4
    let centerHz: Int?        // VFO A frequency in Hz (nil = no marker)

    // Controls
    @State private var showScopeControls = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Spectrum ────────────────────────────────────────────────
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        drawBackground(ctx: ctx, size: size)
                        drawSpectrum(ctx: ctx, size: size, points: engine.currentPoints)
                        drawCenterMarker(ctx: ctx, size: size)
                        drawFreqAxis(ctx: ctx, size: size)
                    }
                    .accessibilityLabel("Band scope spectrum")
                    .accessibilityValue(spectrumAccessibilityValue)
                    .accessibilityChildren {
                        ForEach(spectrumSegments) { seg in
                            Rectangle()
                                .accessibilityLabel(seg.freqLabel)
                                .accessibilityValue(seg.levelLabel)
                        }
                    }

                    // Scope controls overlay (top-right)
                    HStack(spacing: 4) {
                        Spacer()
                        scopeControlsBar
                            .padding(4)
                    }
                }
                .frame(height: geo.size.height * 0.30)
                .background(Color.black)

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
                    }
                }
                .frame(height: geo.size.height * 0.70)
                .accessibilityLabel("Waterfall display")
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Spectrum drawing

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        // Grid lines
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
        let gridColor = Color(white: 0.15)
        // Horizontal: 4 lines at 25%, 50%, 75%
        for frac in [0.25, 0.50, 0.75] as [Double] {
            let y = size.height * frac
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }, with: .color(gridColor), lineWidth: 0.5)
        }
        // Vertical: divide span into segments
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

        // Build filled path
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, val) in points.enumerated() {
            let x = Double(i) / Double(count - 1) * w
            let norm = Double(val) / Double(0x8C)   // 0=top, 1=bottom
            let y = norm * h
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        ctx.fill(path, with: .color(Color(red: 0.0, green: 0.35, blue: 0.7).opacity(0.6)))

        // Outline
        var outline = Path()
        for (i, val) in points.enumerated() {
            let x = Double(i) / Double(count - 1) * w
            let norm = Double(val) / Double(0x8C)
            let y = norm * h
            if i == 0 { outline.move(to: CGPoint(x: x, y: y)) }
            else       { outline.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(outline, with: .color(.cyan), lineWidth: 1.0)
    }

    private func drawCenterMarker(ctx: GraphicsContext, size: CGSize) {
        guard centerHz != nil else { return }
        let cx = size.width / 2
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: cx, y: 0))
            p.addLine(to: CGPoint(x: cx, y: size.height))
        }, with: .color(Color.white.opacity(0.5)), lineWidth: 1)
    }

    private func drawFreqAxis(ctx: GraphicsContext, size: CGSize) {
        guard let center = centerHz else { return }
        let halfKHz = Double(spanKHz) / 2.0
        let segments = spanSegments
        let font = Font.system(size: 9).monospacedDigit()
        let attrs = AttributeContainer([.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                                        .foregroundColor: NSColor(white: 0.55, alpha: 1)])

        for i in 0...segments {
            let x = size.width * Double(i) / Double(segments)
            let freqHz = Double(center) + (Double(i) / Double(segments) - 0.5) * Double(spanKHz) * 1000.0
            let freqMHz = freqHz / 1_000_000.0
            let label = String(format: "%.3f", freqMHz)
            let text = Text(label).font(font).foregroundColor(Color(white: 0.55))
            ctx.draw(text, at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
        }
    }

    // MARK: - Scope controls bar

    private var scopeControlsBar: some View {
        HStack(spacing: 2) {
            Text("Span: \(spanKHz) kHz")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
        }
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
    }

    // MARK: - Waterfall center marker overlay

    private var centerMarkerOverlay: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            Path { p in
                p.move(to: CGPoint(x: cx, y: 0))
                p.addLine(to: CGPoint(x: cx, y: geo.size.height))
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
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
        guard !engine.currentPoints.isEmpty else { return "No data" }
        let peak = engine.currentPoints.min() ?? 0x8C  // lower val = stronger signal
        let dbVal = Int(Double(peak) / Double(0x8C) * -100)
        return "Peak signal \(dbVal) dB, span \(spanKHz) kHz"
    }

    // Five navigable frequency segments for VoiceOver
    private struct SpectrumSegment: Identifiable {
        let id: Int
        let freqLabel: String   // e.g. "14.200 to 14.210 MHz"
        let levelLabel: String  // e.g. "−45 dB"
    }

    private var spectrumSegments: [SpectrumSegment] {
        guard let center = centerHz, !engine.currentPoints.isEmpty else { return [] }
        let points = engine.currentPoints
        let count  = points.count
        let n      = 5   // number of segments — matches the grid column count
        return (0..<n).map { i in
            let lo  = i * count / n
            let hi  = Swift.min((i + 1) * count / n, count)
            let slice = points[lo..<hi]
            let avg = slice.isEmpty ? UInt8(0x8C)
                : UInt8(slice.reduce(0) { $0 + Int($1) } / slice.count)
            let db  = Int(Double(avg) / Double(0x8C) * -100)

            let spanHz   = Double(spanKHz) * 1_000.0
            let loFreqMHz = (Double(center) + (Double(i)     / Double(n) - 0.5) * spanHz) / 1_000_000
            let hiFreqMHz = (Double(center) + (Double(i + 1) / Double(n) - 0.5) * spanHz) / 1_000_000
            let freqLabel = String(format: "%.3f to %.3f MHz", loFreqMHz, hiFreqMHz)
            return SpectrumSegment(id: i, freqLabel: freqLabel, levelLabel: "\(db) dB")
        }
    }
}
