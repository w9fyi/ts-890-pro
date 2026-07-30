import Foundation

/// Chains two noise reduction processors in series.
///
/// Processing order:
///   1. primary   — RNNoise: broadband noise, static crashes, speech preservation
///   2. secondary — WDSP ANR: residual heterodynes and periodic carriers
///
/// The `isEnabled` gate controls both sub-processors together.
/// Either sub-processor's `processFrame48kMonoInPlace` is a no-op when its
/// own `isEnabled` is false, so setting the cascade's `isEnabled` to true
/// must propagate down to both inner processors — which the `didSet` below
/// handles automatically.
///
/// `isAvailable` is true only when both sub-processors are available.
final class CascadeNoiseReductionProcessor: NoiseReductionProcessor {
    nonisolated deinit {}

    let primary:   any NoiseReductionProcessor   // RNNoise
    let secondary: any NoiseReductionProcessor   // WDSP ANR

    var isAvailable: Bool { primary.isAvailable && secondary.isAvailable }

    var isEnabled: Bool = false {
        didSet {
            primary.isEnabled   = isEnabled
            secondary.isEnabled = isEnabled
        }
    }

    init(primary: any NoiseReductionProcessor, secondary: any NoiseReductionProcessor) {
        self.primary   = primary
        self.secondary = secondary
    }

    func processFrame48kMono(_ frame: [Float]) -> [Float] {
        var out = frame
        processFrame48kMonoInPlace(&out)
        return out
    }

    func processFrame48kMonoInPlace(_ frame: inout [Float]) {
        guard isEnabled else { return }
        primary.processFrame48kMonoInPlace(&frame)
        secondary.processFrame48kMonoInPlace(&frame)
    }
}
