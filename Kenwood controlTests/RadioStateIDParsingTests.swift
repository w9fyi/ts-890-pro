import XCTest
@testable import Kenwood_control

/// Tests for RadioState.handleFrame — ID response parsing and capability updates.
/// Feeds raw CAT frames directly into handleFrame() and asserts that radioModel
/// and capabilities are set correctly, including the capability-change side effects.
final class RadioStateIDParsingTests: XCTestCase {

    var radio: RadioState!

    override func setUp() {
        super.setUp()
        radio = RadioState()
    }

    override func tearDown() {
        radio = nil
        super.tearDown()
    }

    // MARK: - ID frame → correct model

    func testParseID_ts890s() {
        radio.handleFrame("ID024;")
        XCTAssertEqual(radio.radioModel, .ts890s)
    }

    func testParseID_ts990s() {
        radio.handleFrame("ID019;")
        XCTAssertEqual(radio.radioModel, .ts990s)
    }

    func testParseID_ts590sg() {
        radio.handleFrame("ID023;")
        XCTAssertEqual(radio.radioModel, .ts590sg)
    }

    func testParseID_ts590s() {
        radio.handleFrame("ID021;")
        XCTAssertEqual(radio.radioModel, .ts590s)
    }

    func testParseID_unknownDigits() {
        radio.handleFrame("ID999;")
        XCTAssertEqual(radio.radioModel, .unknown)
    }

    func testParseID_tooShort_doesNotChangeModel() {
        // "ID02" has only 2 digits after prefix — must not match any model
        radio.handleFrame("ID02;")
        // Default is .ts890s; a malformed short frame should not change it
        XCTAssertEqual(radio.radioModel, .ts890s,
            "A frame shorter than ID + 3 digits should not change the model")
    }

    // MARK: - Capabilities update when model changes

    func testCapabilitiesUpdate_ts590sg_disablesOMCommand() {
        // Default is ts890s (useOMCommand=true); receiving TS-590SG ID should flip it.
        radio.handleFrame("ID023;")
        XCTAssertFalse(radio.capabilities.useOMCommand,
            "TS-590SG uses MD command, not OM")
    }

    func testCapabilitiesUpdate_ts590sg_disablesScope() {
        radio.handleFrame("ID023;")
        XCTAssertFalse(radio.capabilities.hasScope)
    }

    func testCapabilitiesUpdate_ts590sg_disablesLANAudio() {
        radio.handleFrame("ID023;")
        XCTAssertFalse(radio.capabilities.hasLANAudio)
    }

    func testCapabilitiesUpdate_ts990s_hasScope() {
        radio.handleFrame("ID019;")
        XCTAssertTrue(radio.capabilities.hasScope,
            "TS-990S supports BS*/DD* scope commands")
    }

    func testCapabilitiesUpdate_ts990s_noLANAudio() {
        radio.handleFrame("ID019;")
        XCTAssertFalse(radio.capabilities.hasLANAudio,
            "TS-990S has LAN CAT but no audio streaming")
    }

    func testCapabilitiesUpdate_ts990s_hasDualReceive() {
        radio.handleFrame("ID019;")
        XCTAssertTrue(radio.capabilities.hasDualReceive)
    }

    func testCapabilitiesUpdate_ts890s_hasLANAudio() {
        // Simulate re-identification as ts890s after being unknown
        radio.handleFrame("ID999;")                // unknown
        XCTAssertEqual(radio.radioModel, .unknown)
        radio.handleFrame("ID024;")                // back to ts890s
        XCTAssertTrue(radio.capabilities.hasLANAudio)
    }

    // MARK: - Model re-identification (same model — no spurious changes)

    func testReidentification_sameModel_doesNotFlipCapabilities() {
        // Start: default ts890s
        XCTAssertTrue(radio.capabilities.hasLANAudio)

        // Receive ID for the same model again
        radio.handleFrame("ID024;")
        XCTAssertEqual(radio.radioModel, .ts890s)
        XCTAssertTrue(radio.capabilities.hasLANAudio,
            "Re-identifying the same model must not flip capabilities")
    }

    // MARK: - ID frame does not interfere with other parsers

    func testIDFrameFollowedByFAFrame() {
        radio.handleFrame("ID024;")
        radio.handleFrame("FA00014225000;")
        XCTAssertEqual(radio.radioModel, .ts890s)
        XCTAssertEqual(radio.vfoAFrequencyHz, 14_225_000,
            "FA frame after ID frame must still update VFO A frequency")
    }

    func testFAFrameFollowedByIDFrame() {
        radio.handleFrame("FA00007074000;")
        radio.handleFrame("ID019;")
        XCTAssertEqual(radio.vfoAFrequencyHz, 7_074_000,
            "Frequency set before ID arrival must be preserved")
        XCTAssertEqual(radio.radioModel, .ts990s)
    }

    // MARK: - Capabilities struct consistency

    func testCapabilities_modelMatchesRadioModel() {
        radio.handleFrame("ID023;")
        XCTAssertEqual(radio.capabilities.model, radio.radioModel,
            "capabilities.model must always equal radioModel after any ID frame")
    }

    func testCapabilities_ts590s_noMorseDecoder() {
        radio.handleFrame("ID021;")
        XCTAssertFalse(radio.capabilities.hasMorseDecoder,
            "TS-590S lacks the morse decoder added in the SG revision")
    }

    func testCapabilities_ts590sg_hasMorseDecoder() {
        radio.handleFrame("ID023;")
        XCTAssertTrue(radio.capabilities.hasMorseDecoder,
            "TS-590SG added CD0/CD1/CD2 morse decoder command")
    }
}
