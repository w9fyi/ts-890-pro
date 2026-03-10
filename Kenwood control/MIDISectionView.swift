//
//  MIDISectionView.swift
//  Kenwood control
//
//  MIDI controller setup with interactive learn mode.
//
//  Flow:
//   1. User connects a MIDI source (auto-detected or picked from list).
//   2. "Add Mapping" opens the learn sheet.
//   3. Sheet listens for the first MIDI event; announces what was detected.
//   4. User selects an action from a list; optionally configures step size.
//   5. Mapping is saved and appears in the Assigned Controls list.
//   6. Any mapping can be tapped to reassign or deleted with the trash button.
//
//  Fully accessible with VoiceOver — all interactive elements have labels,
//  hints, and traits; the learn sheet announces detected controls.
//

import SwiftUI
import CoreMIDI

// MARK: - Main section view

struct MIDISectionView: View {
    var radio: RadioState
    @Bindable private var midi = MIDIController.shared
    @State private var showLearnSheet = false
    @State private var reassignMapping: MIDIMapping?   // non-nil → reassign flow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("MIDI Controller")
                    .font(.title2)

                Text("Connect a MIDI controller to control the radio without touching the keyboard. Press \"Add Mapping\" to assign a knob or button to a radio function.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // MARK: Connection status
                HStack(spacing: 8) {
                    Circle()
                        .fill(midi.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(midi.isConnected ? "MIDI Connected" : "MIDI Not Connected")
                        .fontWeight(.medium)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(midi.isConnected ? "MIDI status: connected" : "MIDI status: not connected")

                // MARK: Source picker
                GroupBox("MIDI Source") {
                    VStack(alignment: .leading, spacing: 10) {
                        if midi.availableSources.isEmpty {
                            Text("No MIDI sources found. Connect a controller and press Refresh.")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } else {
                            Picker("MIDI Source", selection: $midi.selectedSourceRef) {
                                Text("(none)").tag(MIDIEndpointRef(0))
                                ForEach(midi.availableSources) { src in
                                    Text(src.name).tag(src.id)
                                }
                            }
                            .accessibilityLabel("MIDI input source")
                            .onChange(of: midi.selectedSourceRef) { _, newRef in
                                if newRef == 0 {
                                    midi.disconnect()
                                } else {
                                    midi.connect(to: newRef)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Refresh Sources") {
                                midi.refreshSources()
                            }
                            .accessibilityHint("Scans for newly connected MIDI devices")

                            if midi.isConnected {
                                Button("Disconnect") {
                                    midi.disconnect()
                                }
                                .accessibilityHint("Disconnects the current MIDI source")
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // MARK: Assigned controls list
                GroupBox("Assigned Controls") {
                    VStack(alignment: .leading, spacing: 0) {
                        if midi.mappings.isEmpty {
                            Text("No controls assigned yet.")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(midi.mappings) { mapping in
                                MappingRow(mapping: mapping) {
                                    // Tap → reassign
                                    reassignMapping = mapping
                                    midi.startLearning()
                                    showLearnSheet = true
                                } onDelete: {
                                    midi.removeMapping(id: mapping.id)
                                }
                                if mapping.id != midi.mappings.last?.id {
                                    Divider()
                                }
                            }
                        }

                        Button("Add Mapping") {
                            reassignMapping = nil
                            midi.startLearning()
                            showLearnSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                        .accessibilityHint("Opens the learn sheet — press a button or turn a knob on your controller to assign it")
                    }
                    .padding(.top, 4)
                }

                // MARK: Live event monitor (diagnostic)
                GroupBox("Last MIDI Event") {
                    Text(midi.lastMIDIEvent.isEmpty
                         ? "(none yet — interact with your controller to test)"
                         : midi.lastMIDIEvent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(midi.lastMIDIEvent.isEmpty ? .secondary : .primary)
                        .accessibilityLabel(
                            midi.lastMIDIEvent.isEmpty
                                ? "No MIDI events received yet"
                                : "Last MIDI event: \(midi.lastMIDIEvent)"
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear {
            midi.radio = radio
            midi.refreshSources()
        }
        .sheet(isPresented: $showLearnSheet, onDismiss: {
            midi.stopLearning()
            reassignMapping = nil
        }) {
            MIDILearnSheet(
                midi: midi,
                replacingID: reassignMapping?.id,
                isPresented: $showLearnSheet
            )
        }
    }
}

// MARK: - Mapping list row

private struct MappingRow: View {
    let mapping: MIDIMapping
    let onReassign: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tap the label area to reassign
            Button(action: onReassign) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mapping.action.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(mapping.controlDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mapping.action == .vfoTune {
                        Text("Step: \(mapping.vfoStep.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mapping.accessibilityRowLabel)
            .accessibilityHint("Tap to reassign this control to a different action")

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Remove \(mapping.action.displayName) mapping")
            .accessibilityHint("Removes the assignment for \(mapping.controlDescription)")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Learn sheet

struct MIDILearnSheet: View {
    @Bindable var midi: MIDIController
    /// When non-nil, saving this mapping replaces the existing one with this ID.
    let replacingID: UUID?
    @Binding var isPresented: Bool

    @State private var selectedAction: MIDIAction?
    @State private var selectedStep: MIDITuningStep = .khz1

    private var isReassign: Bool { replacingID != nil }

    var body: some View {
        NavigationStack {
            Form {
                detectSection
                if let event = midi.detectedEvent {
                    actionPickerSection(event: event)
                    if selectedAction == .vfoTune {
                        stepPickerSection
                    }
                }
            }
            .navigationTitle(isReassign ? "Reassign Control" : "Add Mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                if midi.detectedEvent != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveMapping()
                        }
                        .disabled(selectedAction == nil)
                        .accessibilityHint(selectedAction == nil ? "Select an action first" : "Saves this mapping")
                    }
                }
            }
        }
        // Pre-fill step size if reassigning
        .onAppear {
            if let id = replacingID,
               let existing = midi.mappings.first(where: { $0.id == id }) {
                selectedAction = existing.action
                selectedStep = existing.vfoStep
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var detectSection: some View {
        if let event = midi.detectedEvent {
            Section("Detected Control") {
                Text(event.humanDescription)
                    .font(.body)
                    .accessibilityAddTraits(.isHeader)
            }
        } else {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for input…")
                }
                Text("Press a button or turn a knob on your MIDI controller.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Learning")
            }
        }
    }

    @ViewBuilder
    private func actionPickerSection(event: DetectedMIDIEvent) -> some View {
        Section("Assign to Action") {
            ForEach(MIDIAction.allCases, id: \.self) { action in
                ActionPickerRow(
                    action: action,
                    isSelected: selectedAction == action
                ) {
                    selectedAction = action
                }
            }
        }
    }

    @ViewBuilder
    private var stepPickerSection: some View {
        Section("Tuning Step Per Click") {
            ForEach(MIDITuningStep.allCases) { step in
                StepPickerRow(step: step, isSelected: selectedStep == step) {
                    selectedStep = step
                }
            }
        }
    }

    // MARK: Save

    private func saveMapping() {
        guard let event = midi.detectedEvent, let action = selectedAction else { return }

        // Remove the old mapping if reassigning.
        if let id = replacingID {
            midi.removeMapping(id: id)
        }

        midi.addMapping(event: event, action: action, vfoStep: selectedStep)
        isPresented = false
    }
}

// MARK: - Action picker row

private struct ActionPickerRow: View {
    let action: MIDIAction
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.displayName)
                    .font(.body)
                Text(action.actionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.displayName). \(action.actionDescription)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this action")
    }
}

// MARK: - Step picker row

private struct StepPickerRow: View {
    let step: MIDITuningStep
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            Text(step.label)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(step.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
    }
}
