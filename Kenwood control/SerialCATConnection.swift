import Foundation

// IOSSIOSPEED: macOS-specific ioctl to set non-standard baud rates on USB serial adapters.
// Required for CP210x (Silicon Labs) and FTDI devices whose kexts reject cfsetspeed via tcsetattr.
// Value: _IOW('T', 2, speed_t) = 0x80085402 on 64-bit macOS (speed_t = unsigned long = 8 bytes).
private let IOSSIOSPEED: UInt = 0x80085402

/// USB serial CAT transport for the TS-890S (and similar Kenwood radios).
///
/// Opens a POSIX serial port at 115200 baud 8N1, then exchanges raw CAT command
/// strings using the same semicolon-framing as the LAN transport.
/// No KNS authentication is needed; the radio responds to CAT immediately.
final class SerialCATConnection: CATTransport {

    // MARK: - CATTransport callbacks

    var onStatusChange: ((CATConnectionStatus) -> Void)?
    var onError:        ((String) -> Void)?
    var onFrame:        ((String) -> Void)?
    var onLog:          ((String) -> Void)?

    private(set) var status: CATConnectionStatus = .disconnected

    // MARK: - Private state

    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "SerialCATConnection.queue", qos: .userInitiated)
    private var readSource: DispatchSourceRead?
    private var receiveBuffer = Data()
    private var keepaliveTimer: DispatchSourceTimer?
    private let keepaliveInterval: TimeInterval = 5

    // MARK: - Connect

    func connect(portPath: String, baudRate: speed_t = 115_200) {
        queue.async { [weak self] in
            guard let self else { return }
            self.teardownInternal()
            self.setStatus(.connecting)
            self.log("Serial: opening \(portPath) at \(baudRate) baud")

            // Open the device
            let openFd = open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard openFd >= 0 else {
                self.reportError("Cannot open \(portPath): \(String(cString: strerror(errno)))")
                self.setStatus(.disconnected)
                return
            }

            // Configure 8N1, 115200 baud.
            //
            // macOS 15 DriverKit CP2102N quirks:
            //   • O_NONBLOCK causes tcsetattr to return EPERM — clear it first
            //   • TIOCEXCL grants exclusive access; some drivers need this before config
            //   • tcsetattr and IOSSIOSPEED may both still return EPERM on DriverKit
            //   • Proceed regardless — DriverKit driver holds baud rate from USB enumeration
            let savedFlags = fcntl(openFd, F_GETFL)
            _ = fcntl(openFd, F_SETFL, savedFlags & ~O_NONBLOCK)
            _ = ioctl(openFd, TIOCEXCL)

            var tio = termios()
            tcgetattr(openFd, &tio)
            cfmakeraw(&tio)
            cfsetspeed(&tio, baudRate)
            tio.c_cflag |= tcflag_t(CS8 | CREAD | CLOCAL)
            tio.c_cflag &= ~tcflag_t(HUPCL)
            tio.c_iflag = 0
            tio.c_oflag = 0
            if tcsetattr(openFd, TCSANOW, &tio) != 0 {
                self.log("Serial: tcsetattr warning errno=\(errno) — trying IOSSIOSPEED")
                var speed = baudRate
                if ioctl(openFd, IOSSIOSPEED, &speed) != 0 {
                    self.log("Serial: IOSSIOSPEED warning errno=\(errno) — proceeding at driver-default baud rate")
                }
            }

            _ = fcntl(openFd, F_SETFL, savedFlags | O_NONBLOCK)

            self.fd = openFd
            self.setStatus(.connected)
            self.log("Serial: connected on \(portPath)")

            // Enable Auto Information so the radio pushes state changes to us
            self.sendRaw(KenwoodCAT.setAutoInformation(.onNonPersistent))

            // Watch for incoming bytes via GCD
            let src = DispatchSource.makeReadSource(fileDescriptor: openFd, queue: self.queue)
            src.setEventHandler { [weak self] in self?.readAvailable() }
            src.setCancelHandler { [weak self] in
                guard let self, self.fd >= 0 else { return }
                close(self.fd)
                self.fd = -1
            }
            self.readSource = src
            src.resume()
            self.startKeepalive()
        }
    }

    // MARK: - CATTransport

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.teardownInternal()
            self.setStatus(.disconnected)
            self.log("Serial: disconnected")
        }
    }

    func send(_ command: String) {
        log("TX: \(command)")
        sendRaw(command)
    }

    // MARK: - Internal

    private func sendRaw(_ command: String) {
        queue.async { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var data = Data(command.utf8)
            data.withUnsafeBytes { ptr in
                _ = write(self.fd, ptr.baseAddress!, ptr.count)
            }
        }
    }

    private func teardownInternal() {
        stopKeepalive()
        readSource?.cancel()
        readSource = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        // fd is closed asynchronously in the DispatchSource cancel handler
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(fd, &buf, buf.count)
        if n > 0 {
            receiveBuffer.append(contentsOf: buf[0..<n])
            flushFrames()
        } else if n == 0 || (n < 0 && errno != EAGAIN) {
            reportError("Serial read error (errno \(errno))")
            teardownInternal()
            setStatus(.disconnected)
        }
    }

    private func flushFrames() {
        while let sepRange = receiveBuffer.firstRange(of: Data([UInt8(ascii: ";")])) {
            let frameData = receiveBuffer.subdata(in: 0..<sepRange.lowerBound)
            receiveBuffer.removeSubrange(0...sepRange.lowerBound)

            let frame: String
            if      let s = String(data: frameData, encoding: .utf8)       { frame = s }
            else if let s = String(data: frameData, encoding: .isoLatin1)  { frame = s }
            else                                                            { frame = String(decoding: frameData, as: UTF8.self) }

            let cleaned = frame.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            guard !cleaned.isEmpty else { continue }
            let fullFrame = cleaned.hasSuffix(";") ? cleaned : (cleaned + ";")
            log("RX: \(fullFrame)")
            onFrame?(fullFrame)
        }
    }

    // MARK: - Keepalive (polls radio state the same way as the LAN transport)

    private func startKeepalive() {
        stopKeepalive()
        var tickCount = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + keepaliveInterval, repeating: keepaliveInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendRaw(KenwoodCAT.getVFOAFrequency())
            switch tickCount % 2 {
            case 0: self.sendRaw(KenwoodCAT.getAFGain()); self.sendRaw(KenwoodCAT.getRFGain())
            default: self.sendRaw(KenwoodCAT.getSquelchLevel())
            }
            tickCount += 1
        }
        keepaliveTimer = t
        t.resume()
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    // MARK: - Helpers

    private func setStatus(_ s: CATConnectionStatus) {
        status = s
        onStatusChange?(s)
    }

    private func log(_ msg: String)         { onLog?(msg) }
    private func reportError(_ msg: String) { onError?(msg) }
}
