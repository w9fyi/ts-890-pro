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
