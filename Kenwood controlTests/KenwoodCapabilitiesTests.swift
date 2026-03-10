import XCTest
@testable import Kenwood_control

/// Tests for KenwoodRadioModel and KenwoodCapabilities.
/// Validates model identification from raw ID strings and that every
/// capability flag is set correctly for all four supported radios.
final class KenwoodCapabilitiesTests: XCTestCase {

    // MARK: - KenwoodRadioModel identity

    func testModelInit_ts890s_bareDigits() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "024"), .ts890s)
    }

    func testModelInit_ts890s_withPrefixAndSemicolon() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "ID024;"), .ts890s)
    }

    func testModelInit_ts590sg_withPrefixAndSemicolon() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "ID023;"), .ts590sg)
    }

    func testModelInit_ts590s_withPrefixAndSemicolon() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "ID021;"), .ts590s)
    }

    func testModelInit_ts990s_withPrefixAndSemicolon() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "ID019;"), .ts990s)
    }

    func testModelInit_unknown_unrecognisedDigits() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: "ID999;"), .unknown)
    }

    func testModelInit_unknown_emptyString() {
        XCTAssertEqual(KenwoodRadioModel(idResponse: ""), .unknown)
    }

    func testModelInit_rawValue_ts890s() {
        XCTAssertEqual(KenwoodRadioModel(rawValue: "024"), .ts890s)
    }

    // MARK: - Description strings

    func testDescription_ts890s() {
        XCTAssertEqual(KenwoodRadioModel.ts890s.description, "TS-890S")
    }

    func testDescription_ts990s() {
        XCTAssertEqual(KenwoodRadioModel.ts990s.description, "TS-990S")
    }

    func testDescription_ts590sg() {
        XCTAssertEqual(KenwoodRadioModel.ts590sg.description, "TS-590SG")
    }

    func testDescription_ts590s() {
        XCTAssertEqual(KenwoodRadioModel.ts590s.description, "TS-590S")
    }

    func testDescription_unknown() {
        XCTAssertEqual(KenwoodRadioModel.unknown.description, "Unknown")
    }

    // MARK: - TS-890S capabilities (primary radio — all premium features)

    func testTS890S_hasLAN() {
        XCTAssertTrue(caps(.ts890s).hasLAN)
    }

    func testTS890S_hasLANAudio() {
        XCTAssertTrue(caps(.ts890s).hasLANAudio, "TS-890S is the only radio with ##VP/##KN audio streaming")
    }

    func testTS890S_lanEncoding_utf8() {
        XCTAssertEqual(caps(.ts890s).lanEncoding, .utf8)
    }

    func testTS890S_useOMCommand() {
        XCTAssertTrue(caps(.ts890s).useOMCommand)
    }

    func testTS890S_hasPSKModes() {
        XCTAssertTrue(caps(.ts890s).hasPSKModes)
    }

    func testTS890S_hasScope() {
        XCTAssertTrue(caps(.ts890s).hasScope)
    }

    func testTS890S_noDualReceive() {
        XCTAssertFalse(caps(.ts890s).hasDualReceive, "Dual receive (SB) is TS-990S only")
    }

    func testTS890S_has18BandEQ() {
        XCTAssertTrue(caps(.ts890s).has18BandEQ)
    }

    func testTS890S_hasAudioSourceSelect() {
        XCTAssertTrue(caps(.ts890s).hasAudioSourceSelect)
    }

    func testTS890S_noMorseDecoder() {
        XCTAssertFalse(caps(.ts890s).hasMorseDecoder, "CD morse decoder is TS-590SG only")
    }

    // MARK: - TS-990S capabilities (LAN CAT but NO audio streaming)

    func testTS990S_hasLAN() {
        XCTAssertTrue(caps(.ts990s).hasLAN)
    }

    func testTS990S_noLANAudio() {
        XCTAssertFalse(caps(.ts990s).hasLANAudio,
            "TS-990S has LAN CAT (##CN/##ID) but no ##VP/##KN audio stream")
    }

    func testTS990S_lanEncoding_utf16() {
        XCTAssertEqual(caps(.ts990s).lanEncoding, .utf16,
            "TS-990S KNS uses UTF-16; TS-890S uses UTF-8")
    }

    func testTS990S_useOMCommand() {
        XCTAssertTrue(caps(.ts990s).useOMCommand)
    }

    func testTS990S_hasPSKModes() {
        XCTAssertTrue(caps(.ts990s).hasPSKModes)
    }

    func testTS990S_hasScope() {
        XCTAssertTrue(caps(.ts990s).hasScope)
    }

    func testTS990S_hasDualReceive() {
        XCTAssertTrue(caps(.ts990s).hasDualReceive, "TS-990S supports SB sub-band command")
    }

    func testTS990S_has18BandEQ() {
        XCTAssertTrue(caps(.ts990s).has18BandEQ, "TS-990S uses UT/UR commands for 18-band EQ")
    }

    func testTS990S_hasAudioSourceSelect() {
        XCTAssertTrue(caps(.ts990s).hasAudioSourceSelect)
    }

    func testTS990S_noMorseDecoder() {
        XCTAssertFalse(caps(.ts990s).hasMorseDecoder)
    }

    // MARK: - TS-590SG capabilities (serial only, no LAN, morse decoder)

    func testTS590SG_noLAN() {
        XCTAssertFalse(caps(.ts590sg).hasLAN)
    }

    func testTS590SG_noLANAudio() {
        XCTAssertFalse(caps(.ts590sg).hasLANAudio)
    }

    func testTS590SG_lanEncoding_none() {
        XCTAssertEqual(caps(.ts590sg).lanEncoding, .none)
    }

    func testTS590SG_usesMDNotOM() {
        XCTAssertFalse(caps(.ts590sg).useOMCommand, "TS-590SG uses MD command, not OM")
    }

    func testTS590SG_noPSKModes() {
        XCTAssertFalse(caps(.ts590sg).hasPSKModes)
    }

    func testTS590SG_noScope() {
        XCTAssertFalse(caps(.ts590sg).hasScope)
    }

    func testTS590SG_noDualReceive() {
        XCTAssertFalse(caps(.ts590sg).hasDualReceive)
    }

    func testTS590SG_no18BandEQ() {
        XCTAssertFalse(caps(.ts590sg).has18BandEQ, "TS-590SG has preset EQ curves only, no parametric")
    }

    func testTS590SG_noAudioSourceSelect() {
        XCTAssertFalse(caps(.ts590sg).hasAudioSourceSelect)
    }

    func testTS590SG_hasMorseDecoder() {
        XCTAssertTrue(caps(.ts590sg).hasMorseDecoder, "TS-590SG has CD0/CD1/CD2 morse decoder command")
    }

    // MARK: - TS-590S capabilities (subset of SG — no morse decoder)

    func testTS590S_noLAN() {
        XCTAssertFalse(caps(.ts590s).hasLAN)
    }

    func testTS590S_usesMDNotOM() {
        XCTAssertFalse(caps(.ts590s).useOMCommand)
    }

    func testTS590S_noMorseDecoder() {
        XCTAssertFalse(caps(.ts590s).hasMorseDecoder,
            "Morse decoder (CD) was added in TS-590SG, not present in original TS-590S")
    }

    func testTS590S_noScope() {
        XCTAssertFalse(caps(.ts590s).hasScope)
    }

    // MARK: - Unknown model defaults to TS-890S-like flags (safe fallback)

    func testUnknown_fallsBackToLANAudio() {
        XCTAssertTrue(caps(.unknown).hasLANAudio,
            "Unknown model should default to TS-890S-like capabilities so LAN audio is not broken")
    }

    func testUnknown_fallsBackToScope() {
        XCTAssertTrue(caps(.unknown).hasScope)
    }

    func testUnknown_fallsBackToOMCommand() {
        XCTAssertTrue(caps(.unknown).useOMCommand)
    }

    // MARK: - Key differentiators between LAN-capable radios

    func testLANAudioExclusiveToTS890S() {
        // Of the two LAN-capable radios, only the 890S has audio streaming.
        XCTAssertTrue(caps(.ts890s).hasLANAudio)
        XCTAssertFalse(caps(.ts990s).hasLANAudio)
    }

    func testDualReceiveExclusiveToTS990S() {
        XCTAssertFalse(caps(.ts890s).hasDualReceive)
        XCTAssertTrue(caps(.ts990s).hasDualReceive)
    }

    func testEncodingDiffersOnLANRadios() {
        XCTAssertNotEqual(caps(.ts890s).lanEncoding, caps(.ts990s).lanEncoding)
    }

    func testOMCommandOnLANRadios_MDOnSerialOnlyRadios() {
        XCTAssertTrue(caps(.ts890s).useOMCommand)
        XCTAssertTrue(caps(.ts990s).useOMCommand)
        XCTAssertFalse(caps(.ts590s).useOMCommand)
        XCTAssertFalse(caps(.ts590sg).useOMCommand)
    }

    // MARK: - Model stored in capabilities struct

    func testCapabilities_modelPropertyMatchesInput() {
        for model in KenwoodRadioModel.allCases {
            let c = KenwoodCapabilities.capabilities(for: model)
            XCTAssertEqual(c.model, model, "capabilities(for:) should store the model it was built for")
        }
    }

    // MARK: - Helpers

    private func caps(_ model: KenwoodRadioModel) -> KenwoodCapabilities {
        KenwoodCapabilities.capabilities(for: model)
    }
}

// Make KenwoodRadioModel CaseIterable for exhaustive testing
extension KenwoodRadioModel: CaseIterable {
    public static var allCases: [KenwoodRadioModel] {
        [.ts590s, .ts590sg, .ts890s, .ts990s, .unknown]
    }
}
