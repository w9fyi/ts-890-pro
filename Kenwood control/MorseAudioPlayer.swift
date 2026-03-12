import AVFoundation

/// Synthesises Morse code tones and plays them through the Mac's default audio output.
/// Used to give VoiceOver users an audible cue when the radio connects or disconnects —
/// no radio transmission is involved; everything stays local on the Mac.
final class MorseAudioPlayer {

    nonisolated deinit {}

    // MARK: - Parameters

    private let frequency: Double = 700.0   // Hz — classic CW sidetone pitch
    private let wpm: Double = 20.0          // words per minute
    private var unitSeconds: Double { 1.2 / wpm }  // one dot duration in seconds

    // MARK: - Morse table

    private static let morseTable: [Character: String] = [
        "A": ".-",   "B": "-...", "C": "-.-.", "D": "-..",
        "E": ".",    "F": "..-.", "G": "--.",  "H": "....",
        "I": "..",   "J": ".---", "K": "-.-",  "L": ".-..",
        "M": "--",   "N": "-.",   "O": "---",  "P": ".--.",
        "Q": "--.-", "R": ".-.",  "S": "...",  "T": "-",
        "U": "..-",  "V": "...-", "W": ".--",  "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--",
        "4": "....-", "5": ".....", "6": "-....", "7": "--...",
        "8": "---..", "9": "----."
    ]

    // MARK: - Audio engine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100.0

    init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            AppFileLogger.shared.log("MorseAudioPlayer: engine start failed: \(error)")
        }
    }

    // MARK: - Public API

    /// Synthesise `text` as Morse code and play it through the Mac's speakers.
    /// Non-blocking — audio plays asynchronously while the caller continues.
    func play(_ text: String) {
        guard let buffer = buildBuffer(for: text) else { return }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    // MARK: - Buffer synthesis

    private struct Segment { let frames: Int; let isTone: Bool }

    private func buildBuffer(for text: String) -> AVAudioPCMBuffer? {
        let u = unitSeconds
        var segments: [Segment] = []

        let words = text.uppercased().split(separator: " ", omittingEmptySubsequences: true)
        for (wi, word) in words.enumerated() {
            if wi > 0 {
                // Inter-word gap is 7 units. The previous word's last inter-char gap (3 units)
                // was not appended, so we need 7 units here.
                segments.append(Segment(frames: frames(for: 7 * u), isTone: false))
            }
            for (ci, char) in word.enumerated() {
                if ci > 0 {
                    segments.append(Segment(frames: frames(for: 3 * u), isTone: false)) // inter-char
                }
                guard let code = Self.morseTable[char] else { continue }
                for (ei, elem) in code.enumerated() {
                    if ei > 0 {
                        segments.append(Segment(frames: frames(for: u), isTone: false)) // intra-char
                    }
                    let dur = elem == "-" ? 3 * u : u
                    segments.append(Segment(frames: frames(for: dur), isTone: true))
                }
            }
        }

        let totalFrames = segments.reduce(0) { $0 + $1.frames }
        guard totalFrames > 0 else { return nil }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let samples = buffer.floatChannelData![0]
        let rampFrames = Int(0.005 * sampleRate)  // 5 ms linear ramp to eliminate click artefacts
        let amplitude: Float = 0.35
        let phaseInc = 2.0 * Double.pi * frequency / sampleRate
        var offset = 0
        var phase = 0.0

        for seg in segments {
            if seg.isTone {
                // Per-segment effective ramp so short dots don't overflow.
                let effRamp = min(rampFrames, seg.frames / 2)
                for i in 0..<seg.frames {
                    let env: Float
                    if i < effRamp {
                        env = Float(i) / Float(max(1, effRamp))
                    } else if i >= seg.frames - effRamp {
                        env = Float(seg.frames - i) / Float(max(1, effRamp))
                    } else {
                        env = 1.0
                    }
                    samples[offset + i] = Float(sin(phase)) * amplitude * env
                    phase += phaseInc
                }
            } else {
                for i in 0..<seg.frames { samples[offset + i] = 0.0 }
                phase = 0.0  // reset phase so the next tone starts cleanly
            }
            offset += seg.frames
        }

        return buffer
    }

    private func frames(for seconds: Double) -> Int {
        max(1, Int((seconds * sampleRate).rounded()))
    }
}
