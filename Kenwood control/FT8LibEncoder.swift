//
//  FT8LibEncoder.swift
//  Kenwood control
//
//  Swift wrapper around ft8_bridge.h for encoding FT8/FT4 messages to audio.
//

import Foundation

enum FT8LibEncoder {

    /// Returns the number of 12 kHz PCM samples the encoder will produce for the given protocol.
    static func audioSampleCount(protocol proto: FT8Protocol, sampleRate: Int = 12_000) -> Int {
        Int(ft8_bridge_audio_sample_count(proto.bridgeProto, Int32(sampleRate)))
    }

    /// Encode a text message to GFSK audio at 12 kHz.
    ///
    /// - Parameters:
    ///   - message:    Text to encode, e.g. "CQ AI5OS EM10"
    ///   - protocol:   `.ft8` or `.ft4`
    ///   - f0:         Base audio frequency in Hz (default 1 500 Hz)
    ///   - sampleRate: Output sample rate in Hz (default 12 000)
    /// - Returns: Float PCM samples, or `nil` if the message cannot be encoded.
    static func encode(message: String,
                       protocol proto: FT8Protocol,
                       f0: Float = 1500.0,
                       sampleRate: Int = 12_000) -> [Float]? {
        let count = audioSampleCount(protocol: proto, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: count)
        let rc = message.withCString { cStr in
            ft8_bridge_encode_audio(cStr, proto.bridgeProto, f0, Int32(sampleRate), &out)
        }
        return rc == 0 ? out : nil
    }
}
