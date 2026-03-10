import XCTest
@testable import Kenwood_control

/// Tests for KeyboardBinding value type and KeyboardShortcutsManager data layer.
/// Covers key description formatting, action metadata, and binding CRUD.
/// NSEvent dispatch logic is not exercised here (requires a running app).
final class KeyboardShortcutsTests: XCTestCase {

    private var kb: KeyboardShortcutsManager!
    private var savedBindings: [KeyboardBinding] = []

    override func setUp() {
        super.setUp()
        kb = KeyboardShortcutsManager.shared
        // Snapshot existing bindings and clear so tests start from a known state.
        savedBindings = kb.bindings
        kb.bindings = []
        kb.stopRecording()
    }

    override func tearDown() {
        // Restore bindings to not pollute other tests or the user's saved prefs.
        kb.bindings = savedBindings
        kb.stopRecording()
        kb = nil
        super.tearDown()
    }

    // MARK: - KeyboardBinding.keyDescription — modifier symbols

    func testKeyDescription_noModifiers() {
        let b = binding(.tuneUp, keyCode: 126, modifiers: [])
        XCTAssertEqual(b.keyDescription, "↑")
    }

    func testKeyDescription_optionModifier() {
        let b = binding(.tuneUp, keyCode: 126, modifiers: [.option])
        XCTAssertEqual(b.keyDescription, "⌥↑")
    }

    func testKeyDescription_shiftModifier() {
        let b = binding(.bandUp, keyCode: 126, modifiers: [.shift])
        XCTAssertEqual(b.keyDescription, "⇧↑")
    }

    func testKeyDescription_commandModifier() {
        let b = binding(.modeCW, keyCode: 8, modifiers: [.command])
        XCTAssertEqual(b.keyDescription, "⌘C")
    }

    func testKeyDescription_controlModifier() {
        let b = binding(.modeUSB, keyCode: 14, modifiers: [.control])
        XCTAssertEqual(b.keyDescription, "⌃E")
    }

    func testKeyDescription_multipleModifiers_correctOrder() {
        // Order should always be ⌃⌥⇧⌘ (control, option, shift, command)
        let b = binding(.vfoSwap, keyCode: 0,
                        modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(b.keyDescription, "⌃⌥⇧⌘A")
    }

    func testKeyDescription_optionArrowDown() {
        let b = binding(.tuneDown, keyCode: 125, modifiers: [.option])
        XCTAssertEqual(b.keyDescription, "⌥↓")
    }

    // MARK: - KeyboardBinding.keyCodeLabel — spot checks

    func testKeyCodeLabel_space() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(49), "Space")
    }

    func testKeyCodeLabel_arrowUp() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(126), "↑")
    }

    func testKeyCodeLabel_arrowDown() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(125), "↓")
    }

    func testKeyCodeLabel_arrowLeft() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(123), "←")
    }

    func testKeyCodeLabel_arrowRight() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(124), "→")
    }

    func testKeyCodeLabel_letterA() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(0), "A")
    }

    func testKeyCodeLabel_letterQ() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(12), "Q")
    }

    func testKeyCodeLabel_F1() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(122), "F1")
    }

    func testKeyCodeLabel_F2() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(120), "F2")
    }

    func testKeyCodeLabel_F5() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(96), "F5")
    }

    func testKeyCodeLabel_escape() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(53), "⎋")
    }

    func testKeyCodeLabel_delete() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(51), "⌫")
    }

    func testKeyCodeLabel_tab() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(48), "⇥")
    }

    func testKeyCodeLabel_return() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(36), "↩")
    }

    func testKeyCodeLabel_unknownKeyCode() {
        XCTAssertEqual(KeyboardBinding.keyCodeLabel(200), "(200)")
    }

    // MARK: - KeyboardAction.needsTuneStep

    func testNeedsTuneStep_trueForTuneUp() {
        XCTAssertTrue(KeyboardAction.tuneUp.needsTuneStep)
    }

    func testNeedsTuneStep_trueForTuneDown() {
        XCTAssertTrue(KeyboardAction.tuneDown.needsTuneStep)
    }

    func testNeedsTuneStep_falseForAllOtherActions() {
        let tuneActions: Set<KeyboardAction> = [.tuneUp, .tuneDown]
        for action in KeyboardAction.allCases where !tuneActions.contains(action) {
            XCTAssertFalse(action.needsTuneStep,
                "\(action.rawValue).needsTuneStep should be false")
        }
    }

    // MARK: - KeyboardAction.displayName / actionDescription — non-empty

    func testDisplayName_nonEmptyForAllActions() {
        for action in KeyboardAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty,
                "\(action.rawValue).displayName must not be empty")
        }
    }

    func testActionDescription_nonEmptyForAllActions() {
        for action in KeyboardAction.allCases {
            XCTAssertFalse(action.actionDescription.isEmpty,
                "\(action.rawValue).actionDescription must not be empty")
        }
    }

    // MARK: - KeyboardAction.groups — all actions covered, no duplicates

    func testGroups_containsEveryAction() {
        let allInGroups = KeyboardAction.groups.flatMap(\.actions)
        let missing = Set(KeyboardAction.allCases).subtracting(allInGroups)
        XCTAssertTrue(missing.isEmpty,
            "These actions are missing from groups: \(missing.map(\.rawValue).sorted())")
    }

    func testGroups_noDuplicateActions() {
        let allInGroups = KeyboardAction.groups.flatMap(\.actions)
        XCTAssertEqual(allInGroups.count, Set(allInGroups).count,
            "No action should appear in more than one group")
    }

    func testGroups_titlesNonEmpty() {
        for group in KeyboardAction.groups {
            XCTAssertFalse(group.title.isEmpty)
        }
    }

    // MARK: - Manager: recording state

    func testStartRecording_setsIsRecordingTrue() {
        kb.startRecording(for: .tuneUp)
        XCTAssertTrue(kb.isRecording)
        XCTAssertEqual(kb.recordingAction, .tuneUp)
    }

    func testStartRecording_capturesStep() {
        kb.startRecording(for: .tuneDown, step: .khz10)
        XCTAssertEqual(kb.recordingStep, .khz10)
    }

    func testStopRecording_clearsState() {
        kb.startRecording(for: .vfoSwap)
        kb.stopRecording()
        XCTAssertFalse(kb.isRecording)
        XCTAssertNil(kb.recordingAction)
    }

    func testStartRecording_secondCall_replacesFirst() {
        kb.startRecording(for: .tuneUp)
        kb.startRecording(for: .bandDown)
        XCTAssertEqual(kb.recordingAction, .bandDown,
            "Second startRecording call should replace the first")
    }

    // MARK: - Manager: binding CRUD

    func testClearBinding_removesTargetAction() {
        kb.bindings = [
            binding(.tuneUp,   keyCode: 126, modifiers: [.option]),
            binding(.tuneDown, keyCode: 125, modifiers: [.option]),
        ]
        kb.clearBinding(for: .tuneUp)
        XCTAssertNil(kb.bindings.first(where: { $0.action == .tuneUp }))
    }

    func testClearBinding_leavesOtherActionsIntact() {
        kb.bindings = [
            binding(.tuneUp,   keyCode: 126, modifiers: [.option]),
            binding(.tuneDown, keyCode: 125, modifiers: [.option]),
        ]
        kb.clearBinding(for: .tuneUp)
        XCTAssertEqual(kb.bindings.count, 1)
        XCTAssertEqual(kb.bindings.first?.action, .tuneDown)
    }

    func testClearBinding_onNonExistentAction_doesNotThrow() {
        kb.bindings = []
        kb.clearBinding(for: .macro1)   // should be a no-op
        XCTAssertTrue(kb.bindings.isEmpty)
    }

    func testUpdateStep_changesStepForMatchingAction() {
        kb.bindings = [binding(.tuneUp, keyCode: 126, modifiers: [.option], step: .khz1)]
        kb.updateStep(for: .tuneUp, step: .khz10)
        XCTAssertEqual(kb.bindings.first(where: { $0.action == .tuneUp })?.tuneStep, .khz10)
    }

    func testUpdateStep_preservesKeyCodeAndModifiers() {
        kb.bindings = [binding(.tuneUp, keyCode: 126, modifiers: [.option], step: .khz1)]
        kb.updateStep(for: .tuneUp, step: .hz100)
        let updated = kb.bindings.first(where: { $0.action == .tuneUp })
        XCTAssertEqual(updated?.keyCode, 126)
        XCTAssertEqual(updated?.modifierFlags, [.option])
    }

    func testUpdateStep_onMissingAction_doesNotAddBinding() {
        kb.bindings = []
        kb.updateStep(for: .tuneUp, step: .khz10)
        XCTAssertTrue(kb.bindings.isEmpty,
            "updateStep on a non-existent action must not insert a binding")
    }

    func testUpdateStep_doesNotAffectOtherBindings() {
        kb.bindings = [
            binding(.tuneUp,   keyCode: 126, modifiers: [.option], step: .khz1),
            binding(.tuneDown, keyCode: 125, modifiers: [.option], step: .khz1),
        ]
        kb.updateStep(for: .tuneUp, step: .khz100)
        XCTAssertEqual(kb.bindings.first(where: { $0.action == .tuneDown })?.tuneStep, .khz1,
            "updateStep must not affect other bindings")
    }

    // MARK: - KeyboardBinding Codable round-trip

    func testKeyboardBinding_codableRoundTrip() throws {
        let original = binding(.modeCW, keyCode: 8, modifiers: [.command, .shift], step: .hz10)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyboardBinding.self, from: data)
        XCTAssertEqual(decoded.action,       original.action)
        XCTAssertEqual(decoded.keyCode,      original.keyCode)
        XCTAssertEqual(decoded.modifierMask, original.modifierMask)
        XCTAssertEqual(decoded.tuneStep,     original.tuneStep)
    }

    func testBindingsArray_codableRoundTrip() throws {
        let originals = [
            binding(.tuneUp,   keyCode: 126, modifiers: [.option]),
            binding(.bandDown, keyCode: 125, modifiers: [.shift]),
            binding(.modeCW,   keyCode: 8,   modifiers: [.command]),
        ]
        let data = try JSONEncoder().encode(originals)
        let decoded = try JSONDecoder().decode([KeyboardBinding].self, from: data)
        XCTAssertEqual(decoded.map(\.action), originals.map(\.action))
        XCTAssertEqual(decoded.map(\.keyCode), originals.map(\.keyCode))
    }

    // MARK: - KeyboardBinding.modifierFlags round-trip

    func testModifierFlagsRoundTrip_option() {
        let b = binding(.tuneUp, keyCode: 126, modifiers: [.option])
        XCTAssertTrue(b.modifierFlags.contains(.option))
        XCTAssertFalse(b.modifierFlags.contains(.command))
    }

    func testModifierFlagsRoundTrip_commandShift() {
        let b = binding(.macro1, keyCode: 0, modifiers: [.command, .shift])
        XCTAssertTrue(b.modifierFlags.contains(.command))
        XCTAssertTrue(b.modifierFlags.contains(.shift))
        XCTAssertFalse(b.modifierFlags.contains(.option))
    }

    // MARK: - Helpers

    private func binding(
        _ action: KeyboardAction,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        step: MIDITuningStep = .khz1
    ) -> KeyboardBinding {
        let deviceIndependent: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let maskedMods = modifiers.intersection(deviceIndependent)
        return KeyboardBinding(action: action, keyCode: keyCode,
                               modifierMask: maskedMods.rawValue, tuneStep: step)
    }
}
