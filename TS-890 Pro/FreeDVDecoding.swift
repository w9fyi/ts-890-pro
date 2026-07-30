import Foundation

/// Common RX-decode surface shared by the legacy codec2 `FreeDVEngine` (8 kHz
/// speech) and the neural `RADEEngine` (16 kHz speech). Lets the audio
/// pipelines drive either decoder and size the output resampler from the
/// decoder's actual speech sample rate instead of assuming 8 kHz.
protocol FreeDVDecoding: AnyObject {
    /// Feed modem samples (raw full-scale Int16 at the modem rate, 8 kHz for
    /// both decoders) and receive decoded speech Int16 at `speechSampleRate`.
    func feedModemSamples(_ samples: [Int16]) -> [Int16]

    /// Decoded-speech sample rate in Hz (codec2: 8000, RADE: 16000).
    var speechSampleRate: Int { get }

    var isOpen: Bool { get }
}

extension FreeDVEngine: FreeDVDecoding {}
extension RADEEngine: FreeDVDecoding {}

/// Common TX-encode surface shared by the legacy codec2 `FreeDVEngine` (8 kHz
/// speech in) and the neural `RADEEngine` (16 kHz speech in). Both emit real
/// Int16 modem audio at 8 kHz, so the audio pipelines only need the input
/// speech rate to size their mic resampler; the modem-output handling is
/// identical for both. Encoders buffer internally, so callers may feed
/// arbitrary-length speech chunks.
protocol FreeDVEncoding: AnyObject {
    var isOpen: Bool { get }

    /// Speech sample rate the encoder consumes (codec2: 8000, RADE: 16000).
    var txSpeechSampleRate: Int { get }

    /// Feed speech Int16 at `txSpeechSampleRate`; returns whatever real modem
    /// Int16 samples (8 kHz) are ready. Buffers partial frames internally.
    func encodeFromSpeech(_ speech: [Int16]) -> [Int16]

    /// Clear encoder history and pending buffers at the start of an over.
    func resetTx()

    /// Emit any end-of-over signalling (RADE: the EOO/callsign frame) as real
    /// modem Int16 at 8 kHz. codec2 has none and returns empty.
    func finishOver() -> [Int16]
}

extension FreeDVEncoding {
    func resetTx() {}
    func finishOver() -> [Int16] { [] }
}

extension FreeDVEngine: FreeDVEncoding {
    var txSpeechSampleRate: Int { speechSampleRate }
}
extension RADEEngine: FreeDVEncoding {
    var txSpeechSampleRate: Int { speechSampleRate }
}
