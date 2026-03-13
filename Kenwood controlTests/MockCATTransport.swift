import Foundation
@testable import Kenwood_control

/// Fake CATTransport that captures every string passed to send().
/// Inject into RadioState via _setConnectionForTesting(_:) to test
/// that action methods send the correct CAT wire strings without a
/// live radio connection.
///
/// Usage:
///   let mock = MockCATTransport()
///   radio._setConnectionForTesting(mock)
///   radio.setNoiseBlankerEnabled(true)
///   XCTAssertEqual(mock.sent.last, "NB11;")
final class MockCATTransport: CATTransport {
    nonisolated deinit {}

    // MARK: - CATTransport conformance

    var onStatusChange: ((CATConnectionStatus) -> Void)?
    var onError:        ((String) -> Void)?
    var onFrame:        ((String) -> Void)?
    var onLog:          ((String) -> Void)?
    var status: CATConnectionStatus = .disconnected

    func send(_ command: String) {
        sent.append(command)
    }

    func disconnect() {
        status = .disconnected
    }

    // MARK: - Test helpers

    /// All strings passed to send(), in order.
    var sent: [String] = []

    /// Clears the captured send log.
    func reset() { sent.removeAll() }

    /// Simulates an incoming frame from the radio, routing it through
    /// RadioState.handleFrame via the onFrame callback.
    func injectFrame(_ frame: String) {
        onFrame?(frame)
    }
}
