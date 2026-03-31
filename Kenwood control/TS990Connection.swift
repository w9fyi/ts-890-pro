// TS990Connection.swift
// TS-890 Pro — TS-990S proprietary LAN transport
//
// The TS-990S uses a proprietary TCP protocol over LAN that is NOT KNS.
// Handshake: ##CN; → ##CN1; (success) then ##ID{len}{len}{account}{password} → ##ID1;
// All frames are UTF-16 encoded over the wire (vs UTF-8 for TS-890S KNS).
//
// This is a skeleton implementation — LAN connection to a TS-990S requires
// a physical radio for testing. USB serial works today via SerialCATConnection.

import Foundation

final class TS990Connection: CATTransport {
    var onStatusChange: ((CATConnectionStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onFrame: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private(set) var status: CATConnectionStatus = .disconnected

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var readBuffer = Data()
    private var host: String = ""
    private var port: UInt16 = 60000
    private var account: String = ""
    private var password: String = ""

    // MARK: - Connect

    func connect(host: String, port: UInt16, account: String, password: String) {
        self.host = host
        self.port = port
        self.account = account
        self.password = password

        setStatus(.connecting)
        onLog?("TS990: connecting to \(host):\(port)")

        var input: InputStream?
        var output: OutputStream?
        Stream.getStreamsToHost(withName: host, port: Int(port),
                               inputStream: &input, outputStream: &output)

        guard let input, let output else {
            onError?("TS990: failed to create streams to \(host):\(port)")
            setStatus(.disconnected)
            return
        }

        inputStream = input
        outputStream = output

        input.schedule(in: .main, forMode: .common)
        output.schedule(in: .main, forMode: .common)

        input.open()
        output.open()

        // Begin the proprietary handshake after a brief delay for stream setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendHandshake()
        }
    }

    // MARK: - Handshake

    /// TS-990S LAN login sequence:
    /// 1. Send ##CN;
    /// 2. Expect ##CN1; (connection accepted)
    /// 3. Send ##ID{acctLen}{passLen}{account}{password};
    /// 4. Expect ##ID{P5}; where P5=1 means success
    private func sendHandshake() {
        setStatus(.authenticating)
        // Step 1: initiate connection
        sendRaw("##CN;")
        onLog?("TS990: sent ##CN; handshake")
        // The response handling (##CN1 → ##ID login) would be implemented
        // in a stream delegate read handler. For now this is a skeleton.
        // TODO: Implement StreamDelegate to read ##CN response, send ##ID, verify ##ID1
    }

    // MARK: - Send

    func send(_ command: String) {
        sendRaw(command)
    }

    private func sendRaw(_ command: String) {
        // TS-990S LAN uses UTF-16 LE encoding
        guard let data = command.data(using: .utf16LittleEndian) else {
            onError?("TS990: failed to encode command as UTF-16: \(command)")
            return
        }
        guard let output = outputStream, output.hasSpaceAvailable else {
            onError?("TS990: output stream not available")
            return
        }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            output.write(base, maxLength: data.count)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        inputStream?.remove(from: .main, forMode: .common)
        outputStream?.remove(from: .main, forMode: .common)
        inputStream = nil
        outputStream = nil
        readBuffer.removeAll()
        setStatus(.disconnected)
        onLog?("TS990: disconnected")
    }

    // MARK: - Internal

    private func setStatus(_ newStatus: CATConnectionStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }
}
