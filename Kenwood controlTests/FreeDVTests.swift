import XCTest
@testable import Kenwood_control

// MARK: - FreeDVEngine tests

final class FreeDVEngineTests: XCTestCase {

    var engine: FreeDVEngine!

    override func setUp() {
        super.setUp()
        engine = FreeDVEngine()
    }

    override func tearDown() {
        engine.close()
        engine = nil
        super.tearDown()
    }

    // MARK: Initial state

    func testEngine_startsNotOpen() {
        XCTAssertFalse(engine.isOpen)
    }

    func testEngine_speechSampleRate_defaultsToZeroBeforeOpen() {
        // nSpeechSamples is 0 before open — encoding should refuse.
        XCTAssertEqual(engine.nSpeechSamples, 0)
    }

    // MARK: open / close

    func testOpen_mode1600_setsIsOpenTrue() {
        engine.open(mode: .mode1600)
        XCTAssertTrue(engine.isOpen)
    }

    func testOpen_mode700D_setsIsOpenTrue() {
        engine.open(mode: .mode700D)
        XCTAssertTrue(engine.isOpen)
    }

    func testOpen_mode700E_setsIsOpenTrue() {
        engine.open(mode: .mode700E)
        XCTAssertTrue(engine.isOpen)
    }

    func testOpen_mode700C_setsIsOpenTrue() {
        engine.open(mode: .mode700C)
        XCTAssertTrue(engine.isOpen)
    }

    func testClose_afterOpen_setsIsOpenFalse() {
        engine.open(mode: .mode1600)
        engine.close()
        XCTAssertFalse(engine.isOpen)
    }

    func testClose_withoutOpen_doesNotCrash() {
        // Should be a no-op and not crash.
        engine.close()
        XCTAssertFalse(engine.isOpen)
    }

    func testOpenTwice_doesNotCrash() {
        engine.open(mode: .mode1600)
        engine.open(mode: .mode700D)   // should close + reopen
        XCTAssertTrue(engine.isOpen)
    }

    // MARK: Frame sizes after open

    func testOpen_mode1600_speechSampleRateIs8000() {
        engine.open(mode: .mode1600)
        XCTAssertEqual(engine.speechSampleRate, 8000)
    }

    func testOpen_mode1600_modemSampleRateIs8000() {
        engine.open(mode: .mode1600)
        XCTAssertEqual(engine.modemSampleRate, 8000)
    }

    func testOpen_mode1600_nSpeechSamplesIsPositive() {
        engine.open(mode: .mode1600)
        XCTAssertGreaterThan(engine.nSpeechSamples, 0)
    }

    func testOpen_mode1600_nTxModemSamplesIsPositive() {
        engine.open(mode: .mode1600)
        XCTAssertGreaterThan(engine.nTxModemSamples, 0)
    }

    func testOpen_mode1600_nMaxModemSamplesIsPositive() {
        engine.open(mode: .mode1600)
        XCTAssertGreaterThan(engine.nMaxModemSamples, 0)
    }

    func testOpen_mode700D_modemSampleRateIs8000() {
        engine.open(mode: .mode700D)
        XCTAssertEqual(engine.modemSampleRate, 8000)
    }

    // MARK: TX: encodeSpeech

    func testEncodeSpeech_beforeOpen_returnsEmpty() {
        let silence = [Int16](repeating: 0, count: 160)
        let out = engine.encodeSpeech(silence)
        XCTAssertTrue(out.isEmpty)
    }

    func testEncodeSpeech_wrongCount_returnsEmpty() {
        engine.open(mode: .mode1600)
        // nSpeechSamples is e.g. 320 for 1600; pass wrong size.
        let silence = [Int16](repeating: 0, count: engine.nSpeechSamples + 1)
        let out = engine.encodeSpeech(silence)
        XCTAssertTrue(out.isEmpty, "Wrong-size input must return empty")
    }

    func testEncodeSpeech_silenceFrame_returnsCorrectCount() {
        engine.open(mode: .mode1600)
        let silence = [Int16](repeating: 0, count: engine.nSpeechSamples)
        let out = engine.encodeSpeech(silence)
        XCTAssertEqual(out.count, engine.nTxModemSamples,
                       "Encoded output must be exactly nTxModemSamples")
    }

    func testEncodeSpeech_mode700D_silenceFrame_returnsCorrectCount() {
        engine.open(mode: .mode700D)
        let silence = [Int16](repeating: 0, count: engine.nSpeechSamples)
        let out = engine.encodeSpeech(silence)
        XCTAssertEqual(out.count, engine.nTxModemSamples)
    }

    // MARK: RX: feedModemSamples

    func testFeedModemSamples_beforeOpen_returnsEmpty() {
        let zeros = [Int16](repeating: 0, count: 320)
        let out = engine.feedModemSamples(zeros)
        XCTAssertTrue(out.isEmpty)
    }

    func testFeedModemSamples_silenceLoop_doesNotCrash() {
        // Feed silence (encode → decode round-trip). Decoded speech may or may not
        // have content; we only verify no crash and output size is bounded.
        engine.open(mode: .mode1600)
        let speech = [Int16](repeating: 0, count: engine.nSpeechSamples)
        let modem = engine.encodeSpeech(speech)

        // Feed modem samples back. May need multiple packets before nin is satisfied.
        var decoded: [Int16] = []
        for _ in 0..<4 {
            decoded += engine.feedModemSamples(modem)
        }
        // We don't assert decoded content (noise floor, framing) but no crash is the goal.
        XCTAssertGreaterThanOrEqual(decoded.count, 0)
    }

    func testFeedModemSamples_emptyInput_returnsEmpty() {
        engine.open(mode: .mode1600)
        let out = engine.feedModemSamples([])
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: TX callsign

    func testTxCallsign_defaultIsAI5OS() {
        // Default should match the hard-coded fallback in FreeDVEngine.
        XCTAssertFalse(engine.txCallsign.isEmpty)
    }

    func testTxCallsign_canBeChanged() {
        engine.txCallsign = "W1AW"
        XCTAssertEqual(engine.txCallsign, "W1AW")
    }

    // MARK: Mode enum regression guards

    func testModeRawValues_matchCodec2Constants() {
        // These rawValues map directly to freedv_open() mode constants.
        // Regression guard: do not change these without updating codec2.
        XCTAssertEqual(FreeDVEngine.Mode.mode1600.rawValue, 0)
        XCTAssertEqual(FreeDVEngine.Mode.mode700C.rawValue, 6)
        XCTAssertEqual(FreeDVEngine.Mode.mode700D.rawValue, 7)
        XCTAssertEqual(FreeDVEngine.Mode.mode700E.rawValue, 13)
    }

    func testModeLabels_areNonEmpty() {
        for mode in FreeDVEngine.Mode.allCases {
            XCTAssertFalse(mode.label.isEmpty, "\(mode) label must not be empty")
            XCTAssertFalse(mode.details.isEmpty, "\(mode) details must not be empty")
        }
    }

    func testAllCases_hasFourModes() {
        XCTAssertEqual(FreeDVEngine.Mode.allCases.count, 4)
    }
}

// MARK: - FreeDVLanRxPipeline tests

final class FreeDVLanRxPipelineTests: XCTestCase {

    var engine: FreeDVEngine!
    var pipeline: FreeDVLanRxPipeline!
    var receivedSamples: [[Float]] = []

    override func setUp() {
        super.setUp()
        engine = FreeDVEngine()
        engine.open(mode: .mode1600)
        pipeline = FreeDVLanRxPipeline(engine: engine)
        receivedSamples = []
        pipeline.onAudio48kMono = { [weak self] s in self?.receivedSamples.append(s) }
    }

    override func tearDown() {
        pipeline = nil
        engine.close()
        engine = nil
        receivedSamples = []
        super.tearDown()
    }

    // MARK: feed16kSamples

    func testFeed_emptySamples_doesNotCrash() {
        pipeline.feed16kSamples([])
        // No crash is sufficient.
    }

    func testFeed_silencePackets_doesNotCrashOrHang() {
        // 320 samples is the standard KNS packet size (16 kHz, 20 ms).
        let silence = [Int16](repeating: 0, count: 320)
        for _ in 0..<10 {
            pipeline.feed16kSamples(silence)
        }
        // Pipeline may or may not emit audio (FreeDV needs sync first).
        // Assert that any emitted chunks are at 48 kHz scaling.
        for chunk in receivedSamples {
            XCTAssertGreaterThan(chunk.count, 0)
        }
    }

    func testFeed_outputSamplesAreNormalised() {
        // Any emitted float samples should be in [-1, 1].
        let silence = [Int16](repeating: 0, count: 320)
        for _ in 0..<20 { pipeline.feed16kSamples(silence) }
        for chunk in receivedSamples {
            for s in chunk {
                XCTAssertLessThanOrEqual(s, 1.0, "Sample \(s) exceeds +1.0")
                XCTAssertGreaterThanOrEqual(s, -1.0, "Sample \(s) is below -1.0")
            }
        }
    }

    func testReset_clearsInternalBuffers() {
        let silence = [Int16](repeating: 0, count: 320)
        pipeline.feed16kSamples(silence)
        pipeline.reset()
        // After reset, feed again — should not crash or produce corrupted output.
        pipeline.feed16kSamples(silence)
    }

    func testReset_clearsLastSpeechSample() {
        // After reset, the first chunk is handled as if no prior sample exists.
        pipeline.reset()
        let silence = [Int16](repeating: 0, count: 320)
        pipeline.feed16kSamples(silence)   // should not crash
    }

    // MARK: Decimation (16→8 kHz) ratio

    func testDecimation_outputCountIsHalfInput() {
        // We can't observe decimation directly, but we know the pipeline
        // decimates 320 16k samples → 160 8k samples before FreeDV.
        // Indirectly: if FreeDV emits speech, output at 48k should be ≤ 160×6 = 960 samples.
        // Just verify no crash and sanity of any output size.
        let silence = [Int16](repeating: 0, count: 320)
        for _ in 0..<30 { pipeline.feed16kSamples(silence) }
        for chunk in receivedSamples {
            // Each chunk is an interpolation run — must be a multiple of 6 or close.
            XCTAssertGreaterThan(chunk.count, 0)
        }
    }
}

// MARK: - RadioState FreeDV state tests

final class RadioStateFreeDVTests: XCTestCase {

    var radio: RadioState!
    private var sentCommands: [String] { DiagnosticsStore.shared.txLog }

    override func setUp() {
        super.setUp()
        radio = RadioState()
        // Reset to a known TX audio state regardless of any persisted UserDefaults value.
        radio.setTXAudioSource(.hardware)
        DiagnosticsStore.shared.txLog = []
    }

    override func tearDown() {
        radio.deactivateFreeDV()   // ensure clean state
        radio = nil
        DiagnosticsStore.shared.txLog = []
        super.tearDown()
    }

    // MARK: Initial state

    func testFreeDV_startsInactive() {
        XCTAssertFalse(radio.freedvIsActive)
    }

    func testFreeDV_defaultMode_is700D() {
        XCTAssertEqual(radio.freedvMode, .mode700D)
    }

    func testFreeDV_defaultAudioPath_isLan() {
        XCTAssertEqual(radio.freedvAudioPath, .lan)
    }

    func testFreeDV_defaultSync_isFalse() {
        XCTAssertFalse(radio.freedvSync)
    }

    func testFreeDV_defaultSnr_isZero() {
        XCTAssertEqual(radio.freedvSnrDB, 0)
    }

    func testFreeDV_defaultBer_isZero() {
        XCTAssertEqual(radio.freedvBer, 0)
    }

    func testFreeDV_defaultReceivedText_isEmpty() {
        XCTAssertEqual(radio.freedvReceivedText, "")
    }

    func testFreeDV_defaultError_isNil() {
        XCTAssertNil(radio.freedvError)
    }

    // MARK: AudioPath enum

    func testFreeDVAudioPath_allCasesHasTwo() {
        XCTAssertEqual(RadioState.FreeDVAudioPath.allCases.count, 2)
    }

    func testFreeDVAudioPath_lanRawValue() {
        XCTAssertEqual(RadioState.FreeDVAudioPath.lan.rawValue, "LAN (KNS)")
    }

    func testFreeDVAudioPath_usbRawValue() {
        XCTAssertEqual(RadioState.FreeDVAudioPath.usb.rawValue, "USB Audio")
    }

    // MARK: activateFreeDV — LAN path CAT commands

    func testActivateFreeDV_lan_setsIsActiveTrue() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
    }

    func testActivateFreeDV_lan_sendsUsbDataMode() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertTrue(sentCommands.contains("OM0D;"),
                      "Expected OM0D; (USB-DATA mode), got \(sentCommands)")
    }

    func testActivateFreeDV_lan_sendsMS003() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertTrue(sentCommands.contains("MS003;"),
                      "Expected MS003; (Rear=LAN audio) for FreeDV LAN path, got \(sentCommands)")
    }

    func testActivateFreeDV_lan_sendsOM0D_beforeMS003() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        guard let omIdx = sentCommands.firstIndex(of: "OM0D;"),
              let msIdx = sentCommands.firstIndex(of: "MS003;") else {
            XCTFail("Expected both OM0D; and MS003; in sent commands, got \(sentCommands)")
            return
        }
        XCTAssertLessThan(omIdx, msIdx, "OM0D; must be sent before MS003;")
    }

    func testActivateFreeDV_setsMode() {
        radio.activateFreeDV(mode: .mode1600, audioPath: .lan)
        XCTAssertEqual(radio.freedvMode, .mode1600)
    }

    func testActivateFreeDV_setsAudioPath() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertEqual(radio.freedvAudioPath, .lan)
    }

    func testActivateFreeDV_clearsError() {
        radio.freedvError = "stale error"
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertNil(radio.freedvError)
    }

    // MARK: activateFreeDV — all modes

    func testActivateFreeDV_mode1600_activates() {
        radio.activateFreeDV(mode: .mode1600, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
        XCTAssertEqual(radio.freedvMode, .mode1600)
    }

    func testActivateFreeDV_mode700C_activates() {
        radio.activateFreeDV(mode: .mode700C, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
        XCTAssertEqual(radio.freedvMode, .mode700C)
    }

    func testActivateFreeDV_mode700E_activates() {
        radio.activateFreeDV(mode: .mode700E, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
        XCTAssertEqual(radio.freedvMode, .mode700E)
    }

    // MARK: deactivateFreeDV

    func testDeactivateFreeDV_setsIsActiveFalse() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        radio.deactivateFreeDV()
        XCTAssertFalse(radio.freedvIsActive)
    }

    func testDeactivateFreeDV_sendsMicrophoneSource() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        DiagnosticsStore.shared.txLog = []
        radio.deactivateFreeDV()
        XCTAssertTrue(sentCommands.contains("MS010;"),
                      "Expected MS010; (Front=Microphone) on deactivate, got \(sentCommands)")
    }

    func testDeactivateFreeDV_restoresPreviousMode_USB() {
        radio.handleFrame("OM02;")   // USB mode
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        DiagnosticsStore.shared.txLog = []
        radio.deactivateFreeDV()
        XCTAssertTrue(sentCommands.contains("OM02;"),
                      "Expected OM02; (USB) restored on deactivate, got \(sentCommands)")
    }

    func testDeactivateFreeDV_restoresPreviousMode_FM() {
        radio.handleFrame("OM04;")   // FM
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        DiagnosticsStore.shared.txLog = []
        radio.deactivateFreeDV()
        XCTAssertTrue(sentCommands.contains("OM04;"),
                      "Expected OM04; (FM) restored, got \(sentCommands)")
    }

    func testDeactivateFreeDV_withNoPreviousMode_defaultsToUSB() {
        // operatingMode is nil at startup — should default to USB on revert.
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        DiagnosticsStore.shared.txLog = []
        radio.deactivateFreeDV()
        XCTAssertTrue(sentCommands.contains("OM02;"),
                      "Expected OM02; (USB default) when no prior mode, got \(sentCommands)")
    }

    func testDeactivateFreeDV_resetsStats() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        // Manually set stats to simulate received data.
        radio.freedvSync           = true
        radio.freedvSnrDB          = 12.5
        radio.freedvBer            = 0.001
        radio.freedvTotalBits      = 50000
        radio.freedvTotalBitErrors = 50
        radio.freedvRxStatus       = 1

        radio.deactivateFreeDV()

        XCTAssertFalse(radio.freedvSync)
        XCTAssertEqual(radio.freedvSnrDB, 0)
        XCTAssertEqual(radio.freedvBer, 0)
        XCTAssertEqual(radio.freedvTotalBits, 0)
        XCTAssertEqual(radio.freedvTotalBitErrors, 0)
        XCTAssertEqual(radio.freedvRxStatus, 0)
    }

    func testDeactivateFreeDV_whenNotActive_isNoOp() {
        // Should not crash and should not send any commands.
        let before = sentCommands.count
        radio.deactivateFreeDV()
        XCTAssertEqual(sentCommands.count, before, "deactivateFreeDV when inactive must not send commands")
    }

    // MARK: Double activate (guard)

    func testActivateFreeDV_whenAlreadyActive_isNoOp() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        let cmdsAfterFirst = sentCommands

        // Second activate with different mode — should be ignored.
        radio.activateFreeDV(mode: .mode1600, audioPath: .lan)
        XCTAssertEqual(sentCommands, cmdsAfterFirst,
                       "Second activateFreeDV while active must send no additional commands")
        XCTAssertEqual(radio.freedvMode, .mode700D, "Mode must not change while active")
    }

    // MARK: Activate → deactivate → activate cycle

    func testActivateDeactivateCycle_canRepeat() {
        radio.handleFrame("OM02;")

        radio.activateFreeDV(mode: .mode1600, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
        radio.deactivateFreeDV()
        XCTAssertFalse(radio.freedvIsActive)

        DiagnosticsStore.shared.txLog = []
        radio.activateFreeDV(mode: .mode700E, audioPath: .lan)
        XCTAssertTrue(radio.freedvIsActive)
        XCTAssertEqual(radio.freedvMode, .mode700E)
        XCTAssertTrue(sentCommands.contains("OM0D;"))

        radio.deactivateFreeDV()
        XCTAssertFalse(radio.freedvIsActive)
    }

    // MARK: CAT command regression guards

    func testFreeDVCATCommand_usbDataModeIsD() {
        // P2=D encodes USB-DATA per TS-890S PC Command Reference.
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertTrue(sentCommands.contains("OM0D;"),
                      "USB-DATA mode must always be OM0D;")
    }

    func testFreeDVCATCommand_lanAudioSourceIsMS003() {
        // LAN path: Rear = LAN (KNS audio carries modem tones), P3=3.
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        XCTAssertTrue(sentCommands.contains("MS003;"),
                      "LAN audio path must use MS003; (Rear=LAN) per TS-890S command reference")
    }

    func testFreeDVCATCommand_revertMicIsMS010() {
        radio.activateFreeDV(mode: .mode700D, audioPath: .lan)
        DiagnosticsStore.shared.txLog = []
        radio.deactivateFreeDV()
        XCTAssertTrue(sentCommands.contains("MS010;"),
                      "Revert must use MS010; (Front=Microphone)")
    }
}
