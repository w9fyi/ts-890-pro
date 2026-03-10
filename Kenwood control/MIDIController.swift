//
//  MIDIController.swift
//  Kenwood control
//
//  CoreMIDI integration with MIDI-learn style control assignment.
//  Any MIDI source can be connected; individual knobs and buttons
//  are then assigned to radio actions through an interactive learn flow.
//
//  Mappings are stored globally (not per-profile) in UserDefaults as JSON.
//  Fully accessible with VoiceOver — detected controls and available actions
//  are announced through the learn sheet UI.
//

import Foundation
import CoreMIDI
import Observation

// MARK: - Tuning step

/// How far VFO A moves per relative encoder click when assigned to vfoTune.
enum MIDITuningStep: Int, CaseIterable, Identifiable, Codable {
    case hz1     =       1
    case hz10    =      10
    case hz100   =     100
    case khz1    =   1_000
    case khz10   =  10_000
    case khz100  = 100_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hz1:    return "1 Hz"
        case .hz10:   return "10 Hz"
        case .hz100:  return "100 Hz"
        case .khz1:   return "1 kHz"
        case .khz10:  return "10 kHz"
        case .khz100: return "100 kHz"
        }
    }
}

// MARK: - MIDI event kinds

enum MIDIEventKind: String, Codable {
    case cc       // Control Change (0xBn) — typically knobs/encoders
    case noteOn   // Note On (0x9n) or Note On vel=0 — typically buttons
}

// MARK: - Actions

/// Every assignable radio action. Bidirectional actions respond to relative
/// encoder direction (clicks > 0 = positive, clicks < 0 = negative).
/// Button actions fire on any non-zero trigger.
enum MIDIAction: String, CaseIterable, Codable {
    case vfoTune     // Relative: CW = tune up, CCW = tune down (step configurable)
    case afGain      // Relative: CW = louder, CCW = quieter (10 units/click, 0–255)
    case rfGain      // Relative: CW = more RF gain, CCW = less (10 units/click, 0–255)
    case txPower     // Relative: CW = higher power, CCW = lower (5 W/click, 5–100 W)
    case memoryStep  // Relative: CW = next memory channel, CCW = previous (0–119)
    case pttToggle   // Button: each trigger alternates TX/RX
    case pttHold     // Button: trigger = TX on; release (Note Off or CCW) = RX

    var displayName: String {
        switch self {
        case .vfoTune:    return "Tune VFO A"
        case .afGain:     return "Audio (AF) Volume"
        case .rfGain:     return "RF Gain"
        case .txPower:    return "TX Power"
        case .memoryStep: return "Memory Channel"
        case .pttToggle:  return "PTT Toggle"
        case .pttHold:    return "PTT Hold"
        }
    }

    var actionDescription: String {
        switch self {
        case .vfoTune:    return "Clockwise tunes up, counterclockwise tunes down. Step size is configurable."
        case .afGain:     return "Clockwise raises audio volume, counterclockwise lowers it."
        case .rfGain:     return "Clockwise increases RF gain, counterclockwise decreases it."
        case .txPower:    return "Clockwise raises transmit power, counterclockwise lowers it."
        case .memoryStep: return "Clockwise steps to the next memory channel, counterclockwise to the previous."
        case .pttToggle:  return "Each press alternates between transmit and receive."
        case .pttHold:    return "Hold the control to transmit; release to return to receive."
        }
    }
}

// MARK: - Detected MIDI event (during learn)

struct DetectedMIDIEvent {
    let kind: MIDIEventKind
    let channel: Int      // 0-based
    let number: Int       // CC number or note number
    let value: Int
    let sourceName: String

    /// Human-readable description announced to the user after detection.
    var humanDescription: String {
        switch kind {
        case .cc:
            return "Control Change \(number), MIDI Channel \(channel + 1) from \"\(sourceName)\""
        case .noteOn:
            return "Button (Note \(number)), MIDI Channel \(channel + 1) from \"\(sourceName)\""
        }
    }
}

// MARK: - Persistent mapping

struct MIDIMapping: Identifiable, Codable {
    var id: UUID = UUID()
    var eventKind: MIDIEventKind
    var channel: Int       // 0-based
    var number: Int        // CC or note number
    var action: MIDIAction
    var vfoStep: MIDITuningStep   // only meaningful for .vfoTune

    /// Short description shown in the mapping list row.
    var controlDescription: String {
        switch eventKind {
        case .cc:
            return "CC \(number), Ch \(channel + 1)"
        case .noteOn:
            return "Note \(number), Ch \(channel + 1)"
        }
    }

    /// Full VoiceOver label for the list row.
    var accessibilityRowLabel: String {
        var label = "\(action.displayName), assigned to \(controlDescription)"
        if action == .vfoTune {
            label += ", step \(vfoStep.label)"
        }
        return label
    }
}

// MARK: - MIDI source info

struct MIDISourceInfo: Identifiable, Hashable {
    let id: MIDIEndpointRef
    let name: String
}

// MARK: - Controller

/// Singleton that manages a CoreMIDI input port and routes MIDI events to
/// radio actions according to user-configured mappings.
///
/// Usage:
///   1. Set `radio` to the app's `RadioState` instance (done in the App struct).
///   2. Present `MIDISectionView` to let the user connect a source and learn mappings.
///   3. Interact with the MIDI controller; assigned actions fire automatically.
@Observable
final class MIDIController {

    static let shared = MIDIController()

    // MARK: Published

    var availableSources: [MIDISourceInfo] = []
    var selectedSourceRef: MIDIEndpointRef = 0
    var isConnected: Bool = false
    var lastMIDIEvent: String = ""

    /// True while we are waiting for the user to touch a control.
    var isLearning: Bool = false
    /// Set to the first MIDI event received while `isLearning` is true.
    var detectedEvent: DetectedMIDIEvent?
    /// Ordered list of saved control → action mappings.
    var mappings: [MIDIMapping] = []

    weak var radio: RadioState?

    // MARK: Private CoreMIDI state

    private var midiClient:   MIDIClientRef = 0
    private var inputPort:    MIDIPortRef   = 0
    private var activeSource: MIDIEndpointRef = 0

    // UserDefaults keys
    private let kSourceName = "MIDI.SourceName"
    private let kMappings   = "MIDI.Mappings"

    // MARK: Init

    private init() {
        loadMappings()
        setupClient()
        refreshSources()
    }

    // MARK: - CoreMIDI setup

    private func setupClient() {
        let clientStatus = MIDIClientCreateWithBlock(
            "KenwoodControl.MIDIClient" as CFString,
            &midiClient
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshSources() }
        }
        guard clientStatus == noErr else {
            AppLogger.error("MIDI: MIDIClientCreate failed (\(clientStatus))")
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(
            midiClient,
            "KenwoodControl.InputPort" as CFString,
            &inputPort
        ) { [weak self] packetListPtr, _ in
            self?.processMIDIPacketList(packetListPtr)
        }
        guard portStatus == noErr else {
            AppLogger.error("MIDI: MIDIInputPortCreate failed (\(portStatus))")
            return
        }
    }

    // MARK: - Source management

    func refreshSources() {
        let count = MIDIGetNumberOfSources()
        var sources: [MIDISourceInfo] = []
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            var cfName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &cfName)
            let name = (cfName?.takeRetainedValue() as String?) ?? "MIDI Source \(i)"
            sources.append(MIDISourceInfo(id: endpoint, name: name))
        }
        availableSources = sources

        if selectedSourceRef == 0 || !sources.contains(where: { $0.id == selectedSourceRef }) {
            if let ctr = sources.first(where: {
                let n = $0.name.lowercased()
                return n.contains("ctr2midi") || n.contains("ctr 2 midi") || n.contains("ctr-2-midi")
            }) {
                connect(to: ctr.id)
            } else if let savedName = UserDefaults.standard.string(forKey: kSourceName),
                      let found = sources.first(where: { $0.name == savedName }) {
                connect(to: found.id)
            }
        }
    }

    func connect(to endpoint: MIDIEndpointRef) {
        if activeSource != 0 {
            MIDIPortDisconnectSource(inputPort, activeSource)
            activeSource = 0
        }
        guard MIDIPortConnectSource(inputPort, endpoint, nil) == noErr else {
            DispatchQueue.main.async { self.isConnected = false }
            return
        }
        activeSource = endpoint
        selectedSourceRef = endpoint
        if let info = availableSources.first(where: { $0.id == endpoint }) {
            UserDefaults.standard.set(info.name, forKey: kSourceName)
        }
        DispatchQueue.main.async { self.isConnected = true }
    }

    func disconnect() {
        guard activeSource != 0 else { return }
        MIDIPortDisconnectSource(inputPort, activeSource)
        activeSource = 0
        DispatchQueue.main.async {
            self.selectedSourceRef = 0
            self.isConnected = false
        }
    }

    /// Returns the display name of the currently active MIDI source.
    private func currentSourceName() -> String {
        availableSources.first(where: { $0.id == activeSource })?.name ?? "Unknown"
    }

    // MARK: - Learn mode

    func startLearning() {
        DispatchQueue.main.async {
            self.detectedEvent = nil
            self.isLearning = true
        }
    }

    func stopLearning() {
        DispatchQueue.main.async {
            self.isLearning = false
            self.detectedEvent = nil
        }
    }

    // MARK: - Mapping management

    func addMapping(event: DetectedMIDIEvent, action: MIDIAction, vfoStep: MIDITuningStep) {
        let mapping = MIDIMapping(
            eventKind: event.kind,
            channel: event.channel,
            number: event.number,
            action: action,
            vfoStep: vfoStep
        )
        DispatchQueue.main.async {
            self.mappings.append(mapping)
            self.saveMappings()
            self.isLearning = false
            self.detectedEvent = nil
        }
    }

    func removeMapping(id: UUID) {
        mappings.removeAll(where: { $0.id == id })
        saveMappings()
    }

    // MARK: - Persistence

    private func saveMappings() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: kMappings)
    }

    private func loadMappings() {
        guard let data = UserDefaults.standard.data(forKey: kMappings),
              let loaded = try? JSONDecoder().decode([MIDIMapping].self, from: data) else { return }
        mappings = loaded
    }

    // MARK: - Packet processing (CoreMIDI thread)

    private func processMIDIPacketList(_ listPtr: UnsafePointer<MIDIPacketList>) {
        var packet = listPtr.pointee.packet
        let count  = listPtr.pointee.numPackets
        for _ in 0..<count {
            let length = Int(packet.length)
            withUnsafeBytes(of: packet.data) { raw in
                var i = 0
                while i < length {
                    let status      = raw[i]
                    let messageType = status & 0xF0
                    let channel     = Int(status & 0x0F)

                    if messageType == 0xB0 && i + 2 < length {
                        // Control Change (knob / encoder)
                        let cc    = Int(raw[i + 1])
                        let value = Int(raw[i + 2])
                        DispatchQueue.main.async { [weak self] in
                            self?.handleCC(channel: channel, cc: cc, value: value)
                        }
                        i += 3
                    } else if (messageType == 0x90 || messageType == 0x80) && i + 2 < length {
                        // Note On (0x9n) or Note Off (0x8n).
                        // Note On with velocity 0 is equivalent to Note Off per MIDI 1.0 spec.
                        let note     = Int(raw[i + 1])
                        let velocity = messageType == 0x80 ? 0 : Int(raw[i + 2])
                        DispatchQueue.main.async { [weak self] in
                            self?.handleNote(channel: channel, note: note, velocity: velocity)
                        }
                        i += 3
                    } else if messageType == 0xF0 {
                        break // SysEx — skip remainder of packet
                    } else {
                        i += 1
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    // MARK: - CC handler (main thread)

    private func handleCC(channel: Int, cc: Int, value: Int) {
        lastMIDIEvent = "CC ch\(channel + 1) #\(cc) = \(value)"

        // Capture the first event when in learn mode.
        if isLearning && detectedEvent == nil {
            detectedEvent = DetectedMIDIEvent(
                kind: .cc,
                channel: channel,
                number: cc,
                value: value,
                sourceName: currentSourceName()
            )
            isLearning = false
            return
        }

        // Decode relative encoder direction.
        // CTR2MIDI convention (also used by many other controllers):
        //   65–127 → clockwise  (+1 to +63 clicks; 65 = +1, 127 = +63)
        //   1–63   → counterclockwise (1 = −63, 63 = −1)
        //   0      → some encoders use 0 for a single CCW step; treat as −1
        //   64     → center detent / no change
        let clicks: Int
        switch value {
        case 65...127: clicks =  (128 - value)   // CW: +1 … +63
        case 1...63:   clicks = -value            // CCW: −63 … −1
        case 0:        clicks = -1
        default:       clicks =  0
        }
        guard clicks != 0 else { return }

        guard let mapping = mappings.first(where: {
            $0.eventKind == .cc && $0.channel == channel && $0.number == cc
        }) else { return }

        guard let radio else { return }
        dispatch(action: mapping.action, clicks: clicks, vfoStep: mapping.vfoStep, radio: radio)
    }

    // MARK: - Note handler (main thread)

    private func handleNote(channel: Int, note: Int, velocity: Int) {
        if velocity == 0 {
            lastMIDIEvent = "Note Off ch\(channel + 1) #\(note)"
        } else {
            lastMIDIEvent = "Note On ch\(channel + 1) #\(note) vel=\(velocity)"
        }

        // Capture the first non-zero (press) event in learn mode.
        if isLearning && detectedEvent == nil && velocity > 0 {
            detectedEvent = DetectedMIDIEvent(
                kind: .noteOn,
                channel: channel,
                number: note,
                value: velocity,
                sourceName: currentSourceName()
            )
            isLearning = false
            return
        }

        guard let mapping = mappings.first(where: {
            $0.eventKind == .noteOn && $0.channel == channel && $0.number == note
        }) else { return }

        guard let radio else { return }

        // For pttHold: velocity > 0 → press (clicks = 1), velocity = 0 → release (clicks = -1).
        // For all other actions: only fire on press (velocity > 0).
        if velocity == 0 {
            if mapping.action == .pttHold {
                dispatch(action: .pttHold, clicks: -1, vfoStep: mapping.vfoStep, radio: radio)
            }
        } else {
            dispatch(action: mapping.action, clicks: 1, vfoStep: mapping.vfoStep, radio: radio)
        }
    }

    // MARK: - Action dispatch (main thread)

    private func dispatch(action: MIDIAction, clicks: Int, vfoStep: MIDITuningStep, radio: RadioState) {
        switch action {

        case .vfoTune:
            guard let currentHz = radio.vfoAFrequencyHz else { return }
            let delta = clicks * vfoStep.rawValue
            let newHz = max(0, min(currentHz + delta, 999_999_999))
            radio.send(KenwoodCAT.setVFOAFrequencyHz(newHz))

        case .afGain:
            guard let current = radio.afGain else { return }
            let newVal = max(0, min(current + clicks * 10, 255))
            radio.send(KenwoodCAT.setAFGain(newVal))

        case .rfGain:
            guard let current = radio.rfGain else { return }
            let newVal = max(0, min(current + clicks * 10, 255))
            radio.send(KenwoodCAT.setRFGain(newVal))

        case .txPower:
            guard let current = radio.outputPowerWatts else { return }
            let newVal = max(5, min(current + clicks * 5, 100))
            radio.send(KenwoodCAT.setOutputPowerWatts(newVal))

        case .memoryStep:
            guard let current = radio.memoryChannelNumber else { return }
            let newChannel = max(0, min(current + clicks, 119))
            radio.send(KenwoodCAT.setMemoryChannelNumber(newChannel))

        case .pttToggle:
            if radio.isPTTDown {
                radio.send(KenwoodCAT.pttUp())
                radio.isPTTDown = false
            } else {
                radio.send(KenwoodCAT.pttDown())
                radio.isPTTDown = true
            }

        case .pttHold:
            if clicks > 0 {
                radio.send(KenwoodCAT.pttDown())
                radio.isPTTDown = true
            } else {
                radio.send(KenwoodCAT.pttUp())
                radio.isPTTDown = false
            }
        }
    }
}
