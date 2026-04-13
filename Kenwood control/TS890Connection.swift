import Foundation
import Darwin

/// TCP connection to a Kenwood radio via KNS (LAN).
/// Supports TS-890S (UTF-8) and TS-990S (UTF-16LE) — encoding is auto-detected
/// on first connect by inspecting the ##CN response bytes.
/// Uses POSIX BSD sockets instead of Network.framework so that macOS Local
/// Network TCC permission is never required (NWConnection triggers TCC;
/// raw sockets do not).
final class TS890Connection {
    private enum AuthState { case idle, sentCN, sentID, authenticated }

    var onStatusChange: ((CATConnectionStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onFrame: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    /// Delivers parsed bandscope data: 640 UInt8 values (0x00=0 dB … 0x8C=−100 dB).
    var onScopeData: (([UInt8]) -> Void)?

    private(set) var status: CATConnectionStatus = .disconnected

    // POSIX socket fd. -1 = no socket. Only read/written on `queue`.
    private var socketFD: Int32 = -1
    // Monotonically increasing. Incremented in teardown() so background threads
    // from stale connect() calls can detect they've been superseded.
    private var connectGeneration: Int = 0

    private let queue = DispatchQueue(label: "TS890Connection.queue")
    private var receiveBuffer = Data()
    private var authState: AuthState = .idle
    private var useKnsLogin: Bool = true
    private var accountType: KenwoodKNS.AccountType = .administrator
    private var adminId: String = ""
    private var adminPassword: String = ""
    private var authTimeoutTimer: DispatchSourceTimer?
    private var connectTimeoutTimer: DispatchSourceTimer?
    private var keepaliveTimer: DispatchSourceTimer?
    private let keepaliveInterval: TimeInterval = 5
    private let authTimeoutInterval: TimeInterval = 10
    private let connectTimeoutInterval: TimeInterval = 15
    private var currentHost: String?
    private var currentPort: UInt16 = 60000

    // UTF-16LE support (TS-990S). Detected automatically from ##CN response
    // or inferred when no frames arrive within the encoding probe window.
    private var useUTF16LE: Bool = false
    private var didRetryEncoding: Bool = false
    private var hasReceivedFrame: Bool = false
    private var encodingProbeTimer: DispatchSourceTimer?
    private let encodingProbeInterval: TimeInterval = 3

    nonisolated deinit {}

    // MARK: - Helpers

    private func isASCII(_ s: String) -> Bool {
        s.utf8.allSatisfy { $0 < 0x80 }
    }

    private func sanitizeCredential(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }

    private func redactedForLog(_ command: String) -> String {
        if command.hasPrefix("##ID") { return "##ID<redacted>;" }
        return command
    }

    // MARK: - Teardown (must be called on `queue`)

    private func teardown() {
        connectGeneration += 1          // invalidate any in-flight openSocket call
        let fd = socketFD
        socketFD = -1                   // set BEFORE close so recv thread sees -1 on wake
        if fd >= 0 { Darwin.close(fd) }
        receiveBuffer.removeAll(keepingCapacity: true)
        stopAuthTimeout()
        stopConnectTimeout()
        stopKeepalive()
        stopEncodingProbe()
        authState = .idle
    }

    // MARK: - Public API

    func connect(host: String, port: UInt16,
                 useKnsLogin: Bool,
                 accountType: KenwoodKNS.AccountType = .administrator,
                 adminId: String,
                 adminPassword: String,
                 preferUTF16LE: Bool = false) {
        let cleanId = sanitizeCredential(adminId)
        let cleanPw = sanitizeCredential(adminPassword)

        if useKnsLogin {
            if cleanId.isEmpty || cleanPw.isEmpty {
                onError?("KNS login requires an administrator ID and password")
                status = .disconnected; onStatusChange?(status); return
            }
            if !isASCII(cleanId) || !isASCII(cleanPw) {
                onError?("KNS login currently supports ASCII administrator ID/password only")
                status = .disconnected; onStatusChange?(status); return
            }
            if cleanId.utf8.count > 32 || cleanPw.utf8.count > 32 {
                onError?("KNS login credentials must be 32 characters or fewer")
                status = .disconnected; onStatusChange?(status); return
            }
        }

        // Run teardown synchronously so the generation counter is updated before we
        // start the background thread. connect() is always called from the main thread,
        // so queue.sync is safe here (no deadlock risk).
        var myGeneration = 0
        queue.sync { [weak self] in
            guard let self else { return }
            self.teardown()
            self.useUTF16LE = preferUTF16LE
            self.didRetryEncoding = preferUTF16LE
            self.hasReceivedFrame = false
            self.stopEncodingProbe()
            self.useKnsLogin = useKnsLogin
            self.accountType = accountType
            self.adminId = cleanId
            self.adminPassword = cleanPw
            self.currentHost = host
            self.currentPort = port
            self.status = .connecting
            self.onStatusChange?(self.status)
            self.onLog?("Connecting to \(host):\(port)")
            self.startConnectTimeout()
            myGeneration = self.connectGeneration
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.openSocket(host: host, port: port, generation: myGeneration)
        }
    }

    func disconnect() {
        queue.async { [weak self] in self?.handleDisconnect() }
    }

    func send(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let fd = self.socketFD
            guard fd >= 0 else { self.onError?("Not connected"); return }
            self.onLog?("TX: \(self.redactedForLog(command))")
            self.writeDirect(command, fd: fd)
        }
    }

    // MARK: - Socket open (runs on a global background thread)

    private func openSocket(host: String, port: UInt16, generation: Int) {
        // DNS resolution (blocking). Force AF_INET — the TS-890S is an IPv4 LAN device.
        // Using AF_UNSPEC can return an IPv6 address first on macOS, causing EHOSTUNREACH
        // on a LAN that has no IPv6 routing.
        var hints = addrinfo()
        hints.ai_family   = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let gaiErr = getaddrinfo(host, "\(port)", &hints, &res)
        guard gaiErr == 0, let addrList = res else {
            let msg = gaiErr != 0 ? String(cString: gai_strerror(gaiErr)) : "no address found"
            queue.async { [weak self] in
                guard let self, self.connectGeneration == generation else { return }
                self.onError?("DNS resolution failed for \(host): \(msg)")
                self.handleDisconnect()
            }
            return
        }
        defer { freeaddrinfo(res) }

        // Create IPv4 socket.
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            let err = errno
            queue.async { [weak self] in
                guard let self, self.connectGeneration == generation else { return }
                self.onError?("socket() failed (errno \(err))")
                self.handleDisconnect()
            }
            return
        }

        // Suppress SIGPIPE on writes to a closed socket.
        var one: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE,
                          &one, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE,
                          &one, socklen_t(MemoryLayout<Int32>.size))

        // Register fd on the queue so teardown() can close it to abort a blocking connect.
        // Check generation to reject stale calls.
        var proceed = false
        queue.sync { [weak self] in
            guard let self, self.connectGeneration == generation else {
                Darwin.close(fd)
                return
            }
            self.socketFD = fd
            proceed = true
        }
        guard proceed else { return }

        // Blocking connect — unblocked by Darwin.close(fd) if teardown() fires.
        let connectResult = Darwin.connect(fd, addrList.pointee.ai_addr, addrList.pointee.ai_addrlen)
        let connectErrno = errno

        queue.async { [weak self] in
            guard let self else { return }
            // If teardown() ran while we were in connect(), socketFD will no longer be `fd`.
            guard self.socketFD == fd else { return }

            guard connectResult == 0 else {
                Darwin.close(fd)
                self.socketFD = -1
                if self.status == .connecting {
                    self.onError?("Connection failed: \(String(cString: strerror(connectErrno)))")
                    self.handleDisconnect()
                }
                return
            }

            // Successfully connected — start KNS handshake or go straight to connected.
            self.stopConnectTimeout()

            if self.useKnsLogin {
                self.authState = .sentCN
                self.status = .authenticating
                self.onStatusChange?(self.status)
                let cnCmd = KenwoodKNS.knsConnect()
                let enc = self.useUTF16LE ? "UTF-16LE" : "UTF-8"
                let cnData = self.useUTF16LE
                    ? (cnCmd.data(using: .utf16LittleEndian) ?? Data())
                    : Data(cnCmd.utf8)
                let cnHex = cnData.map { String(format: "%02x", $0) }.joined(separator: " ")
                self.onLog?("KNS: Sending ##CN (\(enc)) — TX raw: \(cnHex)")
                self.writeDirect(cnCmd, fd: fd)
                self.startAuthTimeout()
            } else {
                self.status = .connected
                self.onStatusChange?(self.status)
                self.onLog?("Connected without KNS login")
                self.onLog?("Enabling Auto Information (AI)")
                self.writeDirect(KenwoodCAT.setAutoInformation(.onNonPersistent), fd: fd)
                self.startKeepalive()
                // Start encoding probe: if no frames arrive within 3s, the radio
                // may need UTF-16LE (TS-990S). Switch and re-send initial commands.
                self.startEncodingProbe()
            }

            // Start dedicated receive thread.
            Thread.detachNewThread { [weak self] in
                self?.receiveLoop(fd: fd)
            }
        }
    }

    // MARK: - Receive loop (dedicated thread — blocks on recv())

    private func receiveLoop(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, 4096, 0)
            if n <= 0 {
                let err = errno
                queue.async { [weak self] in
                    guard let self, self.socketFD == fd else { return } // deliberate teardown — ignore
                    Darwin.close(fd)
                    self.socketFD = -1
                    let errMsg = n == 0
                        ? "Connection closed by radio"
                        : "Receive error: \(String(cString: strerror(err))) (errno \(err))"
                    self.onLog?("Socket recv returned \(n), errno=\(err), authState=\(self.authState)")
                    self.onError?(errMsg)
                    self.handleDisconnect()
                }
                return
            }
            let chunk = Data(buf[0..<n])
            queue.async { [weak self] in
                guard let self, self.socketFD == fd else { return }
                // During auth phase, log raw hex so we can diagnose protocol issues
                // with radios we can't physically test (e.g. TS-990S).
                if self.authState != .authenticated {
                    let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
                    self.onLog?("RX raw (\(n) bytes): \(hex)")

                    // Auto-detect UTF-16LE: if the response has 0x00 bytes at every odd
                    // position, this is a UTF-16LE radio (TS-990S). Switch encoding and
                    // auto-retry the connection once.
                    if !self.useUTF16LE && !self.didRetryEncoding
                        && chunk.count >= 4 && chunk.count % 2 == 0 {
                        let looksUTF16 = stride(from: 1, to: chunk.count, by: 2)
                            .allSatisfy { chunk[$0] == 0x00 }
                        if looksUTF16 {
                            self.onLog?("Detected UTF-16LE encoding — radio is likely a TS-990S")
                            self.useUTF16LE = true
                            self.didRetryEncoding = true
                            // Tear down and reconnect with UTF-16LE encoding.
                            self.retryWithUTF16LE()
                            return
                        }
                    }
                }
                self.receiveBuffer.append(chunk)
                self.flushFrames()
            }
        }
    }

    // MARK: - Internal state transitions (must be called on `queue`)

    private func handleDisconnect() {
        teardown()
        status = .disconnected
        onStatusChange?(status)
        onLog?("Disconnected")
    }

    /// Tear down the current connection and immediately reconnect using UTF-16LE
    /// encoding. Called once when the first auth response reveals UTF-16LE bytes.
    /// Must be called on `queue`.
    private func retryWithUTF16LE() {
        let host = currentHost ?? ""
        let port = currentPort
        guard !host.isEmpty else { return }

        onLog?("Reconnecting to \(host):\(port) with UTF-16LE encoding")
        teardown()
        status = .connecting
        onStatusChange?(status)
        startConnectTimeout()
        let gen = connectGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.openSocket(host: host, port: port, generation: gen)
        }
    }

    /// Write raw bytes directly to fd. Must be called on `queue` (or from openSocket
    /// before the recv thread starts, while holding implicit queue context).
    /// Uses UTF-16LE encoding when communicating with a TS-990S.
    private func writeDirect(_ command: String, fd: Int32) {
        let data: Data
        if useUTF16LE {
            guard let encoded = command.data(using: .utf16LittleEndian) else {
                onError?("Failed to encode command as UTF-16LE")
                return
            }
            data = encoded
        } else {
            data = Data(command.utf8)
        }
        data.withUnsafeBytes { rawPtr in
            guard let base = rawPtr.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let n = Darwin.send(fd, base + offset, data.count - offset, 0)
                guard n > 0 else { return }
                offset += n
            }
        }
    }

    // MARK: - Frame parsing

    private func flushFrames() {
        // TS-990S uses UTF-16LE on the wire — the semicolon delimiter is 0x3B 0x00.
        // TS-890S and others use UTF-8 where the delimiter is a single 0x3B.
        let delimiter: Data = useUTF16LE ? Data([0x3B, 0x00]) : Data([UInt8(ascii: ";")])

        while let separatorRange = receiveBuffer.firstRange(of: delimiter) {
            let frameData = receiveBuffer.subdata(in: 0..<separatorRange.lowerBound)
            receiveBuffer.removeSubrange(0..<separatorRange.upperBound)
            let frame: String
            if useUTF16LE {
                guard let decoded = String(data: frameData, encoding: .utf16LittleEndian) else { continue }
                frame = decoded
            } else if let decoded = String(data: frameData, encoding: .utf8) {
                frame = decoded
            } else if let decoded = String(data: frameData, encoding: .isoLatin1) {
                frame = decoded
            } else {
                frame = String(decoding: frameData, as: UTF8.self)
            }
            // Normalize control characters that some bridges insert between frames.
            let cleaned = frame.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            guard !cleaned.isEmpty else { continue }
            let fullFrame = cleaned.hasSuffix(";") ? cleaned : (cleaned + ";")
            hasReceivedFrame = true

            if fullFrame.hasPrefix("##DD2") {
                onLog?("RX: ##DD2... (\(fullFrame.count) chars)")
                let payload = fullFrame.dropFirst(5).dropLast()
                if payload.count == 1280 {
                    var points = [UInt8]()
                    points.reserveCapacity(640)
                    var idx = payload.startIndex
                    while idx < payload.endIndex {
                        let next = payload.index(idx, offsetBy: 2, limitedBy: payload.endIndex) ?? payload.endIndex
                        if let v = UInt8(payload[idx..<next], radix: 16) { points.append(v) }
                        idx = next
                    }
                    if points.count == 640 { onScopeData?(points) }
                }
                handleAuthFrame(fullFrame)
                continue
            }
            if fullFrame.hasPrefix("##DD3") {
                onLog?("RX: ##DD3... (\(fullFrame.count) chars)")
                handleAuthFrame(fullFrame)
                continue
            }

            onLog?("RX: \(fullFrame)")
            handleAuthFrame(fullFrame)
            onFrame?(fullFrame)
        }
    }

    private func handleAuthFrame(_ frame: String) {
        let normalized = frame.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        switch authState {
        case .sentCN:
            if normalized.hasPrefix("##CN1") {
                authState = .sentID
                let fd = socketFD
                if fd >= 0 {
                    let idCmd = KenwoodKNS.knsLogin(accountType: accountType,
                                                    account: adminId,
                                                    password: adminPassword)
                    let enc = useUTF16LE ? "UTF-16LE" : "UTF-8"
                    let idData = useUTF16LE
                        ? (idCmd.data(using: .utf16LittleEndian) ?? Data())
                        : Data(idCmd.utf8)
                    let idHex = idData.map { String(format: "%02x", $0) }.joined(separator: " ")
                    onLog?("KNS: Sending ##ID (\(enc)) — TX raw: \(idHex)")
                    writeDirect(idCmd, fd: fd)
                }
            } else if normalized.hasPrefix("##CN0") {
                onLog?("KNS: Connect rejected (##CN0) — session may still be active")
                onError?("KNS connect rejected — the radio may still have an active session. Wait a few seconds and try again.")
                handleDisconnect()
            }
        case .sentID:
            if normalized.hasPrefix("##ID1") {
                authState = .authenticated
                stopAuthTimeout()
                status = .connected
                onStatusChange?(status)
                onLog?("KNS: Authenticated")
                onLog?("Enabling Auto Information (AI)")
                let fd = socketFD
                if fd >= 0 {
                    writeDirect(KenwoodCAT.setAutoInformation(.onNonPersistent), fd: fd)
                }
                startKeepalive()
            } else if normalized.hasPrefix("##ID0") {
                onLog?("KNS: Authentication failed")
                onError?("KNS authentication failed — check Admin ID and password")
                handleDisconnect()
            }
        default:
            break
        }
    }

    // MARK: - Timers (fire on `queue`)

    private func startConnectTimeout() {
        stopConnectTimeout()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + connectTimeoutInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.status == .connecting else { return }
            let host = self.currentHost ?? "unknown"
            self.onError?("Connection timed out — radio unreachable at \(host)")
            self.handleDisconnect()
        }
        connectTimeoutTimer = timer
        timer.resume()
    }

    private func stopConnectTimeout() {
        connectTimeoutTimer?.cancel()
        connectTimeoutTimer = nil
    }

    private func startAuthTimeout() {
        stopAuthTimeout()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + authTimeoutInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.authState != .authenticated {
                self.onLog?("KNS: Authentication timed out")
                self.onError?("KNS authentication timed out")
                self.handleDisconnect()
            }
        }
        authTimeoutTimer = timer
        timer.resume()
    }

    private func stopAuthTimeout() {
        authTimeoutTimer?.cancel()
        authTimeoutTimer = nil
    }

    private func startKeepalive() {
        stopKeepalive()
        var tickCount = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + keepaliveInterval, repeating: keepaliveInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.socketFD >= 0 else { return }
            let fd = self.socketFD
            self.onLog?("TX: \(self.redactedForLog(KenwoodCAT.getVFOAFrequency()))")
            self.writeDirect(KenwoodCAT.getVFOAFrequency(), fd: fd)
            switch tickCount % 2 {
            case 0:
                self.writeDirect(KenwoodCAT.getAFGain(), fd: fd)
                self.writeDirect(KenwoodCAT.getRFGain(), fd: fd)
            default:
                self.writeDirect(KenwoodCAT.getSquelchLevel(), fd: fd)
            }
            // Re-assert AI4 every 30 s (every 6th tick) in case the radio reset it
            // (e.g. after a menu save, firmware quirk, or brief power glitch).
            if tickCount % 6 == 5 {
                self.writeDirect(KenwoodCAT.setAutoInformation(.onNonPersistent), fd: fd)
            }
            tickCount += 1
        }
        keepaliveTimer = timer
        timer.resume()
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    // MARK: - Encoding probe (non-KNS connections)

    /// After a non-KNS TCP connect, if no CAT frames arrive within 3 seconds
    /// the radio may need UTF-16LE encoding (TS-990S). Switch encoding and
    /// re-send the initial commands. Only fires once.
    private func startEncodingProbe() {
        stopEncodingProbe()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + encodingProbeInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.hasReceivedFrame, !self.useUTF16LE, !self.didRetryEncoding else { return }
            let fd = self.socketFD
            guard fd >= 0 else { return }

            self.onLog?("No frames received in \(self.encodingProbeInterval)s — switching to UTF-16LE")
            self.useUTF16LE = true
            self.didRetryEncoding = true

            // Re-send initial commands in UTF-16LE so the radio starts responding.
            self.onLog?("Re-sending AI + ID in UTF-16LE")
            self.writeDirect(KenwoodCAT.setAutoInformation(.onNonPersistent), fd: fd)
            self.writeDirect("ID;", fd: fd)
            // The keepalive timer is already running and will now send in UTF-16LE too.
        }
        encodingProbeTimer = timer
        timer.resume()
    }

    private func stopEncodingProbe() {
        encodingProbeTimer?.cancel()
        encodingProbeTimer = nil
    }
}

extension TS890Connection: CATTransport {}
