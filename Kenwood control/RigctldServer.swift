import Foundation
import Network

// MARK: - RigctldServer
//
// A rigctld-compatible TCP server (Hamlib NET rigctl protocol, protocol level 0).
// Lets WSJT-X, fldigi, JS8Call, flrig, and TillyMac connect to TS-890 Pro as their
// radio backend without any additional radio connection.
//
// All RadioState reads and writes happen on the main thread.
// TCP listener and per-client I/O run on a dedicated background queue.
//
// Minimum viable command set:
//   f/F  — VFO A frequency
//   m/M  — operating mode + passband
//   t/T  — PTT
//   v/V  — active VFO
//   s/S  — split (RX/TX VFO pairing)
//   i/I  — RIT offset
//   j/J  — XIT offset
//   l/L  — levels: RFPOWER, AF, RFGAIN, SMETER
//   u/U  — functions: NR, NB, ANF
//   \dump_state, \chk_vfo, \get_info
//   q    — close connection

final class RigctldServer {

    // MARK: - Hamlib mode bitmask values (rig.h)
    // Used in dump_state to advertise supported modes.
    private enum HamlibMode {
        static let am:     UInt32 = 1 << 0   // 0x001
        static let cw:     UInt32 = 1 << 1   // 0x002
        static let usb:    UInt32 = 1 << 2   // 0x004
        static let lsb:    UInt32 = 1 << 3   // 0x008
        static let rtty:   UInt32 = 1 << 4   // 0x010
        static let fm:     UInt32 = 1 << 5   // 0x020
        static let cwr:    UInt32 = 1 << 7   // 0x080
        static let rttyr:  UInt32 = 1 << 8   // 0x100
        static let pktlsb: UInt32 = 1 << 10  // 0x400
        static let pktusb: UInt32 = 1 << 11  // 0x800
        static let pktfm:  UInt32 = 1 << 12  // 0x1000
        // All modes supported by TS-890S
        static let all: UInt32 = am | cw | usb | lsb | rtty | fm | cwr | rttyr | pktlsb | pktusb | pktfm
    }

    // MARK: - Mode mapping: TS-890S OperatingMode <-> rigctld mode string

    static let modeToRigctld: [KenwoodCAT.OperatingMode: String] = [
        .lsb:     "LSB",
        .usb:     "USB",
        .cw:      "CW",
        .fm:      "FM",
        .am:      "AM",
        .fsk:     "RTTY",
        .cwR:     "CWR",
        .fskR:    "RTTYR",
        .psk:     "PKTLSB",
        .pskR:    "PKTUSB",
        .lsbData: "PKTLSB",
        .usbData: "PKTUSB",
        .fmData:  "PKTFM",
        .amData:  "AM",
    ]

    static let rigctldToMode: [String: KenwoodCAT.OperatingMode] = [
        "LSB":    .lsb,
        "USB":    .usb,
        "CW":     .cw,
        "CWR":    .cwR,
        "RTTY":   .fsk,
        "RTTYR":  .fskR,
        "AM":     .am,
        "FM":     .fm,
        "WFM":    .fm,
        "AMS":    .am,
        "DSB":    .usb,
        "PKTLSB": .lsbData,
        "PKTUSB": .usbData,
        "PKTFM":  .fmData,
    ]

    // MARK: - Public API

    static let defaultPort: UInt16 = 4532

    /// Weak reference to the app's RadioState — all radio I/O goes through here.
    weak var radioState: RadioState?

    /// Called on the main thread when server events occur (start, stop, client connect, errors).
    var onLog: ((String) -> Void)?

    var isRunning: Bool { listener?.state == .ready }

    // MARK: - Private state

    private var listener: NWListener?
    private var clients: [UUID: ClientSession] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.w9fyi.ts890pro.rigctld", qos: .utility)

    // MARK: - Lifecycle

    init(radioState: RadioState) {
        self.radioState = radioState
    }

    nonisolated deinit {}

    func start(port: UInt16 = defaultPort) {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log("invalid port \(port)")
            return
        }
        do {
            let l = try NWListener(using: params, on: nwPort)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.log("listening on port \(port)")
                case .failed(let err):
                    self?.log("listener error: \(err)")
                    self?.stop()
                default:
                    break
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            log("start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let all = Array(clients.values)
        clients.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
        log("stopped")
    }

    // MARK: - Client management

    private func accept(_ conn: NWConnection) {
        let session = ClientSession(connection: conn, server: self)
        lock.lock()
        clients[session.id] = session
        lock.unlock()
        session.start(queue: queue)
        log("client connected [\(session.id)]")
    }

    func removeClient(_ id: UUID) {
        lock.lock()
        clients.removeValue(forKey: id)
        lock.unlock()
        log("client disconnected [\(id)]")
    }

    // MARK: - Command dispatch (must be called on main thread)
    //
    // Returns (response, quit). If quit==true the session should close after sending.

    func dispatch(_ cmd: String) -> (response: String, quit: Bool) {
        guard let radio = radioState else { return ("RPRT -1\n", false) }

        // Split on whitespace — at most 3 parts so long NB/NR values are kept intact.
        let parts = cmd.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            .map(String.init)
        let verb = parts.first ?? ""

        switch verb {

        // ── Get frequency ───────────────────────────────────────────
        case "f", "\\get_freq", "get_freq":
            let hz = radio.vfoAFrequencyHz ?? 0
            return ("\(hz)\nRPRT 0\n", false)

        // ── Set frequency ───────────────────────────────────────────
        case "F", "\\set_freq", "set_freq":
            guard let hzStr = parts.dropFirst().first, let hz = Int(hzStr) else {
                return ("RPRT -1\n", false)
            }
            radio.send(KenwoodCAT.setVFOAFrequencyHz(hz))
            return ("RPRT 0\n", false)

        // ── Get mode ────────────────────────────────────────────────
        case "m", "\\get_mode", "get_mode":
            let modeStr = radio.operatingMode.flatMap { Self.modeToRigctld[$0] } ?? "USB"
            let bw = defaultPassbandHz(for: radio.operatingMode)
            return ("\(modeStr)\n\(bw)\nRPRT 0\n", false)

        // ── Set mode ────────────────────────────────────────────────
        case "M", "\\set_mode", "set_mode":
            guard parts.count >= 2 else { return ("RPRT -1\n", false) }
            let modeStr = parts[1].uppercased()
            guard let mode = Self.rigctldToMode[modeStr] else { return ("RPRT -1\n", false) }
            radio.send(KenwoodCAT.setOperatingMode(mode))
            return ("RPRT 0\n", false)

        // ── Get PTT ─────────────────────────────────────────────────
        case "t", "\\get_ptt", "get_ptt":
            return ("\(radio.isPTTDown ? 1 : 0)\nRPRT 0\n", false)

        // ── Set PTT ─────────────────────────────────────────────────
        case "T", "\\set_ptt", "set_ptt":
            guard let valStr = parts.dropFirst().first, let val = Int(valStr) else {
                return ("RPRT -1\n", false)
            }
            if val == 1 {
                radio.send(KenwoodCAT.pttDown())
                radio.isAppPTTActive = true
            } else {
                radio.send(KenwoodCAT.pttUp())
                radio.isAppPTTActive = false
            }
            return ("RPRT 0\n", false)

        // ── Get VFO ─────────────────────────────────────────────────
        case "v", "\\get_vfo", "get_vfo":
            let vfoName = (radio.rxVFO == .b) ? "VFOB" : "VFOA"
            return ("\(vfoName)\nRPRT 0\n", false)

        // ── Set VFO ─────────────────────────────────────────────────
        case "V", "\\set_vfo", "set_vfo":
            guard let vfoStr = parts.dropFirst().first else { return ("RPRT -1\n", false) }
            let vfo: KenwoodCAT.VFO = vfoStr.uppercased() == "VFOB" ? .b : .a
            radio.send(KenwoodCAT.setReceiverVFO(vfo))
            return ("RPRT 0\n", false)

        // ── Get split ───────────────────────────────────────────────
        case "s", "\\get_split_vfo", "get_split_vfo":
            let isSplit = (radio.rxVFO != nil && radio.txVFO != nil && radio.rxVFO != radio.txVFO)
                       || (radio.splitOffsetSettingActive == true)
            let txHz = radio.vfoBFrequencyHz ?? radio.vfoAFrequencyHz ?? 0
            return ("\(isSplit ? 1 : 0)\n\(txHz)\nRPRT 0\n", false)

        // ── Set split ───────────────────────────────────────────────
        case "S", "\\set_split_vfo", "set_split_vfo":
            guard parts.count >= 2, let val = Int(parts[1]) else { return ("RPRT -1\n", false) }
            if val == 0 {
                radio.send(KenwoodCAT.setReceiverVFO(.a))
                radio.send(KenwoodCAT.setTransmitterVFO(.a))
            } else {
                radio.send(KenwoodCAT.setReceiverVFO(.a))
                radio.send(KenwoodCAT.setTransmitterVFO(.b))
            }
            return ("RPRT 0\n", false)

        // ── Get RIT ─────────────────────────────────────────────────
        case "i", "\\get_rit", "get_rit":
            let offset = (radio.ritEnabled == true) ? (radio.ritXitOffsetHz ?? 0) : 0
            return ("\(offset)\nRPRT 0\n", false)

        // ── Set RIT ─────────────────────────────────────────────────
        case "I", "\\set_rit", "set_rit":
            guard let hzStr = parts.dropFirst().first, let hz = Int(hzStr) else {
                return ("RPRT -1\n", false)
            }
            radio.send(KenwoodCAT.ritSetEnabled(hz != 0))
            if hz != 0 { radio.send(KenwoodCAT.ritXitSetOffsetHz(hz)) }
            return ("RPRT 0\n", false)

        // ── Get XIT ─────────────────────────────────────────────────
        case "j", "\\get_xit", "get_xit":
            let offset = (radio.xitEnabled == true) ? (radio.ritXitOffsetHz ?? 0) : 0
            return ("\(offset)\nRPRT 0\n", false)

        // ── Set XIT ─────────────────────────────────────────────────
        case "J", "\\set_xit", "set_xit":
            guard let hzStr = parts.dropFirst().first, let hz = Int(hzStr) else {
                return ("RPRT -1\n", false)
            }
            radio.send(KenwoodCAT.xitSetEnabled(hz != 0))
            if hz != 0 { radio.send(KenwoodCAT.ritXitSetOffsetHz(hz)) }
            return ("RPRT 0\n", false)

        // ── Get level ───────────────────────────────────────────────
        case "l", "\\get_level", "get_level":
            return (getLevel(parts.dropFirst().first ?? "", radio: radio), false)

        // ── Set level ───────────────────────────────────────────────
        case "L", "\\set_level", "set_level":
            return (setLevel(Array(parts.dropFirst()), radio: radio), false)

        // ── Get func ────────────────────────────────────────────────
        case "u", "\\get_func", "get_func":
            return (getFunc(parts.dropFirst().first ?? "", radio: radio), false)

        // ── Set func ────────────────────────────────────────────────
        case "U", "\\set_func", "set_func":
            return (setFunc(Array(parts.dropFirst()), radio: radio), false)

        // ── Extended / special ──────────────────────────────────────
        case "\\dump_state", "dump_state":
            return (makeDumpState(), false)

        case "\\chk_vfo", "chk_vfo":
            // CHKVFO 0 = server does NOT require a VFO parameter on every command
            return ("CHKVFO 0\nRPRT 0\n", false)

        case "\\get_info", "get_info":
            return ("Kenwood TS-890S (TS-890 Pro)\nRPRT 0\n", false)

        case "\\get_powerstat", "get_powerstat":
            let on = radio.isPoweredOn ?? true
            return ("\(on ? 1 : 0)\nRPRT 0\n", false)

        case "\\set_powerstat", "set_powerstat":
            if let valStr = parts.dropFirst().first, let val = Int(valStr) {
                radio.send(KenwoodCAT.setPower(val != 0))
            }
            return ("RPRT 0\n", false)

        case "\\get_ant", "get_ant":
            let ant = radio.antennaPort ?? 1
            return ("\(ant)\nRPRT 0\n", false)

        case "q", "Q":
            return ("RPRT 0\n", true)

        default:
            log("unknown command: \(cmd)")
            return ("RPRT -1\n", false)
        }
    }

    // MARK: - Level helpers

    private func getLevel(_ param: String, radio: RadioState) -> String {
        switch param.uppercased() {
        case "RFPOWER":
            let watts = Double(radio.outputPowerWatts ?? 100)
            return String(format: "%.6f\nRPRT 0\n", (watts / 100.0).clamped(to: 0...1))
        case "AF":
            let af = Double(radio.afGain ?? 128)
            return String(format: "%.6f\nRPRT 0\n", (af / 255.0).clamped(to: 0...1))
        case "RFGAIN":
            let rg = Double(radio.rfGain ?? 255)
            return String(format: "%.6f\nRPRT 0\n", (rg / 255.0).clamped(to: 0...1))
        case "SMETER":
            let raw = radio.meterReadings[0] ?? 0.0
            return String(format: "%.6f\nRPRT 0\n", smeterRigctldValue(fromRaw: raw))
        case "RAWSTR":
            let raw = radio.meterReadings[0] ?? 0.0
            return String(format: "%.6f\nRPRT 0\n", raw)
        case "SWR":
            let swr = radio.meterReadings[3] ?? 1.0
            return String(format: "%.6f\nRPRT 0\n", swr)
        case "ALC":
            let alc = radio.meterReadings[2] ?? 0.0
            return String(format: "%.6f\nRPRT 0\n", alc)
        case "COMP":
            let comp = radio.meterReadings[1] ?? 0.0
            return String(format: "%.6f\nRPRT 0\n", comp)
        default:
            return "RPRT -1\n"
        }
    }

    private func setLevel(_ parts: [String], radio: RadioState) -> String {
        guard parts.count >= 2 else { return "RPRT -1\n" }
        let param = parts[0].uppercased()
        guard let val = Double(parts[1]) else { return "RPRT -1\n" }
        switch param {
        case "RFPOWER":
            radio.send(KenwoodCAT.setOutputPowerWatts(Int((val * 100.0).clamped(to: 5...100))))
        case "AF":
            radio.send(KenwoodCAT.setAFGain(Int((val * 255.0).clamped(to: 0...255))))
        case "RFGAIN":
            radio.send(KenwoodCAT.setRFGain(Int((val * 255.0).clamped(to: 0...255))))
        default:
            return "RPRT -1\n"
        }
        return "RPRT 0\n"
    }

    // MARK: - Function helpers

    private func getFunc(_ param: String, radio: RadioState) -> String {
        switch param.uppercased() {
        case "NR":
            let nr = (radio.transceiverNRMode != nil && radio.transceiverNRMode != .off) ? 1 : 0
            return "\(nr)\nRPRT 0\n"
        case "NB":
            return "\(radio.noiseBlankerEnabled == true ? 1 : 0)\nRPRT 0\n"
        case "ANF":
            return "\(radio.isNotchEnabled == true ? 1 : 0)\nRPRT 0\n"
        default:
            return "RPRT -1\n"
        }
    }

    private func setFunc(_ parts: [String], radio: RadioState) -> String {
        guard parts.count >= 2 else { return "RPRT -1\n" }
        let param = parts[0].uppercased()
        guard let val = Int(parts[1]) else { return "RPRT -1\n" }
        switch param {
        case "NR":
            radio.send(KenwoodCAT.setNoiseReduction(val == 0 ? .off : .nr1))
        case "NB":
            radio.send(KenwoodCAT.setNoiseBlanker(enabled: val != 0))
        case "ANF":
            radio.send(KenwoodCAT.setNotch(enabled: val != 0))
        default:
            return "RPRT -1\n"
        }
        return "RPRT 0\n"
    }

    // MARK: - Passband width (best-guess default for each mode)

    private func defaultPassbandHz(for mode: KenwoodCAT.OperatingMode?) -> Int {
        switch mode {
        case .cw, .cwR:                     return 500
        case .fsk, .fskR:                   return 2400
        case .am, .amData:                  return 6000
        case .fm, .fmData:                  return 15000
        case .psk, .pskR, .lsbData, .usbData: return 3000
        default:                            return 2400
        }
    }

    // MARK: - S-meter conversion
    //
    // TS-890S SM: 0–30 units. 0=S0, 18=S9, 30=S9+24 dB (approx).
    // rigctld SMETER: 0.0=S0, 9.0=S9, 9+x = S9+x dB (e.g. 9.3 = S9+3dB).

    private func smeterRigctldValue(fromRaw raw: Double) -> Double {
        let dots = min(max(raw, 0), 30)
        if dots <= 18 {
            return dots * 9.0 / 18.0          // linear 0.0 – 9.0
        } else {
            return 9.0 + (dots - 18.0) * 2.0  // S9 + dB (each dot ≈ 2 dB above S9)
        }
    }

    // MARK: - dump_state
    //
    // Parsed by WSJT-X, fldigi, JS8Call, flrig on connect.
    // Format: Hamlib NET rigctl (protocol 0), with TS-890S band plan and capabilities.

    private func makeDumpState() -> String {
        let allModes = String(format: "0x%x", HamlibMode.all)
        // Frequency range line fields: start end modes low_power high_power vfo_bitmap ant_bitmap
        // vfo_bitmap: 0x10000003 = VFOA+VFOB+CURRFREQ; ant_bitmap: 0x3 = ANT1+ANT2
        let rxRange = "\(allModes) -1 -1 0x10000003 0x3"
        let txRange = "\(allModes) 5000 100000 0x10000003 0x3"

        var s = ""
        s += "0\n"                 // protocol version
        s += "2\n"                 // rig model (NET rigctl = 1; generic = 2)
        s += "4\n"                 // ITU region (1=Americas, 2=Europe, 3=Asia, 4=worldwide)

        // RX frequency ranges (each: start end modes low_pwr high_pwr vfo ant)
        s += "150000.000000 30000000.000000 \(rxRange)\n"
        s += "50000000.000000 54000000.000000 \(rxRange)\n"
        s += "0 0\n"               // end RX ranges

        // TX frequency ranges (US ham bands, HF + 6m)
        s += "1800000.000000 2000000.000000 \(txRange)\n"
        s += "3500000.000000 4000000.000000 \(txRange)\n"
        s += "7000000.000000 7300000.000000 \(txRange)\n"
        s += "10100000.000000 10150000.000000 \(txRange)\n"
        s += "14000000.000000 14350000.000000 \(txRange)\n"
        s += "18068000.000000 18168000.000000 \(txRange)\n"
        s += "21000000.000000 21450000.000000 \(txRange)\n"
        s += "24890000.000000 24990000.000000 \(txRange)\n"
        s += "28000000.000000 29700000.000000 \(txRange)\n"
        s += "50000000.000000 54000000.000000 \(txRange)\n"
        s += "0 0\n"               // end TX ranges

        // Tuning steps (mode_bitmap, step_hz) — end with 0 0
        s += "\(allModes) 1\n"
        s += "\(allModes) 10\n"
        s += "\(allModes) 100\n"
        s += "\(allModes) 1000\n"
        s += "0 0\n"

        // Filter list (mode_bitmap, width_hz) — end with 0 0
        s += "0x\(String(format: "%x", HamlibMode.usb | HamlibMode.lsb)) 3000\n"
        s += "0x\(String(format: "%x", HamlibMode.cw | HamlibMode.cwr)) 500\n"
        s += "0x\(String(format: "%x", HamlibMode.am)) 6000\n"
        s += "0x\(String(format: "%x", HamlibMode.fm)) 15000\n"
        s += "0x\(String(format: "%x", HamlibMode.rtty | HamlibMode.rttyr)) 2400\n"
        s += "0x\(String(format: "%x", HamlibMode.pktlsb | HamlibMode.pktusb | HamlibMode.pktfm)) 3000\n"
        s += "0 0\n"

        // Max RIT, max XIT, max IF-shift (Hz), announces bitmap
        s += "9999 9999 0 0\n"

        // Preamp list (gain dB values, 0-terminated)
        s += "12 0\n"
        // Attenuator list (attenuation dB values, 0-terminated)
        s += "6 12 18 0\n"

        // has_get_func, has_set_func, has_get_level, has_set_level, has_get_parm, has_set_parm
        // Advertise NR(0x02) + NB(0x04) + ANF(0x40) for func; RFPOWER(bit3) + AF(bit5) + RFGAIN(bit6) + SMETER(bit0) for level
        s += "0x46 0x46 0x7bff7fff 0x7bff7fff 0x0 0x0\n"

        s += "RPRT 0\n"
        return s
    }

    // MARK: - Logging

    func log(_ msg: String) {
        let full = "[rigctld] \(msg)"
        AppLogger.info(full)
        AppFileLogger.shared.log(full)
        DispatchQueue.main.async { [weak self] in self?.onLog?(full) }
    }
}

// MARK: - ClientSession

private final class ClientSession {

    let id = UUID()
    let connection: NWConnection
    weak var server: RigctldServer?
    private var buffer = Data()

    nonisolated deinit {}

    init(connection: NWConnection, server: RigctldServer) {
        self.connection = connection
        self.server = server
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        connection.cancel()
    }

    private func close() {
        server?.removeClient(id)
        connection.cancel()
    }

    // MARK: - Receive loop

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainLines()
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }

    private func drainLines() {
        while let nlIdx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<nlIdx]
            buffer.removeSubrange(buffer.startIndex...nlIdx)
            let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !line.isEmpty {
                handleCommand(line)
            }
        }
    }

    // MARK: - Command handling

    private func handleCommand(_ cmd: String) {
        guard let server else { close(); return }
        DispatchQueue.main.async { [weak self, weak server] in
            guard let self, let server else {
                self?.sendText("RPRT -1\n")
                return
            }
            let (response, quit) = server.dispatch(cmd)
            if quit {
                // Send final response then close
                let data = Data(response.utf8)
                self.connection.send(content: data, completion: .contentProcessed { [weak self] _ in
                    self?.close()
                })
            } else {
                self.sendText(response)
            }
        }
    }

    private func sendText(_ text: String) {
        connection.send(content: Data(text.utf8), completion: .idempotent)
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
