// KeyboardShortcutsSectionView.swift
// TS-890 Pro — Settings tab for user-configurable keyboard shortcuts.
//
// Layout:
//   • Actions grouped by category (Tuning, Bands, Modes, …).
//     Each row shows the action name, current key binding (or "—"), and
//     a Record / Clear button pair.
//   • While recording, the row shows "Press a key… (Esc to cancel)".
//   • tuneUp/tuneDown rows also show a step-size picker after the key is set.
//   • A Macros section at the bottom has four text fields for raw CAT strings.
//   • All controls have explicit accessibilityLabel/hint for VoiceOver.

import SwiftUI

struct KeyboardShortcutsSectionView: View {
    var radio: RadioState
    @Bindable private var kb = KeyboardShortcutsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                headerText

                // Action groups
                ForEach(KeyboardAction.groups, id: \.title) { group in
                    GroupBox(group.title) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(group.actions, id: \.self) { action in
                                ActionBindingRow(action: action, kb: kb)
                                if action != group.actions.last {
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // Macros
                macrosSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear { kb.radio = radio }
        .onDisappear { kb.stopRecording() }
    }

    // MARK: - Header

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard Shortcuts")
                .font(.title2)
            Text("Assign a key combination to each radio action. Click Record, then press the key you want. Option+Space is reserved for Push-to-Talk hold.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Macros section

    private var macrosSection: some View {
        GroupBox("Macros — CAT Strings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter a raw CAT command for each macro slot. Example: KY HELLO; or MD1;")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                macroField(label: "Macro 1", text: $kb.macro1String,
                           hint: "CAT string sent when Macro 1 key is pressed")
                macroField(label: "Macro 2", text: $kb.macro2String,
                           hint: "CAT string sent when Macro 2 key is pressed")
                macroField(label: "Macro 3", text: $kb.macro3String,
                           hint: "CAT string sent when Macro 3 key is pressed")
                macroField(label: "Macro 4", text: $kb.macro4String,
                           hint: "CAT string sent when Macro 4 key is pressed")

                Button("Save Macros") { kb.saveMacros() }
                    .accessibilityHint("Saves all four macro CAT strings to disk")
            }
            .padding(.top, 4)
        }
    }

    private func macroField(label: String, text: Binding<String>, hint: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 64, alignment: .leading)
                .accessibilityHidden(true)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(label)
                .accessibilityHint(hint)
        }
    }
}

// MARK: - Action binding row

private struct ActionBindingRow: View {
    let action: KeyboardAction
    @Bindable var kb: KeyboardShortcutsManager

    private var binding: KeyboardBinding? {
        kb.bindings.first(where: { $0.action == action })
    }

    private var isRecordingThis: Bool {
        kb.isRecording && kb.recordingAction == action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Action label + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displayName)
                        .font(.body)
                    Text(action.actionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Current binding display
                keyBadge

                // Record / Clear buttons
                recordButton
                if binding != nil {
                    clearButton
                }
            }
            .padding(.vertical, 8)

            // Tune step picker — shown inline when a tuneUp/tuneDown binding exists
            if action.needsTuneStep, let b = binding, !isRecordingThis {
                tuneStepPicker(for: b)
                    .padding(.bottom, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint(isRecordingThis
            ? "Press any key combination to assign it. Press Escape to cancel."
            : (binding == nil
                ? "No key assigned. Activate Record to assign one."
                : "Key assigned: \(binding!.keyDescription). Activate Record to reassign."))
    }

    // MARK: Sub-views

    @ViewBuilder
    private var keyBadge: some View {
        if isRecordingThis {
            Text("Press a key… (Esc cancels)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
        } else if let b = binding {
            Text(b.keyDescription)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
        } else {
            Text("—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var recordButton: some View {
        Button(isRecordingThis ? "Cancel" : (binding == nil ? "Record" : "Reassign")) {
            if isRecordingThis {
                kb.stopRecording()
            } else {
                // Stop any other in-progress recording first.
                kb.stopRecording()
                kb.startRecording(for: action, step: binding?.tuneStep ?? .khz1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(isRecordingThis
            ? "Cancel recording for \(action.displayName)"
            : (binding == nil
                ? "Record shortcut for \(action.displayName)"
                : "Reassign shortcut for \(action.displayName)"))
    }

    @ViewBuilder
    private var clearButton: some View {
        Button(role: .destructive) {
            kb.clearBinding(for: action)
        } label: {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .accessibilityLabel("Clear shortcut for \(action.displayName)")
        .accessibilityHint("Removes the assigned key combination")
    }

    @ViewBuilder
    private func tuneStepPicker(for b: KeyboardBinding) -> some View {
        HStack(spacing: 8) {
            Text("Step:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Step size for \(action.displayName)", selection: stepBinding) {
                ForEach(MIDITuningStep.allCases) { step in
                    Text(step.label).tag(step)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .accessibilityLabel("Tune step for \(action.displayName)")
            .accessibilityHint("How far VFO A moves each time this key is pressed")
        }
    }

    /// Binding that reads/writes the tuneStep of the existing binding in-place and persists.
    private var stepBinding: Binding<MIDITuningStep> {
        Binding(
            get: { binding?.tuneStep ?? .khz1 },
            set: { newStep in
                guard let b = binding else { return }
                kb.updateStep(for: b.action, step: newStep)
            }
        )
    }

    private var rowAccessibilityLabel: String {
        var label = action.displayName
        if isRecordingThis {
            label += ", recording — press a key combination"
        } else if let b = binding {
            label += ", assigned to \(b.keyDescription)"
            if action.needsTuneStep { label += ", step \(b.tuneStep.label)" }
        } else {
            label += ", not assigned"
        }
        return label
    }
}
