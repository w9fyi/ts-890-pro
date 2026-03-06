import Foundation

// MARK: - Connection type (LAN vs USB serial)

enum ConnectionType: String, Codable, CaseIterable {
    case lan = "LAN"
    case usb = "USB"
}

// MARK: - Shared status type

/// Status enum shared by both the LAN (TS890Connection) and USB (SerialCATConnection) transports.
/// Defined here so SerialCATConnection doesn't depend on TS890Connection.
enum CATConnectionStatus: String {
    case disconnected, connecting, authenticating, connected
}

// MARK: - Protocol

/// Common interface that both LAN and USB serial CAT transports conform to.
/// RadioState holds an `any CATTransport` so it can switch transports without changing
/// any of the frame-parsing or command logic above this layer.
protocol CATTransport: AnyObject {
    var onStatusChange: ((CATConnectionStatus) -> Void)? { get set }
    var onError:        ((String) -> Void)?               { get set }
    var onFrame:        ((String) -> Void)?               { get set }
    var onLog:          ((String) -> Void)?               { get set }
    var status: CATConnectionStatus { get }
    func send(_ command: String)
    func disconnect()
}
