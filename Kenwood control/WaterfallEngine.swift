//
//  WaterfallEngine.swift
//  Kenwood control
//
//  Maintains a pixel buffer for the waterfall display.
//  New scope rows are prepended (most recent at top); old rows fall off the bottom.
//  Produces a CGImage ready for SwiftUI display — no per-frame heap allocations after init.
//

import Foundation
import CoreGraphics
import SwiftUI
import Observation

@MainActor
@Observable
final class WaterfallEngine {

    nonisolated deinit {}

    static let pointsPerRow = 640
    static let displayRows  = 256

    private let width  = WaterfallEngine.pointsPerRow
    private let height = WaterfallEngine.displayRows

    /// Most-recently received spectrum points (640 values). Updated on main actor.
    private(set) var currentPoints: [UInt8] = []

    /// Max-hold peak envelope — lowest raw values seen (lower = stronger signal).
    /// Reset when maxHoldEnabled transitions to true or clearMaxHold() is called.
    private(set) var maxHoldPoints: [UInt8] = []

    /// Whether max-hold tracking is active.
    var maxHoldEnabled: Bool = false {
        didSet { if maxHoldEnabled && !oldValue { clearMaxHold() } }
    }

    /// Rendered waterfall image, updated every time a new row arrives.
    private(set) var waterfallImage: CGImage?

    // RGBA pixel buffer: row 0 is the most recent (top of waterfall).
    private var pixelBuffer: [UInt8]
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        pixelBuffer = [UInt8](repeating: 0, count: WaterfallEngine.pointsPerRow * WaterfallEngine.displayRows * 4)
    }

    // MARK: - Public

    /// Clear the max-hold peak envelope.
    func clearMaxHold() {
        maxHoldPoints = [UInt8](repeating: 0xFF, count: WaterfallEngine.pointsPerRow)
    }

    /// Push a new 640-point row.  O(n) memmove + O(640) colormap.
    func push(_ points: [UInt8]) {
        guard points.count == WaterfallEngine.pointsPerRow else { return }
        currentPoints = points

        // Update max-hold envelope (lower raw value = stronger signal)
        if maxHoldEnabled {
            if maxHoldPoints.count != points.count { clearMaxHold() }
            for i in 0..<points.count {
                if points[i] < maxHoldPoints[i] { maxHoldPoints[i] = points[i] }
            }
        }

        let rowBytes = width * 4

        // Shift existing rows down by one (row 0 → row 1, etc.)
        if height > 1 {
            pixelBuffer.withUnsafeMutableBytes { buf in
                let ptr = buf.baseAddress!
                memmove(ptr.advanced(by: rowBytes), ptr, rowBytes * (height - 1))
            }
        }

        // Write new row at index 0 (top)
        for x in 0..<width {
            let (r, g, b) = color(for: points[x])
            let base = x * 4
            pixelBuffer[base + 0] = r
            pixelBuffer[base + 1] = g
            pixelBuffer[base + 2] = b
            pixelBuffer[base + 3] = 255
        }

        rebuildImage()
    }

    func clear() {
        currentPoints = []
        maxHoldPoints = []
        pixelBuffer = [UInt8](repeating: 0, count: width * height * 4)
        waterfallImage = nil
    }

    // MARK: - Private

    private func rebuildImage() {
        pixelBuffer.withUnsafeBytes { bytes in
            guard let provider = CGDataProvider(data: NSData(bytes: bytes.baseAddress!, length: bytes.count)) else { return }
            waterfallImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
    }

    /// Map a scope value (0x00=0 dB peak … 0x8C=−100 dB floor) to an RGB color.
    /// TS-Control-style blue waterfall: noise floor reads as blue, signals climb
    /// through cyan and green to yellow/white at the strongest.
    private static let colorStops: [(Double, (Double, Double, Double))] = [
        (0.00, (0, 0, 30)),       // silence — near black
        (0.35, (0, 30, 180)),     // noise floor — blue
        (0.55, (0, 180, 255)),    // weak signal — cyan
        (0.72, (40, 220, 80)),    // medium — green
        (0.88, (255, 255, 0)),    // strong — yellow
        (1.00, (255, 255, 220)),  // strongest — near white
    ]

    private func color(for val: UInt8) -> (UInt8, UInt8, UInt8) {
        // norm: 1.0 = strongest signal, 0.0 = no signal
        let norm = Swift.max(0, Swift.min(1, 1.0 - Double(val) / Double(0x8C)))
        let stops = Self.colorStops
        for i in 1..<stops.count where norm <= stops[i].0 {
            let (f0, c0) = stops[i - 1]
            let (f1, c1) = stops[i]
            let t = f1 > f0 ? (norm - f0) / (f1 - f0) : 0
            return (UInt8(clamping: Int(c0.0 + (c1.0 - c0.0) * t)),
                    UInt8(clamping: Int(c0.1 + (c1.1 - c0.1) * t)),
                    UInt8(clamping: Int(c0.2 + (c1.2 - c0.2) * t)))
        }
        return (255, 255, 220)
    }
}
