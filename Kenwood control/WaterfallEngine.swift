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

    static let pointsPerRow = 640
    static let displayRows  = 256

    private let width  = WaterfallEngine.pointsPerRow
    private let height = WaterfallEngine.displayRows

    /// Most-recently received spectrum points (640 values). Updated on main actor.
    private(set) var currentPoints: [UInt8] = []

    /// Rendered waterfall image, updated every time a new row arrives.
    private(set) var waterfallImage: CGImage?

    // RGBA pixel buffer: row 0 is the most recent (top of waterfall).
    private var pixelBuffer: [UInt8]
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        pixelBuffer = [UInt8](repeating: 0, count: WaterfallEngine.pointsPerRow * WaterfallEngine.displayRows * 4)
    }

    // MARK: - Public

    /// Push a new 640-point row.  O(n) memmove + O(640) colormap.
    func push(_ points: [UInt8]) {
        guard points.count == WaterfallEngine.pointsPerRow else { return }
        currentPoints = points

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
    /// Colormap: strong signal → red/yellow, medium → green/cyan, weak → dark blue.
    private func color(for val: UInt8) -> (UInt8, UInt8, UInt8) {
        // norm: 1.0 = strongest signal, 0.0 = no signal
        let norm = 1.0 - Double(val) / Double(0x8C)
        switch norm {
        case 0.80...:
            // Red → yellow
            let t = (norm - 0.80) / 0.20
            return (255, UInt8(clamping: Int(255 * t)), 0)
        case 0.55..<0.80:
            // Yellow → green
            let t = (norm - 0.55) / 0.25
            return (UInt8(clamping: Int(255 * (1 - t))), 200, 0)
        case 0.35..<0.55:
            // Green → cyan
            let t = (norm - 0.35) / 0.20
            return (0, UInt8(clamping: Int(150 + 105 * t)), UInt8(clamping: Int(200 * t)))
        case 0.15..<0.35:
            // Cyan → blue
            let t = (norm - 0.15) / 0.20
            return (0, UInt8(clamping: Int(100 * (1 - t))), UInt8(clamping: Int(100 + 155 * t)))
        default:
            // Dark blue → black
            let t = norm / 0.15
            return (0, 0, UInt8(clamping: Int(60 * t)))
        }
    }
}
