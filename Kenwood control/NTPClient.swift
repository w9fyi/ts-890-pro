//
//  NTPClient.swift
//  Kenwood control
//
//  Minimal SNTP client (RFC 4330).
//  Sends a 48-byte client request to port 123 and reads the transmit timestamp
//  (bytes 40–43) from the response to obtain current UTC time.
//

import Foundation
import Network

enum NTPError: Error, LocalizedError {
    case timeout
    case invalidResponse
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:            return "NTP query timed out."
        case .invalidResponse:    return "NTP server returned an invalid response."
        case .connectionFailed(let msg): return "NTP connection failed: \(msg)"
        }
    }
}

final class NTPClient {

    /// Default public NTP pool server.
    static let defaultServer = "pool.ntp.org"

    /// NTP epoch offset in seconds (NTP epoch = Jan 1 1900; Unix epoch = Jan 1 1970).
    private static let ntpEpochOffset: Double = 2_208_988_800

    // MARK: - Public API

    /// Query `server` on UDP port 123 and call `completion` on the main queue
    /// with the current UTC time (or an error).
    static func queryTime(server: String,
                          timeout: TimeInterval = 4.0,
                          completion: @escaping (Result<Date, Error>) -> Void) {

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(server.isEmpty ? defaultServer : server),
            port: NWEndpoint.Port(rawValue: 123)!
        )
        let connection = NWConnection(to: endpoint, using: .udp)
        var finished = false

        func finish(_ result: Result<Date, Error>) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sendRequest(on: connection, finish: finish)
            case .failed(let err):
                finish(.failure(NTPError.connectionFailed(err.localizedDescription)))
            case .waiting(let err):
                finish(.failure(NTPError.connectionFailed(err.localizedDescription)))
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))

        // Hard timeout in case the server never replies.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            finish(.failure(NTPError.timeout))
        }
    }

    // MARK: - Private

    private static func sendRequest(on connection: NWConnection,
                                    finish: @escaping (Result<Date, Error>) -> Void) {
        // 48-byte SNTP packet: LI=0, VN=3 (NTPv3), Mode=3 (client)
        var packet = [UInt8](repeating: 0, count: 48)
        packet[0] = 0x1B
        let data = Data(packet)

        connection.send(content: data, completion: .contentProcessed { err in
            if let err = err { finish(.failure(err)); return }

            connection.receive(minimumIncompleteLength: 48, maximumLength: 256) { data, _, _, err in
                if let err = err { finish(.failure(err)); return }
                guard let data = data, data.count >= 44 else {
                    finish(.failure(NTPError.invalidResponse)); return
                }
                // Transmit Timestamp (T3) — seconds field at byte offset 40
                let ntpSeconds = data.withUnsafeBytes { ptr -> UInt32 in
                    ptr.loadUnaligned(fromByteOffset: 40, as: UInt32.self).bigEndian
                }
                guard ntpSeconds > 0 else {
                    finish(.failure(NTPError.invalidResponse)); return
                }
                let unix = Double(ntpSeconds) - ntpEpochOffset
                finish(.success(Date(timeIntervalSince1970: unix)))
            }
        })
    }
}
