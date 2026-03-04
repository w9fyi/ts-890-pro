//
//  FT8LibDecoder.swift
//  Kenwood control
//
//  Swift wrapper around ft8_bridge.h for decoding FT8/FT4 audio slots.
//

import Foundation

/// FT8/FT4 protocol selector.
enum FT8Protocol: String, CaseIterable {
    case ft8 = "FT8"
    case ft4 = "FT4"

    /// Duration of one transmission slot in seconds.
    var slotDuration: Double {
        switch self {
        case .ft8: return 15.0
        case .ft4: return 7.5
        }
    }

    /// Number of 12 kHz audio samples per slot.
    var slotSamples: Int { Int(slotDuration * 12_000) }

    var bridgeProto: Int32 {
        switch self {
        case .ft8: return Int32(FT8_BRIDGE_PROTO_FT8)
        case .ft4: return Int32(FT8_BRIDGE_PROTO_FT4)
        }
    }
}

/// A single decoded FT8/FT4 message.
struct DecodedFT8Message {
    let message: String   // e.g. "CQ K1ABC FN42"
    let freqHz:  Float    // audio tone frequency in Hz
    let timeSec: Float    // time offset within the slot
    let snr:     Float    // approximate SNR
}

// Internal box used to collect results through the C callback.
private final class DecodeResultBox {
    var results: [DecodedFT8Message] = []
}

enum FT8LibDecoder {

    /// Decode a single FT8 or FT4 slot from a 12 kHz mono float PCM array.
    /// Runs synchronously — call from a background thread.
    ///
    /// - Parameters:
    ///   - samples12k: Float PCM samples at 12 000 Hz
    ///   - protocol:   `.ft8` or `.ft4`
    /// - Returns: Array of decoded messages (may be empty).
    static func decodeSlot(samples12k: [Float], protocol proto: FT8Protocol) -> [DecodedFT8Message] {
        let box = DecodeResultBox()
        let boxPtr = Unmanaged.passRetained(box).toOpaque()

        samples12k.withUnsafeBufferPointer { buf in
            ft8_bridge_decode_slot(
                buf.baseAddress,
                Int32(buf.count),
                12_000,
                proto.bridgeProto,
                { msg, freq, time, snr, userdata in
                    guard let msg = msg, let userdata = userdata else { return }
                    let b = Unmanaged<DecodeResultBox>.fromOpaque(userdata).takeUnretainedValue()
                    b.results.append(DecodedFT8Message(
                        message: String(cString: msg),
                        freqHz:  freq,
                        timeSec: time,
                        snr:     snr
                    ))
                },
                boxPtr
            )
        }

        // Release the retained reference now that the C call is done.
        Unmanaged.passUnretained(box).release()
        return box.results
    }
}
