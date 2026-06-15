//
//  TuningPreferences.swift
//  Kenwood control
//
//  Shared, persistent tuning-step preference for the front-panel Up/Down
//  buttons and the .cycleVfoStep MIDI button action. Independent of the
//  per-mapping step on MIDI knob mappings (those keep their own value).
//

import Foundation
import Observation
import AppKit

@Observable
final class TuningPreferences {

    static let shared = TuningPreferences()

    private let kFrontPanelStepHz = "FrontPanel.TuneStep.Hz"

    /// Current step size used by the front-panel tune buttons and the
    /// .cycleVfoStep MIDI action. Persists to UserDefaults on change.
    var step: MIDITuningStep {
        didSet {
            guard step != oldValue else { return }
            UserDefaults.standard.set(step.rawValue, forKey: kFrontPanelStepHz)
        }
    }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: kFrontPanelStepHz)
        self.step = MIDITuningStep(rawValue: saved) ?? .khz1
    }

    /// Advance to the next-larger step, wrapping from 1 MHz back to 1 Hz.
    /// Posts a VoiceOver announcement so the user hears the new size when
    /// triggered from a MIDI button.
    func cycleStepUp() {
        let all = MIDITuningStep.allCases
        guard let idx = all.firstIndex(of: step) else { return }
        step = all[(idx + 1) % all.count]
        announce()
    }

    /// Step down to the next-smaller size, wrapping from 1 Hz back to 1 MHz.
    func cycleStepDown() {
        let all = MIDITuningStep.allCases
        guard let idx = all.firstIndex(of: step) else { return }
        step = all[(idx + all.count - 1) % all.count]
        announce()
    }

    private func announce() {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: "Tuning step \(step.label)",
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high,
            ]
        )
    }
}
