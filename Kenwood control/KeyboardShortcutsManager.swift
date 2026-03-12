// KeyboardShortcutsManager.swift
// TS-890 Pro — user-configurable keyboard shortcut system.
//
// Architecture mirrors MIDIController: @Observable singleton with a local
// NSEvent monitor. One binding per action; stored as JSON in UserDefaults.
// Recording mode: set isRecording + recordingAction, then the next non-modifier
// keyDown is captured as the binding for that action.
//
// PTT hold (keyDown = TX on, keyUp = TX off) is supported as an action.
// Option+Space is reserved for PTTKeyMonitor and is rejected during recording.

import Foundation
import AppKit
import Observation

// MARK: - Notification name

extension Notification.Name {
    /// Posted when a panel-open action fires. `object` is the window ID string.
    static let kbOpenPanel = Notification.Name("KenwoodControl.KB.OpenPanel")
}

// MARK: - Assignable actions

enum KeyboardAction: String, CaseIterable, Codable {
    // Tuning
    case tuneUp       = "tuneUp"
    case tuneDown     = "tuneDown"
    // Bands (relative)
    case bandUp       = "bandUp"
    case bandDown     = "bandDown"
    // Bands (direct)
    case band160m     = "band160m"
    case band80m      = "band80m"
    case band40m      = "band40m"
    case band30m      = "band30m"
    case band20m      = "band20m"
    case band17m      = "band17m"
    case band15m      = "band15m"
    case band12m      = "band12m"
    case band10m      = "band10m"
    case band6m       = "band6m"
    // Modes
    case modeLSB      = "modeLSB"
    case modeUSB      = "modeUSB"
    case modeCW       = "modeCW"
    case modeFM       = "modeFM"
    case modeAM       = "modeAM"
    case modeFSK      = "modeFSK"
    // VFO
    case vfoSwap      = "vfoSwap"
    case vfoAtoB      = "vfoAtoB"
    // Functions
    case ritToggle    = "ritToggle"
    case splitToggle  = "splitToggle"
    // Macros
    case macro1       = "macro1"
    case macro2       = "macro2"
    case macro3       = "macro3"
    case macro4       = "macro4"
    // PTT hold: keyDown = TX on, keyUp = TX off
    case pttHold      = "pttHold"
    // Panels
    case openFT8        = "openFT8"
    case openTuning     = "openTuning"
    case openMenuAccess = "openMenuAccess"
    case openFreeDV     = "openFreeDV"

    var displayName: String {
        switch self {
        case .tuneUp:      return "Tune Up"
        case .tuneDown:    return "Tune Down"
        case .bandUp:      return "Band Up"
        case .bandDown:    return "Band Down"
        case .band160m:    return "Band: 160m"
        case .band80m:     return "Band: 80m"
        case .band40m:     return "Band: 40m"
        case .band30m:     return "Band: 30m"
        case .band20m:     return "Band: 20m"
        case .band17m:     return "Band: 17m"
        case .band15m:     return "Band: 15m"
        case .band12m:     return "Band: 12m"
        case .band10m:     return "Band: 10m"
        case .band6m:      return "Band: 6m"
        case .modeLSB:     return "Mode: LSB"
        case .modeUSB:     return "Mode: USB"
        case .modeCW:      return "Mode: CW"
        case .modeFM:      return "Mode: FM"
        case .modeAM:      return "Mode: AM"
        case .modeFSK:     return "Mode: FSK (RTTY)"
        case .vfoSwap:     return "VFO A ↔ B Swap"
        case .vfoAtoB:     return "VFO A → B Copy"
        case .ritToggle:   return "RIT On/Off"
        case .splitToggle: return "Split On/Off"
        case .macro1:      return "Macro 1"
        case .macro2:      return "Macro 2"
        case .macro3:      return "Macro 3"
        case .macro4:      return "Macro 4"
        case .pttHold:     return "PTT (Hold)"
        case .openFT8:        return "Open FT8 Window"
        case .openTuning:     return "Open Tuning Panel"
        case .openMenuAccess: return "Open Menu Access"
        case .openFreeDV:     return "Open FreeDV Window"
        }
    }

    var actionDescription: String {
        switch self {
        case .tuneUp:      return "Steps VFO A up by the configured step size."
        case .tuneDown:    return "Steps VFO A down by the configured step size."
        case .bandUp:      return "Switches to the next higher amateur band."
        case .bandDown:    return "Switches to the next lower amateur band."
        case .band160m, .band80m, .band40m, .band30m, .band20m,
             .band17m, .band15m, .band12m, .band10m, .band6m:
            return "Jumps directly to this band, restoring the last used frequency."
        case .modeLSB:     return "Sets operating mode to LSB."
        case .modeUSB:     return "Sets operating mode to USB."
        case .modeCW:      return "Sets operating mode to CW."
        case .modeFM:      return "Sets operating mode to FM."
        case .modeAM:      return "Sets operating mode to AM."
        case .modeFSK:     return "Sets operating mode to FSK (RTTY)."
        case .vfoSwap:     return "Swaps VFO A and VFO B frequencies."
        case .vfoAtoB:     return "Copies VFO A frequency to VFO B."
        case .ritToggle:   return "Toggles RIT (Receive Incremental Tuning) on or off."
        case .splitToggle: return "Toggles split TX (VFO B) on or off."
        case .macro1:      return "Sends the Macro 1 CAT string configured below."
        case .macro2:      return "Sends the Macro 2 CAT string configured below."
        case .macro3:      return "Sends the Macro 3 CAT string configured below."
        case .macro4:      return "Sends the Macro 4 CAT string configured below."
        case .pttHold:     return "Transmits while key is held; returns to receive on release."
        case .openFT8:        return "Opens the FT8 / digital modes window."
        case .openTuning:     return "Opens the Tuning Panel window."
        case .openMenuAccess: return "Opens the Menu Access window."
        case .openFreeDV:     return "Opens the FreeDV window."
        }
    }

    var needsTuneStep: Bool {
        self == .tuneUp || self == .tuneDown
    }

    /// True for actions that open a window rather than control the radio.
    var isPanelAction: Bool {
        switch self {
        case .openFT8, .openTuning, .openMenuAccess, .openFreeDV: return true
        default: return false
        }
    }

    /// The SwiftUI window ID string for panel actions.
    var panelWindowID: String? {
        switch self {
        case .openFT8:        return "ft8"
        case .openTuning:     return "tuning"
        case .openMenuAccess: return "menuAccess"
        case .openFreeDV:     return "freedv"
        default:              return nil
        }
    }

    // Groups for organised display in the UI
    static var groups: [(title: String, actions: [KeyboardAction])] {
        [
            ("Tuning",       [.tuneUp, .tuneDown, .bandUp, .bandDown]),
            ("Bands",        [.band160m, .band80m, .band40m, .band30m, .band20m,
                              .band17m, .band15m, .band12m, .band10m, .band6m]),
            ("Modes",        [.modeLSB, .modeUSB, .modeCW, .modeFM, .modeAM, .modeFSK]),
            ("VFO",          [.vfoSwap, .vfoAtoB]),
            ("Functions",    [.ritToggle, .splitToggle, .pttHold]),
            ("Macros",       [.macro1, .macro2, .macro3, .macro4]),
            ("Panels",       [.openFT8, .openTuning, .openMenuAccess, .openFreeDV]),
        ]
    }
}

// MARK: - Binding

struct KeyboardBinding: Identifiable, Codable {
    var id: UUID = UUID()
    var action: KeyboardAction
    var keyCode: UInt16
    var modifierMask: UInt          // NSEvent.ModifierFlags device-independent rawValue
    var tuneStep: MIDITuningStep    // only meaningful for tuneUp / tuneDown

    init(action: KeyboardAction, keyCode: UInt16, modifierMask: UInt,
         tuneStep: MIDITuningStep = .khz1) {
        self.id          = UUID()
        self.action      = action
        self.keyCode     = keyCode
        self.modifierMask = modifierMask
        self.tuneStep    = tuneStep
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierMask)
    }

    /// Human-readable description, e.g. "⌥↑" or "⌃⌘F".
    var keyDescription: String {
        var s = ""
        let mods = modifierFlags
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += KeyboardBinding.keyCodeLabel(keyCode)
        return s
    }

    // swiftlint:disable cyclomatic_complexity
    static func keyCodeLabel(_ kc: UInt16) -> String {
        switch kc {
        case 0:   return "A";  case 1:  return "S";  case 2:  return "D"
        case 3:   return "F";  case 4:  return "H";  case 5:  return "G"
        case 6:   return "Z";  case 7:  return "X";  case 8:  return "C"
        case 9:   return "V";  case 11: return "B";  case 12: return "Q"
        case 13:  return "W";  case 14: return "E";  case 15: return "R"
        case 16:  return "Y";  case 17: return "T";  case 18: return "1"
        case 19:  return "2";  case 20: return "3";  case 21: return "4"
        case 22:  return "6";  case 23: return "5";  case 24: return "="
        case 25:  return "9";  case 26: return "7";  case 27: return "−"
        case 28:  return "8";  case 29: return "0";  case 30: return "]"
        case 31:  return "O";  case 32: return "U";  case 33: return "["
        case 34:  return "I";  case 35: return "P";  case 36: return "↩"
        case 37:  return "L";  case 38: return "J";  case 39: return "'"
        case 40:  return "K";  case 41: return ";";  case 42: return "\\"
        case 43:  return ",";  case 44: return "/";  case 45: return "N"
        case 46:  return "M";  case 47: return ".";  case 48: return "⇥"
        case 49:  return "Space"
        case 50:  return "`";  case 51: return "⌫";  case 53: return "⎋"
        case 96:  return "F5"; case 97: return "F6"; case 98: return "F7"
        case 99:  return "F3"; case 100: return "F8"; case 101: return "F9"
        case 103: return "F11"; case 105: return "F13"; case 107: return "F14"
        case 109: return "F10"; case 111: return "F12"; case 113: return "F15"
        case 114: return "Ins"; case 115: return "↖"; case 116: return "⇞"
        case 117: return "⌦"; case 118: return "F4"; case 119: return "↘"
        case 120: return "F2"; case 121: return "⇟"; case 122: return "F1"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"
        case 126: return "↑"
        default:  return "(\(kc))"
        }
    }
    // swiftlint:enable cyclomatic_complexity
}

// MARK: - Manager

@Observable
final class KeyboardShortcutsManager {

    static let shared = KeyboardShortcutsManager()

    // MARK: Published

    var bindings: [KeyboardBinding] = []

    /// True while waiting for a key press to record a new binding.
    var isRecording: Bool = false
    /// Which action the in-progress recording will be assigned to.
    var recordingAction: KeyboardAction?
    /// Step size for the pending tuneUp/tuneDown recording.
    var recordingStep: MIDITuningStep = .khz1

    /// Four user-defined raw CAT strings sent by macro actions.
    var macro1String: String = UserDefaults.standard.string(forKey: "KBMacro1") ?? ""
    var macro2String: String = UserDefaults.standard.string(forKey: "KBMacro2") ?? ""
    var macro3String: String = UserDefaults.standard.string(forKey: "KBMacro3") ?? ""
    var macro4String: String = UserDefaults.standard.string(forKey: "KBMacro4") ?? ""

    weak var radio: RadioState?

    // MARK: Private

    private var monitor: Any?
    /// Key code currently held down for pttHold, nil = not transmitting.
    private var pttHoldKeyCode: UInt16?

    private let kBindings = "KB.Bindings"

    // Band table — index order used for bandUp/bandDown cycling.
    // Frequency ranges and defaults match FrontPanelView.bands / bandRanges.
    private static let bandTable: [(label: String, defaultHz: Int, range: ClosedRange<Int>)] = [
        ("160m",  1_800_000,  1_800_000...2_000_000),
        ("80m",   3_500_000,  3_500_000...4_000_000),
        ("60m",   5_330_500,  5_330_500...5_406_400),
        ("40m",   7_000_000,  7_000_000...7_300_000),
        ("30m",  10_100_000, 10_100_000...10_150_000),
        ("20m",  14_000_000, 14_000_000...14_350_000),
        ("17m",  18_068_000, 18_068_000...18_168_000),
        ("15m",  21_000_000, 21_000_000...21_450_000),
        ("12m",  24_890_000, 24_890_000...24_990_000),
        ("10m",  28_000_000, 28_000_000...29_700_000),
        ("6m",   50_000_000, 50_000_000...54_000_000),
    ]

    private static let deviceIndependentMask: NSEvent.ModifierFlags =
        [.control, .option, .shift, .command]

    // MARK: Init

    private init() {
        loadBindings()
        installMonitor()
    }

    // MARK: - NSEvent monitor

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(Self.deviceIndependentMask)

        // ── Recording mode ──────────────────────────────────────────────────
        if isRecording, let action = recordingAction, event.type == .keyDown {
            // Escape cancels without saving.
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            // Option+Space is reserved for PTTKeyMonitor.
            if event.keyCode == 49 && mods.contains(.option) {
                return event
            }
            let binding = KeyboardBinding(
                action:       action,
                keyCode:      event.keyCode,
                modifierMask: mods.rawValue,
                tuneStep:     recordingStep
            )
            DispatchQueue.main.async {
                self.commitBinding(binding)
                self.isRecording = false
                self.recordingAction = nil
            }
            return nil
        }

        guard !isRecording else { return event }

        // ── Normal dispatch ─────────────────────────────────────────────────
        if event.type == .keyDown {
            guard let binding = bindings.first(where: {
                $0.keyCode == event.keyCode &&
                NSEvent.ModifierFlags(rawValue: $0.modifierMask) == mods
            }) else { return event }

            if binding.action == .pttHold {
                guard pttHoldKeyCode == nil else { return nil }
                radio?.setPTT(down: true)
                pttHoldKeyCode = event.keyCode
                return nil
            }

            // Panel actions don't need a radio — they just open a window.
            if binding.action.isPanelAction, let windowID = binding.action.panelWindowID {
                NotificationCenter.default.post(name: .kbOpenPanel, object: windowID)
                return nil
            }

            guard let radio else { return event }
            dispatch(action: binding.action, tuneStep: binding.tuneStep, radio: radio)
            return nil
        }

        if event.type == .keyUp {
            if let held = pttHoldKeyCode, event.keyCode == held {
                radio?.setPTT(down: false)
                pttHoldKeyCode = nil
                return nil
            }
        }

        return event
    }

    // MARK: - Action dispatch

    private func dispatch(action: KeyboardAction, tuneStep: MIDITuningStep, radio: RadioState) {
        switch action {

        case .tuneUp:
            guard let hz = radio.vfoAFrequencyHz else { return }
            radio.send(KenwoodCAT.setVFOAFrequencyHz(max(0, min(hz + tuneStep.rawValue, 999_999_999))))

        case .tuneDown:
            guard let hz = radio.vfoAFrequencyHz else { return }
            radio.send(KenwoodCAT.setVFOAFrequencyHz(max(0, min(hz - tuneStep.rawValue, 999_999_999))))

        case .bandUp:
            guard let hz = radio.vfoAFrequencyHz else { return }
            let idx  = Self.bandTable.firstIndex(where: { $0.range.contains(hz) }) ?? -1
            let next = min(idx + 1, Self.bandTable.count - 1)
            if next >= 0 { switchToBand(Self.bandTable[next], radio: radio) }

        case .bandDown:
            guard let hz = radio.vfoAFrequencyHz else { return }
            let idx  = Self.bandTable.firstIndex(where: { $0.range.contains(hz) }) ?? Self.bandTable.count
            let prev = max(idx - 1, 0)
            switchToBand(Self.bandTable[prev], radio: radio)

        case .band160m: switchToBandLabel("160m", radio: radio)
        case .band80m:  switchToBandLabel("80m",  radio: radio)
        case .band40m:  switchToBandLabel("40m",  radio: radio)
        case .band30m:  switchToBandLabel("30m",  radio: radio)
        case .band20m:  switchToBandLabel("20m",  radio: radio)
        case .band17m:  switchToBandLabel("17m",  radio: radio)
        case .band15m:  switchToBandLabel("15m",  radio: radio)
        case .band12m:  switchToBandLabel("12m",  radio: radio)
        case .band10m:  switchToBandLabel("10m",  radio: radio)
        case .band6m:   switchToBandLabel("6m",   radio: radio)

        case .modeLSB: radio.send(KenwoodCAT.setOperatingMode(.lsb))
        case .modeUSB: radio.send(KenwoodCAT.setOperatingMode(.usb))
        case .modeCW:  radio.send(KenwoodCAT.setOperatingMode(.cw))
        case .modeFM:  radio.send(KenwoodCAT.setOperatingMode(.fm))
        case .modeAM:  radio.send(KenwoodCAT.setOperatingMode(.am))
        case .modeFSK: radio.send(KenwoodCAT.setOperatingMode(.fsk))

        case .vfoSwap: radio.send("SV;")
        case .vfoAtoB: radio.send("VV;")

        case .ritToggle:
            radio.send(KenwoodCAT.ritSetEnabled(!(radio.ritEnabled ?? false)))

        case .splitToggle:
            let splitActive = radio.txVFO == .b
            radio.send(KenwoodCAT.setTransmitterVFO(splitActive ? .a : .b))

        case .macro1: sendMacro(macro1String, radio: radio)
        case .macro2: sendMacro(macro2String, radio: radio)
        case .macro3: sendMacro(macro3String, radio: radio)
        case .macro4: sendMacro(macro4String, radio: radio)

        case .pttHold: break  // handled via keyDown/keyUp in handleEvent
        case .openFT8, .openTuning, .openMenuAccess, .openFreeDV: break  // handled via notification in handleEvent
        }
    }

    // MARK: - Band helpers

    private func switchToBandLabel(_ label: String, radio: RadioState) {
        guard let entry = Self.bandTable.first(where: { $0.label == label }) else { return }
        switchToBand(entry, radio: radio)
    }

    private func switchToBand(
        _ entry: (label: String, defaultHz: Int, range: ClosedRange<Int>),
        radio: RadioState
    ) {
        // Persist current VFO A frequency under the current band key so coming back restores it.
        // This uses the same UserDefaults key format as FrontPanelView.switchBand() so they share state.
        if let hz = radio.vfoAFrequencyHz,
           let cur = Self.bandTable.first(where: { $0.range.contains(hz) }) {
            UserDefaults.standard.set(hz, forKey: "bandFreq_A_\(cur.label)")
        }
        let stored = UserDefaults.standard.integer(forKey: "bandFreq_A_\(entry.label)")
        let target = stored > 0 ? stored : entry.defaultHz
        radio.send(KenwoodCAT.setVFOAFrequencyHz(target))
    }

    private func sendMacro(_ text: String, radio: RadioState) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        radio.send(s)
    }

    // MARK: - Recording control

    func startRecording(for action: KeyboardAction, step: MIDITuningStep = .khz1) {
        recordingAction = action
        recordingStep   = step
        isRecording     = true
    }

    func stopRecording() {
        isRecording     = false
        recordingAction = nil
    }

    // MARK: - Binding management

    private func commitBinding(_ binding: KeyboardBinding) {
        // One binding per action — replace any existing.
        bindings.removeAll(where: { $0.action == binding.action })
        bindings.append(binding)
        saveBindings()
    }

    func clearBinding(for action: KeyboardAction) {
        bindings.removeAll(where: { $0.action == action })
        saveBindings()
    }

    /// Update only the tune step for an existing binding, keeping its key combination.
    func updateStep(for action: KeyboardAction, step: MIDITuningStep) {
        guard let idx = bindings.firstIndex(where: { $0.action == action }) else { return }
        bindings[idx] = KeyboardBinding(
            action:       bindings[idx].action,
            keyCode:      bindings[idx].keyCode,
            modifierMask: bindings[idx].modifierMask,
            tuneStep:     step
        )
        saveBindings()
    }

    func saveMacros() {
        UserDefaults.standard.set(macro1String, forKey: "KBMacro1")
        UserDefaults.standard.set(macro2String, forKey: "KBMacro2")
        UserDefaults.standard.set(macro3String, forKey: "KBMacro3")
        UserDefaults.standard.set(macro4String, forKey: "KBMacro4")
    }

    // MARK: - Persistence

    private func saveBindings() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: kBindings)
    }

    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: kBindings),
              let loaded = try? JSONDecoder().decode([KeyboardBinding].self, from: data)
        else { return }
        bindings = loaded
    }
}
