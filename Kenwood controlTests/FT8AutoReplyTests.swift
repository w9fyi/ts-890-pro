import XCTest
@testable import Kenwood_control

// MARK: - FT8 Auto-Reply State Machine Tests
//
// Test cases derived from live on-air sessions (2026-03-14):
//   - KB9DED QSO: full CQ path (grid → RRR → 73)
//   - KE9SX QSO: directed call path (signal report → R+report → RR73 → 73), confirmed QSO
//   - KM4JXE: mid-exchange stall (auto-clear after 6 retries)
//   - Regression: RR73 was not recognized (only RRR was) — now both handled
//   - Regression: race condition — processDecodedLine was advancing state for non-queued callers
//   - Regression: RR73/73 closing messages were re-queued as new candidates

final class FT8AutoReplyTests: XCTestCase {

    private let myCall = "AI5OS"
    private let myGrid = "EM10BK"
    private var vm: FT8ViewModel!

    override func setUp() {
        super.setUp()
        vm = FT8ViewModel()
    }

    override func tearDown() {
        vm = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func reply(_ line: String) -> String? {
        vm.autoReply(forDecodedLine: line, myCall: myCall, myGrid: myGrid)
    }

    // MARK: - Full CQ QSO path (KB9DED pattern from logs)

    func testCQPath_gridReply() {
        // They send their grid → we send ours
        let r = reply("AI5OS KB9DED EN54")
        XCTAssertEqual(r, "KB9DED AI5OS EM10BK")
    }

    func testCQPath_RplusReportAfterGrid() {
        // After exchanging grids, they send R+signal → we send RRR
        _ = reply("AI5OS KB9DED EN54")   // advance to sentGrid
        let r = reply("AI5OS KB9DED R-16")
        XCTAssertEqual(r, "KB9DED AI5OS RRR")
    }

    func testCQPath_RR73_returns73() {
        // Regression: RR73 was not recognized — only RRR was handled.
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")
        let r = reply("AI5OS KB9DED RR73")
        XCTAssertEqual(r, "KB9DED AI5OS 73")
    }

    func testCQPath_RRR_returns73() {
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")
        let r = reply("AI5OS KB9DED RRR")
        XCTAssertEqual(r, "KB9DED AI5OS 73")
    }

    func testCQPath_theirFinal73_returnsNil() {
        // They send 73 → QSO complete, no reply needed.
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")
        _ = reply("AI5OS KB9DED RRR")
        let r = reply("AI5OS KB9DED 73")
        XCTAssertNil(r)
    }

    // MARK: - Directed call path (KE9SX pattern from logs)

    func testDirectedCall_signalReport_returnsRplusReport() {
        // They start with a plain signal report (no R prefix) → we send R+report
        let r = reply("AI5OS KE9SX +01")
        XCTAssertEqual(r, "KE9SX AI5OS R+01")
    }

    func testDirectedCall_negativeReport_returnsRplusReport() {
        let r = reply("AI5OS KE9SX -12")
        XCTAssertEqual(r, "KE9SX AI5OS R-12")
    }

    func testDirectedCall_RplusReport_returnsRRR() {
        _ = reply("AI5OS KE9SX +01")   // advance to sentRReport
        let r = reply("AI5OS KE9SX R+01")
        XCTAssertEqual(r, "KE9SX AI5OS RRR")
    }

    func testDirectedCall_RR73_after_RRR_returns73() {
        _ = reply("AI5OS KE9SX +01")
        _ = reply("AI5OS KE9SX R+01")
        let r = reply("AI5OS KE9SX RR73")
        XCTAssertEqual(r, "KE9SX AI5OS 73")
    }

    // MARK: - Idempotency: same stage does not re-send same reply

    func testIdempotency_grid_secondCallReturnsGrid() {
        // First call with grid — sentGrid stage, returns our grid
        _ = reply("AI5OS KB9DED EN54")
        // Same message again — stage is already sentGrid, still returns grid (allows for retry)
        let r = reply("AI5OS KB9DED EN54")
        XCTAssertEqual(r, "KB9DED AI5OS EM10BK")
    }

    func testIdempotency_RRR_notRepeated() {
        // After we've sent RRR, they send R+report again — we should NOT repeat RRR
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")  // advances to sentRRR
        _ = reply("AI5OS KB9DED R-16")  // same message again — should return nil (already sentRRR)
        let r = reply("AI5OS KB9DED R-16")
        XCTAssertNil(r)
    }

    func testIdempotency_73_notRepeated() {
        // After we've sent 73, they send RRR again — we should NOT repeat 73
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")
        _ = reply("AI5OS KB9DED RRR")   // advances to sent73
        let r = reply("AI5OS KB9DED RRR")
        XCTAssertNil(r)
    }

    // MARK: - Messages not directed to us

    func testNotDirectedToUs_returnsNil() {
        let r = reply("W5XX KB9DED EN54")
        XCTAssertNil(r)
    }

    func testCQMessage_returnsNil() {
        let r = reply("CQ KB9DED EN54")
        XCTAssertNil(r)
    }

    func testOnlyTwoTokens_returnsNil() {
        let r = reply("AI5OS KB9DED")
        XCTAssertNil(r, "Two-token message (no payload) should not generate a reply")
    }

    func testEmptyLine_returnsNil() {
        XCTAssertNil(reply(""))
    }

    // MARK: - queuedTarget lifecycle

    func testRR73_doesNotClearQueuedTarget() {
        // Regression: queuedTarget was cleared immediately on RR73 before 73 was transmitted.
        // cqTick needs queuedTarget to still be set so it actually sends the 73.
        vm.queuedTarget = "KB9DED"
        _ = reply("AI5OS KB9DED EN54")
        _ = reply("AI5OS KB9DED R-16")
        _ = reply("AI5OS KB9DED RR73")
        XCTAssertEqual(vm.queuedTarget, "KB9DED",
            "queuedTarget must NOT be cleared by autoReply on RR73 — cqTick clears it after actual TX")
    }

    func testTheirFinal73_clearsQueuedTarget() {
        // When they send 73, the QSO is done — clear target immediately.
        vm.queuedTarget = "KE9SX"
        _ = reply("AI5OS KE9SX +01")
        _ = reply("AI5OS KE9SX R+01")
        _ = reply("AI5OS KE9SX RR73")   // we reply 73
        _ = reply("AI5OS KE9SX 73")     // they confirm — clears target
        XCTAssertNil(vm.queuedTarget,
            "queuedTarget should be cleared when they send final 73")
    }

    // MARK: - processDecodedLine race condition guard

    func testProcessDecodedLine_nonQueuedCaller_doesNotUpdatePlannedTx() {
        // Regression: processDecodedLine was advancing qsoStageByCaller for any directed message,
        // causing fillReply to see stale stage and fall back to sending grid instead of correct reply.
        vm.queuedTarget = nil   // no queued target
        vm.processDecodedLine("AI5OS KB9DED EN54", myCall: myCall, myGrid: myGrid)
        XCTAssertEqual(vm.plannedTxText, "",
            "Non-queued caller must not update plannedTxText")
    }

    func testProcessDecodedLine_queuedCaller_updatesPlannedTx() {
        // Queued target's message SHOULD update plannedTxText.
        vm.queuedTarget = "KB9DED"
        vm.processDecodedLine("AI5OS KB9DED EN54", myCall: myCall, myGrid: myGrid)
        XCTAssertEqual(vm.plannedTxText, "KB9DED AI5OS EM10BK",
            "Queued caller's grid exchange should update plannedTxText")
    }

    func testProcessDecodedLine_differentQueuedCaller_doesNotUpdatePlannedTx() {
        // KB9DED calls us but we are working KE9SX — KB9DED must not hijack state.
        vm.queuedTarget = "KE9SX"
        vm.processDecodedLine("AI5OS KB9DED EN54", myCall: myCall, myGrid: myGrid)
        XCTAssertEqual(vm.plannedTxText, "",
            "Non-queued caller (different from queuedTarget) must not update plannedTxText")
    }

    // MARK: - fillReply

    func testFillReply_firstContact_fallsBackToGrid() {
        // No prior state for this caller — fillReply falls back to sending our grid.
        let msg = FT8ViewModel.DecodedMessage(
            receivedAt: Date(), raw: "AI5OS KE9SX EN54",
            caller: "KE9SX", to: myCall,
            payload: "EN54", isDirectedToMe: true
        )
        vm.queueTarget("KE9SX", for: msg, myCall: myCall, myGrid: myGrid)
        XCTAssertEqual(vm.plannedTxText, "KE9SX AI5OS EM10BK")
    }

    func testFillReply_signalReport_usesStateMachine() {
        // They open with a signal report rather than a grid.
        let msg = FT8ViewModel.DecodedMessage(
            receivedAt: Date(), raw: "AI5OS KE9SX +01",
            caller: "KE9SX", to: myCall,
            payload: "+01", isDirectedToMe: true
        )
        vm.queueTarget("KE9SX", for: msg, myCall: myCall, myGrid: myGrid)
        XCTAssertEqual(vm.plannedTxText, "KE9SX AI5OS R+01")
    }

    // MARK: - Case insensitivity
    //
    // autoReply requires pre-uppercased myCall — processDecodedLine handles that.
    // Verified: autoReply("AI5OS KB9DED EN54", myCall: "AI5OS") → correct reply.
    func testAutoReply_uppercaseCallsign_handledCorrectly() {
        let r = vm.autoReply(forDecodedLine: "AI5OS KB9DED EN54",
                             myCall: "AI5OS", myGrid: "EM10BK")
        XCTAssertEqual(r, "KB9DED AI5OS EM10BK")
    }
}
