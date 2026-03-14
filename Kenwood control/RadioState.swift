import Foundation
import Observation
import CoreAudio
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

/// Holds live meter readings in a dedicated observable so that SM-frame
/// updates only re-render views that actually read meter data.
@Observable
final class MeterStore {
    static let shared = MeterStore()
    private init() {}
    var readings: [Int: Double] = [:]
}

/// Holds bandscope data in a dedicated observable so that high-rate ##DD2
/// frames (~5fps on LAN) only re-render the scope view.
@Observable
final class ScopeStore {
    static let shared = ScopeStore()
    private init() {}
    var points: [UInt8] = []
}

/// Holds diagnostic frame log strings in a dedicated observable.
@Observable
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()
    private init() {}
    var lastTXFrame: String = ""
    var lastRXFrame: String = ""
    var lastError: String? = nil
    var errorLog: [String] = []
    /// All CAT commands sent this session in order — used by unit tests.
    var txLog: [String] = []
}

struct MemoryChannel: Identifiable {
    let id: Int            // channel number 0–119
    var frequencyHz: Int
    var mode: KenwoodCAT.OperatingMode
    var name: String
    var isEmpty: Bool      // radio reports blank channel

    var frequencyMHz: String {
        String(format: "%.6f", Double(frequencyHz) / 1_000_000.0)
    }
}

@Observable
final class RadioState {
    enum ConnectionStatus: String { case disconnected = "Disconnected", connecting = "Connecting", authenticating = "Authenticating", connected = "Connected" }
    enum NoiseReductionProfile: String, CaseIterable {
        // Minimal, predictable presets. Users can fine-tune with NR Strength.
        case speech = "Speech"
        case staticHiss = "Static/Hiss"

        var recommendedStrength: Double {
            switch self {
            case .speech: return 0.60
            case .staticHiss: return 1.00
            }
        }
    }

    /// Whether the front-panel NR button controls the radio's built-in NR or the app's WDSP NR.
    enum NRButtonMode: String {
        case hardware  // uses NR CAT command (NR0/NR1/NR2)
        case software  // uses WDSP inside the app
    }

    /// Software NR button cycle: Off → RNNoise+ANR → Off.
    /// ANR and EMNR remain selectable from the backend picker but are not in the button cycle.
    enum SoftwareNRState: String, CaseIterable {
        case off     = "Off"
        case cascade = "RNNoise+ANR"
        case anr     = "ANR"
        case emnr    = "EMNR"

        var next: SoftwareNRState {
            switch self {
            case .off:     return .cascade
            case .cascade: return .off
            case .anr:     return .off
            case .emnr:    return .off
            }
        }
    }

    /// Controls whether the per-slot filter popover shows Hi/Lo-cut sliders or an IF-Shift slider.
    enum FilterSlotDisplayMode: String {
        case hiLoCut = "hilocut"
        case ifShift = "ifshift"
    }

    var connectionStatus: String = ConnectionStatus.disconnected.rawValue
    /// One-shot callback fired when a CK0 read-back response arrives. Cleared after use.
    /// Set before sending `CK0;` query; called on main thread from handleFrame.
    var pendingCKReadback: ((String) -> Void)?
    var vfoAFrequencyHz: Int?
    var vfoBFrequencyHz: Int?
    var operatingMode: KenwoodCAT.OperatingMode?
    var transceiverNRMode: KenwoodCAT.NoiseReductionMode?
    var isNotchEnabled: Bool?
    var rfGain: Int?
    var afGain: Int?
    var squelchLevel: Int?
    var sMeterDots: Int?
    var rxVFO: KenwoodCAT.VFO?
    var txVFO: KenwoodCAT.VFO?
    var ritEnabled: Bool?
    var xitEnabled: Bool?
    var ritXitOffsetHz: Int?
    var rxFilterShiftHz: Int?
    var rxFilterLowCutID: Int?
    var rxFilterHighCutID: Int?
    var txFilterLowCutID: Int?
    var txFilterHighCutID: Int?
    var outputPowerWatts: Int?
    var atuTxEnabled: Bool?
    var atuTuningActive: Bool?
    var splitOffsetSettingActive: Bool?
    var splitOffsetPlus: Bool?
    var splitOffsetKHz: Int?
    var isTransmitting: Bool?
    /// True while the radio is actually on-air (set from AI4 TX/RX frames — any source).
    var isPTTDown: Bool = false
    /// True only when this app initiated PTT. Kept separate from isPTTDown so that
    /// external keying (foot pedal, VOX, front panel) does not block app-initiated TX.
    var isAppPTTActive: Bool = false
    var isMemoryMode: Bool?
    var memoryChannelNumber: Int?
    var memoryChannelFrequencyHz: Int?
    var memoryChannelMode: KenwoodCAT.OperatingMode?
    var memoryChannelName: String?
    var scanActive: Bool = false
    var scanSpeed: Int?
    var toneScanMode: KenwoodCAT.ToneScanMode?
    var scanType: KenwoodCAT.ScanType?
    /// Last ham-band label seen on VFO A — used to detect band changes for auto-mode switching.
    private var _lastBandLabel: String? = nil

    // Antenna selection (AN)
    var antennaPort: Int?               // 1=ANT1, 2=ANT2
    var rxAntennaInUse: Bool?
    var driveOutEnabled: Bool?
    var antennaOutputEnabled: Bool?

    // APF Audio Peak Filter (AP0–AP3)
    var apfEnabled: Bool?
    var apfShift: Int?                  // 0–80, 40=center
    var apfBandwidth: KenwoodCAT.APFBandwidth?
    var apfGain: Int?                   // 0–6

    var isNoiseReductionEnabled: Bool = false
    var noiseReductionBackend: String = "Passthrough"
    var availableNoiseReductionBackends: [String] = []
    var selectedNoiseReductionBackend: String = "Passthrough"
    var noiseReductionStrength: Double = 1.0
    var noiseReductionProfileRaw: String = NoiseReductionProfile.speech.rawValue
    /// Which NR path the front-panel NR button controls (hardware vs software).
    var nrButtonMode: NRButtonMode = .hardware
    /// Current state of the software NR cycle (Off / ANR / EMNR).
    var softwareNRState: SoftwareNRState = .off
    var connectionLog: [String] = []
    var smokeTestStatus: String = "Not run"
    var useKnsLogin: Bool = true
    var adminId: String = ""
    var adminPassword: String = ""
    var knsAccountType: String = KenwoodKNS.AccountType.administrator.rawValue
    /// When enabled, plays "CQ" as Morse code tones through the Mac's speakers on connect
    /// and "73" on disconnect. Purely local audio — no RF transmission.
    var cwGreetingEnabled: Bool = false {
        didSet {
            guard oldValue != cwGreetingEnabled else { return }
            UserDefaults.standard.set(cwGreetingEnabled, forKey: "CWGreetingEnabled")
        }
    }

    // Audio monitor (USB audio in -> NR -> speakers out)
    var audioInputDevices: [AudioDeviceInfo] = []
    var audioOutputDevices: [AudioDeviceInfo] = []
    var selectedAudioInputUID: String = "" {
        didSet {
            guard oldValue != selectedAudioInputUID else { return }
            UserDefaults.standard.set(selectedAudioInputUID, forKey: audioInputUIDKey)
        }
    }
    var selectedAudioOutputUID: String = ""
    var isAudioMonitorRunning: Bool = false
    var audioMonitorError: String?
    var audioMonitorLog: [String] = []
    var audioMonitorWetDry: Double = 1.0
    var audioMonitorInputGain: Double = 1.0
    var audioMonitorOutputGain: Double = 1.0

    // MARK: - TX Audio (USB mic passthrough → USB Codec)
    enum TXAudioSource: String {
        case hardware        // Front panel mic, no app involvement (MS001)
        case usbPassthrough  // Mac USB mic → TS-890S USB Codec (MS002)
    }
    var txAudioSource: TXAudioSource = .hardware
    var selectedTXMicInputUID: String = "" {
        didSet {
            guard oldValue != selectedTXMicInputUID else { return }
            UserDefaults.standard.set(selectedTXMicInputUID, forKey: txMicInputUIDKey)
        }
    }
    var selectedTXCodecOutputUID: String = "" {
        didSet {
            guard oldValue != selectedTXCodecOutputUID else { return }
            UserDefaults.standard.set(selectedTXCodecOutputUID, forKey: txCodecOutputUIDKey)
        }
    }
    var isTXPassthroughRunning: Bool = false
    var txPassthroughError: String?
    var txPassthroughInputGain: Double = 1.0

    // LAN audio (UDP 60001) experimental RX path
    var isLanAudioRunning: Bool = false
    var lanAudioError: String?
    var lanAudioWetDry: Double = 1.0
    var lanAudioOutputGain: Double = 1.0
    var isAudioMuted: Bool = false
    var selectedLanAudioOutputUID: String = "" {
        didSet {
            guard oldValue != selectedLanAudioOutputUID else { return }
            UserDefaults.standard.set(selectedLanAudioOutputUID, forKey: lanAudioOutputUIDKey)
            switchLanAudioOutputIfRunning()
        }
    }
    var lanAudioPacketCount: Int = 0
    var lanAudioLastPacketAt: Date?
    var autoStartLanAudio: Bool = true {
        didSet { UserDefaults.standard.set(autoStartLanAudio, forKey: autoStartLanAudioKey) }
    }
    var voipOutputLevel: Int?
    var voipInputLevel: Int?

    // MARK: KNS admin settings (populated by queryKNSAdminSettings)
    var knsMode: Int = 0                 // ##KN0: 0=off 1=LAN 2=internet
    var knsVoipEnabled: Bool = false     // ##KN2
    var knsJitterBuffer: Int = 10        // ##KN4 raw P1 (04/10/25/40)
    var knsSpeakerMute: Bool = false     // ##KN5
    var knsAccessLog: Bool = false       // ##KN6
    var knsUserRemoteOps: Bool = false   // ##KN7
    var knsUserCount: Int = 0            // ##KN8
    var knsWelcomeMessage: String = ""   // ##KNC
    var knsSessionTimeout: Int = 13      // ##KND raw (13 = Unlimited)
    var knsUsers: [KNSUser] = []         // populated by loadAllKNSUsers()
    var knsAdminChangeResult: String = ""   // ##KN1 result
    var knsPasswordChangeResult: String = "" // ##KNE result
    private var _knsLoadUsersAfterCount = false
    var selectedLanMicInputUID: String = "" {
        didSet {
            guard oldValue != selectedLanMicInputUID else { return }
            UserDefaults.standard.set(selectedLanMicInputUID, forKey: lanMicInputUIDKey)
        }
    }
    var dataModeEnabled: Bool?
    var mdMode: Int?

    // MARK: - Built-in Radio EQ (UT/UR — 18-band graphic EQ)
    var txEQBands: [Int] = Array(repeating: 0, count: 18)
    var rxEQBands: [Int] = Array(repeating: 0, count: 18)
    var txEQPreset: KenwoodCAT.EQPreset? = nil
    var rxEQPreset: KenwoodCAT.EQPreset? = nil

    // General EX menu value store for the Menu Access view (menu# → last-seen value)
    var exMenuValues: [Int: Int] = [:]

    // MARK: - EX menu discovery scan
    var menuDiscoveryRunning: Bool = false
    var menuDiscoveryProgress: Double = 0      // 0.0–1.0 while scanning; 1.0 when done
    var menuDiscoverySnapshot: [(number: Int, value: Int)] = []
    var menuDiscoveryResponseCount: Int = 0    // live count of EX responses received
    var menuDiscoverySentCount: Int = 0        // live count of queries actually transmitted
    var menuDiscoveryTotalCount: Int = 0       // total queries planned for this scan

    // MARK: - New DSP / TX / CW controls (ARCP-890 parity)
    var agcMode: KenwoodCAT.AGCMode?
    var attenuatorLevel: KenwoodCAT.AttenuatorLevel?
    var preampLevel: KenwoodCAT.PreampLevel?
    var filterSlot: KenwoodCAT.FilterSlot?
    /// Per-slot display mode (Hi/Lo-cut vs IF-Shift). Persisted to UserDefaults.
    var filterSlotDisplayModes: [FilterSlotDisplayMode] = [.hiLoCut, .hiLoCut, .hiLoCut] {
        didSet {
            guard oldValue != filterSlotDisplayModes else { return }
            UserDefaults.standard.set(filterSlotDisplayModes.map { $0.rawValue },
                                      forKey: "filterSlotDisplayModes")
        }
    }
    /// Per-slot IF Shift in Hz. Saved/restored when the user switches filter slots.
    var filterSlotIFShiftHz: [Int] = [0, 0, 0] {
        didSet {
            guard oldValue != filterSlotIFShiftHz else { return }
            UserDefaults.standard.set(filterSlotIFShiftHz, forKey: "filterSlotIFShiftHz")
        }
    }
    var noiseBlankerEnabled: Bool?
    var beatCancelMode: KenwoodCAT.BeatCancelMode?
    var micGain: Int?           // 0-100
    var voxEnabled: Bool?
    var monitorLevel: Int?      // 0=off, 1-100
    var speechProcEnabled: Bool?
    var cwKeySpeedWPM: Int?     // 4-100
    var cwBreakInMode: KenwoodCAT.CWBreakInMode?

    // MARK: - Batch 1 new properties

    // Lock / Mute / Power
    var isLocked: Bool?
    var isMuted: Bool?
    var isSpeakerMuted: Bool?
    var isPoweredOn: Bool?
    var firmwareVersion: String?

    // Monitors
    var txMonitorEnabled: Bool?
    var rxMonitorEnabled: Bool?
    var dspMonitorEnabled: Bool?

    // CW extended
    var cwAutotuneActive: Bool?
    var cwPitchHz: Int?          // 300–1100 Hz
    var cwBreakInDelayMs: Int?   // 0–1000 ms

    // NB2 suite
    var noiseBlanker2Enabled: Bool?
    var noiseBlanker1Level: Int?
    var noiseBlanker2Level: Int?
    var noiseBlanker2Type: KenwoodCAT.NoiseBlanker2Type?
    var noiseBlanker2Depth: Int?
    var noiseBlanker2Width: Int?

    // Notch extended
    var notchFrequency: Int?         // 0–255 raw
    var notchBandwidth: KenwoodCAT.NotchBandwidth?

    // NR level tuning
    var nrLevel: Int?                // 1–10
    var nr2TimeConstant: Int?        // 0–9

    // DATA VOX
    var dataVOXMode: KenwoodCAT.DataVOXMode?

    // TX Modulation Sources (MS)
    // P1=0: config when TX keyed by PTT/SEND; P1=1: config when keyed by DATA SEND (PF)
    // P2: front source 0=Off 1=Mic;  P3: rear source 0=Off 1=ACC2 2=USB 3=LAN
    var msPttFront: Int?    // MS P1=0, P2
    var msPttRear: Int?     // MS P1=0, P3
    var msDataFront: Int?   // MS P1=1, P2
    var msDataRear: Int?    // MS P1=1, P3

    // VOX per-input parameters (index: 0=Mic, 1=ACC2, 2=USB, 3=LAN)
    var voxDelay: [Int?]     = [nil, nil, nil, nil]
    var voxGain: [Int?]      = [nil, nil, nil, nil]
    var antiVOXLevel: [Int?] = [nil, nil, nil, nil]

    /// Raw SM readings keyed by smIndex (0=S-meter,1=COMP,2=ALC,3=SWR,5=power).
    /// Stored in MeterStore so updates do NOT fire RadioState.objectWillChange,
    /// preventing meter polling from triggering full-tree SwiftUI re-renders.
    var meterReadings: [Int: Double] {
        get { MeterStore.shared.readings }
        set { MeterStore.shared.readings = newValue }
    }

    // MARK: - Memory browser (all 120 channels)
    var memoryChannels: [MemoryChannel] = []
    var isLoadingAllMemories: Bool = false

    // MARK: - Connection type (LAN / USB)
    var connectionType: ConnectionType = .lan
    var availableSerialPorts: [SerialPort] = []
    var selectedSerialPort: String = ""

    // MARK: - Bandscope / Waterfall
    /// Current span in kHz from BS4 (5/10/25/50/100/200/500). Default 50.
    var scopeSpanKHz: Int = 50

    // MARK: - Digital mode configuration state
    var isConfiguredForDigitalMode: Bool = false

    // MARK: - FreeDV state
    enum FreeDVAudioPath: String, CaseIterable { case lan = "LAN (KNS)", usb = "USB Audio" }
    var freedvIsActive:        Bool   = false
    var freedvMode:            FreeDVEngine.Mode = .mode700D
    var freedvAudioPath:       FreeDVAudioPath = .lan
    var freedvSync:            Bool   = false
    var freedvSnrDB:           Float  = 0
    var freedvBer:             Float  = 0
    var freedvTotalBits:       Int    = 0
    var freedvTotalBitErrors:  Int    = 0
    var freedvRxStatus:        Int32  = 0
    var freedvReceivedText:    String = ""
    var freedvTxCallsign:      String = UserDefaults.standard.string(forKey: "freedv_callsign") ?? "AI5OS"
    var freedvError:           String?

    var radioModel: KenwoodRadioModel = .ts890s
    var capabilities: KenwoodCapabilities = KenwoodCapabilities.capabilities(for: .ts890s)

    private var connection: any CATTransport = TS890Connection()
    private var previousOperatingModeForDigital: KenwoodCAT.OperatingMode? = nil
    private let morsePlayer = MorseAudioPlayer()
    /// Proxy wrapping the active backend. Passed to LanAudioPipeline and AudioMonitor
    /// so backend switches (and enable/disable) immediately affect all running pipelines.
    private let processorProxy = NoiseReductionProcessorProxy(inner: PassthroughNoiseReduction())
    private var noiseProcessor: any NoiseReductionProcessor {
        get { processorProxy.inner }
        set {
            processorProxy.inner = newValue
            isNoiseReductionAvailable = newValue.isAvailable
        }
    }
    private var audioMonitor: AudioMonitor?
    private var txPassthrough: AudioPassthrough?
    private var lanReceiver: KenwoodLanAudioReceiver?
    private var lanPipeline: LanAudioPipeline?
    private var lanPlayer: AudioOutputPlayer?
    private var micCapture: KenwoodLanMicCapture?
    private let micSendQueue = DispatchQueue(label: "KenwoodLanMicSend.queue")
    private var micFrameLogCountdown: Int = 0
    private var micTxFrames: [[Int16]] = []
    private var micTxTimer: DispatchSourceTimer?
    private enum MicTxSource { case mic, generated }
    private var micTxSource: MicTxSource = .mic
    private struct GeneratedTxState {
        var framesRemaining: Int
        var phase: Double
        var frequencyHz: Double
        var amplitude: Double
    }
    private var generatedTxState: GeneratedTxState?
    // Pre-computed PCM16 buffer for digital modes (FT8/FT4); played by the `.generated` timer branch.
    private var generatedTxBuffer: [Int16] = []
    private var generatedTxBufferPos: Int = 0

    // FreeDV
    private let freedvEngine = FreeDVEngine()
    private var freedvLanRxPipeline: FreeDVLanRxPipeline?
    private var freedvLanTxPipeline: FreeDVLanTxPipeline?
    private var freedvUsbPipeline: FreeDVUsbPipeline?
    private var previousModeBeforeFreeDV: KenwoodCAT.OperatingMode?
    private var previousTxAudioSourceBeforeFreeDV: TXAudioSource?

    private var currentHost: String = ""
    private var currentSerialPort: String = ""
    private let lanRxTapQueue = DispatchQueue(label: "KenwoodLanAudio.tap")

    // Optional tap for consumers (FT8, recording, etc). Called off the main thread.
    // Frame format: 48 kHz mono float samples.
    var onLanRxAudio48kMono: (([Float]) -> Void)?
    // Keep high-rate packet counts off the main thread; publish a throttled view for UI/VoiceOver.
    private var lanAudioPacketCountRaw: Int = 0
    private var lanAudioLastPacketAtRaw: Date?
    // Throttle noisy CAT frames so VoiceOver doesn't lose focus due to constant UI updates.
    private var lastRXFrameSMAt: Date = .distantPast
    private let nrStrengthKey        = "nr_strength"
    private let nrProfileKey         = "nr_profile"
    private let nrBackendKey         = "nr_backend"
    private let lanAudioOutputUIDKey = "lan_audio_output_uid"
    private let lanMicInputUIDKey    = "lan_mic_input_uid"
    private let audioInputUIDKey     = "audio_input_uid"
    private let txAudioSourceKey     = "tx_audio_source"
    private let autoStartLanAudioKey = "auto_start_lan_audio"
    private let txMicInputUIDKey     = "tx_mic_input_uid"
    private let txCodecOutputUIDKey  = "tx_codec_output_uid"
    // Cache the most recently loaded/saved credentials so we don't touch Keychain on every connect.
    // Keyed by "\(accountTypeRaw)|\(host)".
    private var knsCredentialCache: [String: (username: String, password: String)] = [:]
    private var debouncedCAT: [String: DispatchWorkItem] = [:]
    private var _bandFreqSaveWork: DispatchWorkItem?

    init() {
        // Build the list of available NR backends.
        var available: [String] = []
        if RNNoiseProcessor() != nil && WDSPNoiseReductionProcessor(mode: .anr) != nil { available.append("RNNoise + ANR") }
        if RNNoiseProcessor() != nil { available.append("RNNoise (in-process)") }
        if WDSPNoiseReductionProcessor(mode: .anr)  != nil { available.append("WDSP ANR") }
        if WDSPNoiseReductionProcessor(mode: .emnr) != nil { available.append("WDSP EMNR") }
        available.append("Passthrough (disabled)")
        self.availableNoiseReductionBackends = available

        // Pick the best available backend and wire it into the proxy.
        // Auto-selection order: RNNoise+ANR → RNNoise → WDSP ANR → WDSP EMNR → Passthrough.
        if let rnnoise = RNNoiseProcessor(), let anr = WDSPNoiseReductionProcessor(mode: .anr) {
            noiseProcessor = CascadeNoiseReductionProcessor(primary: rnnoise, secondary: anr)
            isNoiseReductionEnabled = false
            noiseReductionBackend = "RNNoise + ANR"
            selectedNoiseReductionBackend = "RNNoise + ANR"
        } else if let rnnoise = RNNoiseProcessor() {
            noiseProcessor = rnnoise
            isNoiseReductionEnabled = false
            noiseReductionBackend = rnnoise.backendDescription
            selectedNoiseReductionBackend = "RNNoise (in-process)"
        } else if let anr = WDSPNoiseReductionProcessor(mode: .anr) {
            anr.isEnabled = false
            noiseProcessor = anr
            isNoiseReductionEnabled = false
            noiseReductionBackend = "WDSP ANR"
            selectedNoiseReductionBackend = "WDSP ANR"
        } else if let emnr = WDSPNoiseReductionProcessor(mode: .emnr) {
            noiseProcessor = emnr
            isNoiseReductionEnabled = false
            noiseReductionBackend = "WDSP EMNR"
            selectedNoiseReductionBackend = "WDSP EMNR"
        } else {
            noiseProcessor = PassthroughNoiseReduction()
            isNoiseReductionEnabled = false
            noiseReductionBackend = "Passthrough (disabled)"
            selectedNoiseReductionBackend = "Passthrough (disabled)"
        }
        AppFileLogger.shared.log("Noise reduction backend: \(noiseReductionBackend)")

        loadPersistedKnsSettings()
        loadPersistedNoiseReductionSettings()
        loadPersistedFilterSlotSettings()
        // Apply initial strength to both paths (LAN + monitor).
        setNoiseReductionStrength(noiseReductionStrength, persist: false)
        // Apply profile after strength so preset can override if user chose it.
        applyNoiseReductionProfile(persist: false)

        refreshAudioDevices()
        // Restore saved audio input, or fall back to system default.
        if let saved = UserDefaults.standard.string(forKey: audioInputUIDKey), !saved.isEmpty,
           audioInputDevices.contains(where: { $0.uid == saved }) {
            selectedAudioInputUID = saved
        } else if selectedAudioInputUID.isEmpty {
            if let defaultID = AudioDeviceManager.defaultInputDeviceID(),
               let match = audioInputDevices.first(where: { $0.id == defaultID }) {
                selectedAudioInputUID = match.uid
            } else if let first = audioInputDevices.first {
                selectedAudioInputUID = first.uid
            }
        }
        if selectedAudioOutputUID.isEmpty {
            if let defaultID = AudioDeviceManager.defaultOutputDeviceID(),
               let match = audioOutputDevices.first(where: { $0.id == defaultID }) {
                selectedAudioOutputUID = match.uid
            } else if let first = audioOutputDevices.first {
                selectedAudioOutputUID = first.uid
            }
        }
        // Restore saved LAN audio output device, or default to system output (empty string).
        if let saved = UserDefaults.standard.string(forKey: lanAudioOutputUIDKey), !saved.isEmpty,
           audioOutputDevices.contains(where: { $0.uid == saved }) {
            selectedLanAudioOutputUID = saved
        }
        // Restore saved LAN mic input, or default to system input (empty string).
        if let saved = UserDefaults.standard.string(forKey: lanMicInputUIDKey), !saved.isEmpty,
           audioInputDevices.contains(where: { $0.uid == saved }) {
            selectedLanMicInputUID = saved
        }

        // Restore TX audio source and device selections.
        if let rawSource = UserDefaults.standard.string(forKey: txAudioSourceKey),
           let saved = TXAudioSource(rawValue: rawSource) {
            txAudioSource = saved
        }
        // Restore LAN audio auto-start preference (default true if never saved).
        if UserDefaults.standard.object(forKey: autoStartLanAudioKey) != nil {
            autoStartLanAudio = UserDefaults.standard.bool(forKey: autoStartLanAudioKey)
        }
        if let saved = UserDefaults.standard.string(forKey: txMicInputUIDKey), !saved.isEmpty,
           audioInputDevices.contains(where: { $0.uid == saved }) {
            selectedTXMicInputUID = saved
        }
        if let saved = UserDefaults.standard.string(forKey: txCodecOutputUIDKey), !saved.isEmpty,
           audioOutputDevices.contains(where: { $0.uid == saved }) {
            selectedTXCodecOutputUID = saved
        }

        // Restore saved FreeDV mode and audio path.
        if let rawMode = UserDefaults.standard.object(forKey: "freedv_mode") as? Int,
           let savedMode = FreeDVEngine.Mode(rawValue: Int32(rawMode)) {
            freedvMode = savedMode
        }
        if let rawPath = UserDefaults.standard.string(forKey: "freedv_audio_path"),
           let savedPath = FreeDVAudioPath(rawValue: rawPath) {
            freedvAudioPath = savedPath
        }

        wireCallbacks()
    }

    nonisolated deinit {}

    // MARK: - Frame-drain state
    // Batches incoming CAT frames so we dispatch to main at most once per RunLoop
    // tick instead of once per frame. Prevents keyboard events from queuing behind
    // a flood of individual DispatchQueue.main.async calls (AI4 + scope streaming).
    private var _pendingFrames: [String] = []
    private let _pendingLock = NSLock()
    private var _drainScheduled = false
    private var _discoverySource: DispatchSourceTimer?

    // Scope coalescing — only the latest ##DD2 frame per RunLoop tick reaches main.
    private var _latestScopePoints: [UInt8]? = nil
    private var _scopeDrainScheduled = false
    private let _scopeLock = NSLock()

    // MARK: - Transport wiring

    private func wireCallbacks() {
        connection.onStatusChange = { [weak self] status in
            AppLogger.info("Status: \(status.rawValue)")
            AppFileLogger.shared.log("Status: \(status.rawValue)")
            DispatchQueue.main.async {
                let mapped: ConnectionStatus
                switch status {
                case .connected: mapped = .connected
                case .connecting: mapped = .connecting
                case .authenticating: mapped = .authenticating
                case .disconnected: mapped = .disconnected
                }
                self?.connectionStatus = mapped.rawValue.capitalized
                self?.announceConnectionStatus(mapped)

                guard let self else { return }
                if mapped == .connected {
                    if self.connectionType == .lan {
                        // If the user configured the radio for USB digital mode and is now
                        // connecting via LAN, automatically restore the previous operating mode
                        // and switch TX audio to LAN VoIP so voice/digital ops work immediately.
                        if self.isConfiguredForDigitalMode {
                            let revertMode = self.previousOperatingModeForDigital ?? .usb
                            self.send(KenwoodCAT.setOperatingMode(revertMode))
                            self.send("MS003;") // SEND/PTT, Front=OFF, Rear=LAN
                            self.isConfiguredForDigitalMode = false
                            self.previousOperatingModeForDigital = nil
                            AppFileLogger.shared.log("CAT: LAN connect — cleared digital mode config, restored \(revertMode.label), TX audio=LAN")
                            self.postRadioNotification(
                                title: "Radio Updated for LAN Connection",
                                body: "Digital mode cleared. Restored to \(revertMode.label) with LAN VoIP audio for TX."
                            )
                        }

                        if self.capabilities.hasLANAudio, self.autoStartLanAudio, !self.currentHost.isEmpty {
                            if self.isLanAudioRunning {
                                AppFileLogger.shared.log("LAN: reconnect — reusing existing receiver, sending ##VP1")
                                self.connection.send("##VP1;")
                            } else {
                                self.startLanAudio(host: self.currentHost)
                            }
                            self.send(KenwoodCAT.getVoipInputLevel())
                            self.send(KenwoodCAT.getVoipOutputLevel())
                        }
                    }
                    // Enable Auto-Information mode: radio pushes FA/FB/OM/RIT/XIT/etc.
                    // changes unsolicited, eliminating the need to poll those values.
                    // AI4 = auto-info ON with backup (survives KNS reconnects).
                    self.send("AI4;")
                    // Prime basic audio/rf controls and common operating params.
                    self.send(KenwoodCAT.getAFGain())
                    self.send(KenwoodCAT.getRFGain())
                    self.queryTop5()
                    // Enable bandscope streaming to LAN (high cycle) and read span
                    if self.connectionType == .lan && self.capabilities.hasScope {
                        self.send("DD01;")   // Output to LAN, High cycle
                        self.send("BS4;")    // Read current span setting
                    }
                    if self.cwGreetingEnabled {
                        AppFileLogger.shared.log("Morse: playing connect greeting (CQ)")
                        self.morsePlayer.play("CQ")
                    }
                }
                if mapped == .disconnected {
                    if self.connectionType == .lan { self.stopMicCapture() }
                    self.deactivateFreeDV()
                    // Keep the UDP receiver alive so port 60001 stays bound.
                    self.isPTTDown = false
                    self.isAppPTTActive = false
                }
            }
        }
        connection.onError = { [weak self] err in
            AppLogger.error(err)
            AppFileLogger.shared.log("Error: \(err)")
            DispatchQueue.main.async {
                DiagnosticsStore.shared.lastError = err
                DiagnosticsStore.shared.errorLog.append(err)
                self?.connectionLog.append("Error: \(err)")
                self?.announceError(err)
            }
        }
        connection.onFrame = { [weak self] frame in
            guard let self else { return }
            // Drain pattern: enqueue on background, dispatch to main only on first item.
            // All frames queued before the drain runs are handled in a single RunLoop tick,
            // so keyboard events are never blocked by a flood of individual async calls.
            self._pendingLock.lock()
            self._pendingFrames.append(frame)
            let needsDrain = !self._drainScheduled
            if needsDrain { self._drainScheduled = true }
            self._pendingLock.unlock()
            if needsDrain {
                DispatchQueue.main.async { [weak self] in self?._drainFrames() }
            }
        }
        // Wire scope data — LAN only; no-op for serial transport.
        // Coalescing: if multiple ##DD2 frames arrive before main drains, only the
        // latest is applied — avoids saturating the main RunLoop with scope data.
        if let lan = connection as? TS890Connection {
            lan.onScopeData = { [weak self] points in
                guard let self else { return }
                self._scopeLock.lock()
                self._latestScopePoints = points
                let needsDrain = !self._scopeDrainScheduled
                if needsDrain { self._scopeDrainScheduled = true }
                self._scopeLock.unlock()
                if needsDrain {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self._scopeLock.lock()
                        let pts = self._latestScopePoints
                        self._latestScopePoints = nil
                        self._scopeDrainScheduled = false
                        self._scopeLock.unlock()
                        if let pts { ScopeStore.shared.points = pts }
                    }
                }
            }
        }
        connection.onLog = { [weak self] message in
            // High-frequency push frames (FA/FB during tuning, SM, ##DD2 scope) are
            // already written to AppFileLogger. Skip them from the @Published connectionLog
            // — every append fires objectWillChange and re-renders ContentView's log panel.
            let isHighFreq = message.hasPrefix("RX: SM")
                          || message.hasPrefix("RX: FA")
                          || message.hasPrefix("RX: FB")
                          || message.hasPrefix("RX: ##DD")
            AppFileLogger.shared.log(message)
            guard !isHighFreq else { return }
            AppLogger.info(message)
            DispatchQueue.main.async {
                guard let self else { return }
                self.connectionLog.append(message)
                if self.connectionLog.count > 50 {
                    self.connectionLog.removeFirst(self.connectionLog.count - 50)
                }
            }
        }
    }

    // MARK: - Frame drain (called on main thread)

    private func _drainFrames() {
        _pendingLock.lock()
        let frames = _pendingFrames
        _pendingFrames.removeAll(keepingCapacity: true)
        _drainScheduled = false
        _pendingLock.unlock()
        // Deduplicate before processing: during AI4 operation and VFO tuning, dozens of
        // FA/FB frames can pile up between drain cycles. Only the latest value matters;
        // skipping stale duplicates cuts main-thread parse work and reduces SwiftUI
        // re-render pressure across all open windows.
        let deduped = Self._deduplicateFrames(frames)
        for frame in deduped {
            handleFrame(frame)
            if shouldPublishLastRXFrame(frame) {
                DiagnosticsStore.shared.lastRXFrame = frame
            }
        }
    }

    /// Returns `frames` with duplicate high-frequency frames removed, keeping only
    /// the last occurrence of each key. Frame order is preserved for all other types.
    private static func _deduplicateFrames(_ frames: [String]) -> [String] {
        // First pass: find the last index of each dedup key.
        var lastIndex: [String: Int] = [:]
        for (i, frame) in frames.enumerated() {
            if let key = _dedupKey(frame) { lastIndex[key] = i }
        }
        guard !lastIndex.isEmpty else { return frames }
        // Second pass: emit each frame unless a newer one with the same key exists.
        var result: [String] = []
        result.reserveCapacity(frames.count)
        for (i, frame) in frames.enumerated() {
            if let key = _dedupKey(frame) {
                if lastIndex[key] == i { result.append(frame) }
            } else {
                result.append(frame)
            }
        }
        return result
    }

    /// Returns a dedup key for high-frequency frame types, nil for everything else.
    /// FA/FB: VFO frequency pushed by AI4 on every encoder tick.
    /// SM:    meter reading polled at ~4 Hz — single command, no type index.
    private static func _dedupKey(_ frame: String) -> String? {
        if frame.hasPrefix("FA") { return "FA" }
        if frame.hasPrefix("FB") { return "FB" }
        if frame.hasPrefix("SM") { return "SM" }
        return nil
    }

    // MARK: - Serial port discovery

    func scanSerialPorts() {
        availableSerialPorts = SerialPortScanner.availablePorts()
        if selectedSerialPort.isEmpty || !availableSerialPorts.contains(where: { $0.path == selectedSerialPort }) {
            selectedSerialPort = availableSerialPorts.first(where: { $0.isLikelyRadio })?.path
                              ?? availableSerialPorts.first?.path
                              ?? ""
        }
    }

    func setAudioMuted(_ muted: Bool) {
        isAudioMuted = muted
        applyAudioMuteState()
        AppFileLogger.shared.log("Audio: muted=\(muted)")
    }

    func toggleAudioMute() {
        setAudioMuted(!isAudioMuted)
    }

    private func applyAudioMuteState() {
        let factor: Float = isAudioMuted ? 0.0 : 1.0
        lanPlayer?.gain = Float(lanAudioOutputGain) * factor
        audioMonitor?.outputGain = Float(audioMonitorOutputGain) * factor
    }

    func clearConnectionLog() {
        connectionLog.removeAll()
    }

    func connect(host: String, port: Int) {
        let p = UInt16(clamping: port)
        let type = KenwoodKNS.AccountType(rawValue: knsAccountType) ?? .administrator
        persistKnsSettings(host: host, port: port, accountType: type)
        connectionType = .lan
        currentHost = host
        DiagnosticsStore.shared.lastError = nil
        let lan = TS890Connection()
        connection = lan
        wireCallbacks()
        lan.connect(host: host, port: p, useKnsLogin: useKnsLogin, accountType: type, adminId: adminId, adminPassword: adminPassword)
        connectionStatus = ConnectionStatus.connecting.rawValue
    }

    func connectUSB(portPath: String) {
        connectionType = .usb
        currentSerialPort = portPath
        DiagnosticsStore.shared.lastError = nil
        let serial = SerialCATConnection()
        connection = serial
        wireCallbacks()
        serial.connect(portPath: portPath)
        connectionStatus = ConnectionStatus.connecting.rawValue
    }

    func disconnect() {
        if cwGreetingEnabled {
            AppFileLogger.shared.log("Morse: playing disconnect farewell (73)")
            morsePlayer.play("73")
        }
        if connectionType == .lan { stopLanAudio() }
        _scopeLock.lock(); _latestScopePoints = nil; _scopeDrainScheduled = false; _scopeLock.unlock()
        connection.disconnect()
    }

    /// Reconnect using the last transport and settings (keyboard shortcut use).
    /// No-ops if already connected.
    func reconnect() {
        guard connectionStatus != ConnectionStatus.connected.rawValue else { return }
        if connectionType == .usb, !currentSerialPort.isEmpty {
            connectUSB(portPath: currentSerialPort)
            return
        }
        guard let host = KNSSettings.loadLastHost(), !host.isEmpty else { return }
        let port = KNSSettings.loadLastPort() ?? 60000
        loadSavedCredentials(host: host)
        connect(host: host, port: port)
    }

    /// Cycle through available NR backends in order.
    /// Passthrough is excluded from the cycle — use the NR popover to disable entirely.
    func cycleNoiseReductionBackend() {
        let cycleable = availableNoiseReductionBackends.filter { $0 != "Passthrough (disabled)" }
        guard !cycleable.isEmpty else { return }
        let idx = cycleable.firstIndex(of: selectedNoiseReductionBackend) ?? -1
        let next = cycleable[(idx + 1) % cycleable.count]
        setNoiseReductionBackend(next)
        announceInfo("NR: \(next)")
    }

    func send(_ command: String) {
        // Don't surface admin credentials in the UI.
        let display = command.hasPrefix("##ID") ? "##ID<redacted>;" : command
        DiagnosticsStore.shared.lastTXFrame = display
        DiagnosticsStore.shared.txLog.append(display)
        connection.send(command)
    }

    /// Replaces the active transport. For unit testing only — does not reconnect or re-wire callbacks.
    func _setConnectionForTesting(_ transport: any CATTransport) {
        connection = transport
    }

    func setNoiseReduction(enabled: Bool) {
        guard isNoiseReductionEnabled != enabled else { return }
        isNoiseReductionEnabled = enabled
        noiseProcessor.isEnabled = enabled
        AppFileLogger.shared.log("NR: enabled=\(enabled) backend=\(noiseReductionBackend) lanWetDry=\(String(format: "%.2f", lanAudioWetDry)) monitorWetDry=\(String(format: "%.2f", audioMonitorWetDry))")
        announceNoiseReductionChange(enabled: enabled)
    }

    func setNoiseReductionBackend(_ backendName: String) {
        let previousBackend = selectedNoiseReductionBackend
        selectedNoiseReductionBackend = backendName
        persistNoiseReductionSettings()
        // Preserve the user's current on/off state across backend switches.
        // New processors always start with isEnabled=false; we restore the
        // previous state so NR doesn't silently turn off when switching modes.
        let wasEnabled = isNoiseReductionEnabled
        switch backendName {
        case "RNNoise + ANR":
            if let rnnoise = RNNoiseProcessor(), let anr = WDSPNoiseReductionProcessor(mode: .anr) {
                let cascade = CascadeNoiseReductionProcessor(primary: rnnoise, secondary: anr)
                cascade.isEnabled = wasEnabled
                noiseProcessor = cascade
                noiseReductionBackend = "RNNoise + ANR"
                AppFileLogger.shared.log("NR backend switched to: RNNoise + ANR (enabled=\(wasEnabled))")
            } else {
                selectedNoiseReductionBackend = previousBackend
                AppFileLogger.shared.log("NR backend switch to RNNoise + ANR failed (init returned nil) — keeping \(previousBackend)")
            }
        case "WDSP EMNR":
            if let emnr = WDSPNoiseReductionProcessor(mode: .emnr) {
                emnr.isEnabled = wasEnabled
                noiseProcessor = emnr
                noiseReductionBackend = "WDSP EMNR"
                AppFileLogger.shared.log("NR backend switched to: WDSP EMNR (enabled=\(wasEnabled))")
            } else {
                selectedNoiseReductionBackend = previousBackend
                AppFileLogger.shared.log("NR backend switch to WDSP EMNR failed (init returned nil) — keeping \(previousBackend)")
            }
        case "WDSP ANR":
            if let anr = WDSPNoiseReductionProcessor(mode: .anr) {
                anr.isEnabled = wasEnabled
                noiseProcessor = anr
                noiseReductionBackend = "WDSP ANR"
                AppFileLogger.shared.log("NR backend switched to: WDSP ANR (enabled=\(wasEnabled))")
            } else {
                selectedNoiseReductionBackend = previousBackend
                AppFileLogger.shared.log("NR backend switch to WDSP ANR failed (init returned nil) — keeping \(previousBackend)")
            }
        case "RNNoise (in-process)":
            if let rnnoise = RNNoiseProcessor() {
                rnnoise.isEnabled = wasEnabled
                noiseProcessor = rnnoise
                isNoiseReductionEnabled = wasEnabled
                noiseReductionBackend = rnnoise.backendDescription
                AppFileLogger.shared.log("NR backend switched to: RNNoise (in-process) (enabled=\(wasEnabled))")
            } else {
                selectedNoiseReductionBackend = previousBackend
                AppFileLogger.shared.log("NR backend switch to RNNoise (in-process) failed (init returned nil) — keeping \(previousBackend)")
            }
        default: // "Passthrough (disabled)"
            noiseProcessor = PassthroughNoiseReduction()
            isNoiseReductionEnabled = false
            noiseReductionBackend = "Passthrough (disabled)"
            AppFileLogger.shared.log("NR backend switched to: Passthrough")
        }
    }

    private(set) var isNoiseReductionAvailable: Bool = false


    func setNoiseReductionStrength(_ value: Double) {
        setNoiseReductionStrength(value, persist: true)
    }

    func setNoiseReductionProfile(rawValue: String) {
        noiseReductionProfileRaw = rawValue
        applyNoiseReductionProfile(persist: true)
    }

    func refreshAudioDevices() {
        audioInputDevices = AudioDeviceManager.inputDevices()
        audioOutputDevices = AudioDeviceManager.outputDevices()
        if !selectedAudioInputUID.isEmpty, AudioDeviceManager.deviceID(forUID: selectedAudioInputUID) == nil {
            selectedAudioInputUID = ""
        }
        if !selectedAudioOutputUID.isEmpty, AudioDeviceManager.deviceID(forUID: selectedAudioOutputUID) == nil {
            selectedAudioOutputUID = ""
        }
        if !selectedLanAudioOutputUID.isEmpty, AudioDeviceManager.deviceID(forUID: selectedLanAudioOutputUID) == nil {
            selectedLanAudioOutputUID = ""
        }
        if !selectedLanMicInputUID.isEmpty, AudioDeviceManager.deviceID(forUID: selectedLanMicInputUID) == nil {
            selectedLanMicInputUID = ""
        }

        if selectedAudioOutputUID.isEmpty {
            if let defaultID = AudioDeviceManager.defaultOutputDeviceID(),
               let match = audioOutputDevices.first(where: { $0.id == defaultID }) {
                selectedAudioOutputUID = match.uid
            } else if let first = audioOutputDevices.first {
                selectedAudioOutputUID = first.uid
            }
        }
        // Allow empty UID to mean "system default output".

        // Emit a concise device list to the file log for debugging VoiceOver selection issues.
        if !audioOutputDevices.isEmpty {
            let names = audioOutputDevices.prefix(10).map { "\($0.name) uid=\($0.uid)" }.joined(separator: " | ")
            AppFileLogger.shared.log("Audio outputs (first 10): \(names)")
        }
    }

    // MARK: - Top-5 Operating Features

    func queryTop5() {
        // Identify the radio model so capability flags are set before we use them.
        send("ID;")
        // VFO A (also pushed by AI, but query on connect for instant population).
        send(KenwoodCAT.getVFOAFrequency())
        // VFO B + split (FR/FT), RIT/XIT, RX filter, power, ATU.
        send(KenwoodCAT.getVFOBFrequency())
        send(KenwoodCAT.getReceiverVFO())
        send(KenwoodCAT.getTransmitterVFO())
        send(KenwoodCAT.ritGetState())
        send(KenwoodCAT.xitGetState())
        send(KenwoodCAT.ritXitGetOffset())
        send(KenwoodCAT.getReceiveFilterShift())
        send(KenwoodCAT.getReceiveFilterLowCutSettingID())
        send(KenwoodCAT.getReceiveFilterHighCutSettingID())
        send(KenwoodCAT.getFilterSlot())
        send("TF1;")
        send("TF2;")
        send(KenwoodCAT.getOutputPower())
        send(KenwoodCAT.getAntennaTuner())
        send(KenwoodCAT.getSplitOffsetSettingState())
        // Memory mode/channel are useful for quick operation.
        send(KenwoodCAT.getMemoryMode())
        send(KenwoodCAT.getMemoryChannelNumber())
        // Mode, squelch, NR, notch — not pushed by AI mode.
        send(KenwoodCAT.getOperatingMode(.left))
        send(KenwoodCAT.getSquelchLevel())
        send(KenwoodCAT.getNoiseReduction())
        send(KenwoodCAT.getNotch())
        // ARCP-890 parity: AGC, ATT, PRE, NB, BC, Mic, VOX, Monitor, Speech proc, CW speed/break-in.
        send(KenwoodCAT.getAGC())
        send(KenwoodCAT.getAttenuator())
        send(KenwoodCAT.getPreamp())
        send(KenwoodCAT.getNoiseBlanker())
        send(KenwoodCAT.getBeatCancel())
        send(KenwoodCAT.getMicGain())
        send(KenwoodCAT.getVOX())
        send(KenwoodCAT.getMonitorLevel())
        send(KenwoodCAT.getSpeechProc())
        send(KenwoodCAT.getCWSpeed())
        send(KenwoodCAT.getCWBreakIn())
        // Batch 1: new state queries
        send(KenwoodCAT.getLock())
        send(KenwoodCAT.getMute())
        send(KenwoodCAT.getSpeakerMute())
        send(KenwoodCAT.getFirmwareVersion())
        send(KenwoodCAT.getTXMonitor())
        send(KenwoodCAT.getRXMonitor())
        send(KenwoodCAT.getDSPMonitor())
        send(KenwoodCAT.getCWAutotune())
        send(KenwoodCAT.getCWPitch())
        send(KenwoodCAT.getCWBreakInDelay())
        send(KenwoodCAT.getNoiseBlanker2())
        send(KenwoodCAT.getNoiseBlanker1Level())
        send(KenwoodCAT.getNoiseBlanker2Level())
        send(KenwoodCAT.getNoiseBlanker2Type())
        send(KenwoodCAT.getNoiseBlanker2Depth())
        send(KenwoodCAT.getNoiseBlanker2Width())
        send(KenwoodCAT.getNotchFrequency())
        send(KenwoodCAT.getNotchBandwidth())
        send(KenwoodCAT.getNRLevel())
        send(KenwoodCAT.getNR2TimeConstant())
        send(KenwoodCAT.getDataVOX())
        send(KenwoodCAT.getTxAudioSource(txMeans: 0))  // PTT keying config
        send(KenwoodCAT.getTxAudioSource(txMeans: 1))  // DATA SEND keying config
        send(KenwoodCAT.getVOXDelay(inputType: 0))
        send(KenwoodCAT.getVOXGain(inputType: 0))
        send(KenwoodCAT.getAntiVOXLevel(inputType: 0))
        // Antenna selection, scan state.
        send(KenwoodCAT.getAntenna())
        send(KenwoodCAT.getScanState())
        send(KenwoodCAT.getScanSpeed())
        send(KenwoodCAT.getToneScanMode())
        send(KenwoodCAT.getScanType())
        // PS not queried on connect — radio won't answer when already powered on
        // DA command not sent — no DA command exists in TS-890S PC Command Reference
    }

    func setVFOBFrequencyHz(_ hz: Int) {
        send(KenwoodCAT.setVFOBFrequencyHz(hz))
        // AI4 pushes FB confirmation automatically
    }

    func setSplitEnabled(_ enabled: Bool) {
        // Split means TX VFO differs from RX VFO.
        let rx = rxVFO ?? .a
        if enabled {
            let tx: KenwoodCAT.VFO = (rx == .a) ? .b : .a
            send(KenwoodCAT.setTransmitterVFO(tx))
        } else {
            send(KenwoodCAT.setTransmitterVFO(rx))
        }
        // AI4 pushes FT confirmation automatically
    }

    func setReceiverVFO(_ vfo: KenwoodCAT.VFO) {
        send(KenwoodCAT.setReceiverVFO(vfo))
        // AI4 pushes FR confirmation automatically
    }

    func setTransmitterVFO(_ vfo: KenwoodCAT.VFO) {
        send(KenwoodCAT.setTransmitterVFO(vfo))
        // AI4 pushes FT confirmation automatically
    }

    func setRITEnabled(_ enabled: Bool) {
        send(KenwoodCAT.ritSetEnabled(enabled))
        // AI4 pushes RT confirmation automatically
    }

    func setXITEnabled(_ enabled: Bool) {
        send(KenwoodCAT.xitSetEnabled(enabled))
        // AI4 pushes XT confirmation automatically
    }

    func clearRitXitOffset() {
        send(KenwoodCAT.ritXitClearOffset())
        // AI4 pushes RD confirmation automatically
    }

    func setRitXitOffsetHz(_ hz: Int) {
        send(KenwoodCAT.ritXitSetOffsetHz(hz))
        // AI4 pushes RD confirmation automatically
    }

    func stepRitXit(up: Bool) {
        send(up ? KenwoodCAT.ritXitStepUp() : KenwoodCAT.ritXitStepDown())
        // AI4 pushes RD confirmation automatically
    }

    func setReceiveFilterShiftHz(_ hz: Int) {
        send(KenwoodCAT.setReceiveFilterShiftHz(hz))
        send(KenwoodCAT.getReceiveFilterShift())
    }

    func setReceiveFilterLowCutID(_ id: Int) {
        send(KenwoodCAT.setReceiveFilterLowCutSettingID(id))
        send(KenwoodCAT.getReceiveFilterLowCutSettingID())
    }

    func setReceiveFilterHighCutID(_ id: Int) {
        send(KenwoodCAT.setReceiveFilterHighCutSettingID(id))
        send(KenwoodCAT.getReceiveFilterHighCutSettingID())
    }

    private func debounceCAT(key: String, delaySeconds: Double, _ block: @escaping () -> Void) {
        if let existing = debouncedCAT[key] {
            existing.cancel()
        }
        let work = DispatchWorkItem(block: block)
        debouncedCAT[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    func setOutputPowerWatts(_ watts: Int) {
        send(KenwoodCAT.setOutputPowerWatts(watts))
        // AI4 pushes PC confirmation automatically
    }

    func setOutputPowerWattsDebounced(_ watts: Int) {
        let clamped = max(5, min(watts, 100))
        outputPowerWatts = clamped
        debounceCAT(key: "tx_power", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setOutputPowerWatts(clamped))
            // AI4 pushes PC confirmation automatically
        }
    }

    func setATUTxEnabled(_ enabled: Bool) {
        send(KenwoodCAT.setAntennaTuner(txEnabled: enabled))
        // AI4 pushes AC confirmation automatically
    }

    func setMemoryMode(enabled: Bool) {
        isMemoryMode = enabled
        send(KenwoodCAT.setMemoryMode(enabled))
        send(KenwoodCAT.getMemoryMode())
        send(KenwoodCAT.getMemoryChannelNumber())
    }

    /// Start memory scan (SC01;). Radio advances through memory channels automatically.
    func startMemoryScan() {
        scanActive = true   // optimistic — corrected by SC0 response frame
        send(KenwoodCAT.setScanEnabled(true))
    }

    /// Stop any active scan (SC00;).
    func stopScan() {
        scanActive = false
        send(KenwoodCAT.setScanEnabled(false))
    }

    func setScanSpeed(_ speed: Int) {
        let clamped = max(1, min(speed, 9))
        scanSpeed = clamped
        send(KenwoodCAT.setScanSpeed(clamped))
    }

    func setToneScanMode(_ mode: KenwoodCAT.ToneScanMode) {
        toneScanMode = mode
        send(KenwoodCAT.setToneScanMode(mode))
    }

    func setScanType(_ type: KenwoodCAT.ScanType) {
        scanType = type
        send(KenwoodCAT.setScanType(type))
    }

    // Band table used for step up/down. Matches fpBandRanges in FrontPanelView.
    // UserDefaults keys share the "bandFreq_A_<label>" format used by FrontPanelView.switchBand().
    private static let _bandStepTable: [(label: String, defaultHz: Int, range: ClosedRange<Int>)] = [
        ("160m",  1_800_000,  1_800_000...2_000_000),
        ("80m",   3_500_000,  3_500_000...4_000_000),
        ("60m",   5_330_500,  5_330_000...5_410_000),
        ("40m",   7_000_000,  7_000_000...7_300_000),
        ("30m",  10_100_000, 10_100_000...10_150_000),
        ("20m",  14_000_000, 14_000_000...14_350_000),
        ("17m",  18_068_000, 18_068_000...18_168_000),
        ("15m",  21_000_000, 21_000_000...21_450_000),
        ("12m",  24_890_000, 24_890_000...24_990_000),
        ("10m",  28_000_000, 28_000_000...29_700_000),
        ("6m",   50_000_000, 50_000_000...54_000_000),
    ]

    func bandStepUp() {
        guard let hz = vfoAFrequencyHz else { return }
        let idx  = Self._bandStepTable.firstIndex(where: { $0.range.contains(hz) }) ?? -1
        let next = min(idx + 1, Self._bandStepTable.count - 1)
        guard next >= 0 else { return }
        _applyBandStep(to: Self._bandStepTable[next], currentHz: hz)
    }

    func bandStepDown() {
        guard let hz = vfoAFrequencyHz else { return }
        let idx  = Self._bandStepTable.firstIndex(where: { $0.range.contains(hz) }) ?? Self._bandStepTable.count
        let prev = max(idx - 1, 0)
        _applyBandStep(to: Self._bandStepTable[prev], currentHz: hz)
    }

    private func _applyBandStep(
        to entry: (label: String, defaultHz: Int, range: ClosedRange<Int>),
        currentHz: Int
    ) {
        if let cur = Self._bandStepTable.first(where: { $0.range.contains(currentHz) }) {
            UserDefaults.standard.set(currentHz, forKey: "bandFreq_A_\(cur.label)")
        }
        let stored = UserDefaults.standard.integer(forKey: "bandFreq_A_\(entry.label)")
        let target = stored > 0 ? stored : entry.defaultHz
        send(KenwoodCAT.setVFOAFrequencyHz(target))
    }

    // Called from the FA frame handler. Debounced so rapid VFO tuning doesn't spam
    // UserDefaults — only persists after the frequency has been stable for 1 second.
    private func _scheduleBandFreqSave(hz: Int) {
        _bandFreqSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            guard let band = Self._bandRanges.first(where: { $0.1.contains(hz) })?.0 else { return }
            UserDefaults.standard.set(hz, forKey: "bandFreq_A_\(band)")
        }
        _bandFreqSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func recallMemoryChannel(_ channel: Int) {
        let clamped = max(0, min(channel, 119))
        memoryChannelNumber = clamped
        send(KenwoodCAT.setMemoryChannelNumber(clamped))
        send(KenwoodCAT.getMemoryChannelNumber())
        send(KenwoodCAT.getMemoryChannelConfiguration(clamped))
    }

    func queryMemoryChannel(_ channel: Int) {
        let clamped = max(0, min(channel, 119))
        send(KenwoodCAT.getMemoryChannelConfiguration(clamped))
    }

    func programMemoryChannel(channel: Int, frequencyHz: Int, mode: KenwoodCAT.OperatingMode, fmNarrow: Bool, name: String) {
        let ch = max(0, min(channel, 119))
        let hz = max(0, min(frequencyHz, 99_999_999_999))
        memoryChannelNumber = ch
        AppFileLogger.shared.log("UI: Program memory ch=\(ch) hz=\(hz) mode=\(mode.rawValue) fmNarrow=\(fmNarrow) name=\(name)")

        // Select the channel, then write frequency/mode, then name (optional).
        send(KenwoodCAT.setMemoryChannelNumber(ch))
        send(KenwoodCAT.setMemoryChannelDirectWriteFrequencyHz(hz, mode: mode, fmNarrow: fmNarrow))

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            send(KenwoodCAT.setMemoryChannelName(ch, name: trimmedName))
        }

        // Read back for confirmation.
        send(KenwoodCAT.getMemoryChannelNumber())
        send(KenwoodCAT.getMemoryChannelConfiguration(ch))
    }

    // MARK: - Memory Browser — batch load all 120 channels

    func loadAllMemoryChannels() {
        guard !isLoadingAllMemories else { return }
        isLoadingAllMemories = true
        memoryChannels = []
        AppFileLogger.shared.log("Memory: loading all 120 channels")
        // Stagger requests by 50 ms to avoid flooding the radio's command queue.
        for ch in 0..<120 {
            let delay = Double(ch) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.send(KenwoodCAT.getMemoryChannelConfiguration(ch))
                if ch == 119 {
                    // Allow last response time to arrive before clearing the flag.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.isLoadingAllMemories = false
                    }
                }
            }
        }
    }

    func startATUTuning() {
        send(KenwoodCAT.startAntennaTuning())
        send(KenwoodCAT.getAntennaTuner())
    }

    func stopATUTuning() {
        let enabled = atuTxEnabled ?? false
        send(KenwoodCAT.stopAntennaTuning(txEnabled: enabled))
        send(KenwoodCAT.getAntennaTuner())
    }

    func setSplitOffset(plus: Bool, khz: Int) {
        splitOffsetPlus = plus
        splitOffsetKHz = khz
        send(KenwoodCAT.startSplitOffsetSetting())
        send(KenwoodCAT.setSplitOffset(plus: plus, khz: khz))
        send(KenwoodCAT.getSplitOffsetSettingState())
    }

    func startAudioMonitor() {
        audioMonitorError = nil
        guard !isAudioMonitorRunning else { return }
        guard let inputID = AudioDeviceManager.deviceID(forUID: selectedAudioInputUID) else {
            audioMonitorError = "Select an audio input device"
            return
        }
        let outputID: AudioDeviceID
        if let id = AudioDeviceManager.deviceID(forUID: selectedAudioOutputUID) {
            outputID = id
        } else if let id = AudioDeviceManager.defaultOutputDeviceID() {
            outputID = id
        } else {
            audioMonitorError = "No audio output device"
            return
        }

        let monitor = AudioMonitor(processor: processorProxy)
        monitor.wetDry = Float(audioMonitorWetDry)
        monitor.inputGain = Float(audioMonitorInputGain)
        monitor.outputGain = Float(audioMonitorOutputGain) * (isAudioMuted ? 0.0 : 1.0)
        monitor.onLog = { [weak self] msg in
            DispatchQueue.main.async {
                self?.audioMonitorLog.append(msg)
                if (self?.audioMonitorLog.count ?? 0) > 50 {
                    self?.audioMonitorLog.removeFirst((self?.audioMonitorLog.count ?? 0) - 50)
                }
            }
        }
        monitor.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.audioMonitorError = msg
                self?.audioMonitorLog.append("Error: \(msg)")
            }
        }

        do {
            try monitor.start(inputDeviceID: inputID, outputDeviceID: outputID)
            audioMonitor = monitor
            isAudioMonitorRunning = true
        } catch {
            audioMonitorError = error.localizedDescription
            audioMonitor = nil
            isAudioMonitorRunning = false
        }
    }

    func stopAudioMonitor() {
        audioMonitor?.stop()
        audioMonitor = nil
        isAudioMonitorRunning = false
    }

    // MARK: - TX Audio Passthrough (USB mic → USB Codec)

    func setTXAudioSource(_ source: TXAudioSource) {
        txAudioSource = source
        UserDefaults.standard.set(source.rawValue, forKey: txAudioSourceKey)
        switch source {
        case .hardware:
            stopTXPassthrough()
            send("MS010;")  // P1=0(PTT), P2=1(Front Mic), P3=0(Rear OFF)
        case .usbPassthrough:
            send("MS002;")
            startTXPassthrough()
        }
    }

    func startTXPassthrough() {
        stopTXPassthrough()
        guard txAudioSource == .usbPassthrough else { return }

        // Require explicit device selections — do not fall back to system defaults.
        // Accidentally routing the wrong mic to the radio transmitter would be harmful.
        guard !selectedTXMicInputUID.isEmpty else {
            txPassthroughError = "Select a microphone input device for TX"
            return
        }
        guard !selectedTXCodecOutputUID.isEmpty else {
            txPassthroughError = "Select the TS-890S USB Codec output device for TX"
            return
        }

        guard let inputID = AudioDeviceManager.deviceID(forUID: selectedTXMicInputUID) else {
            txPassthroughError = "Selected TX mic device is no longer available"
            return
        }
        guard let outputID = AudioDeviceManager.deviceID(forUID: selectedTXCodecOutputUID) else {
            txPassthroughError = "Selected USB Codec output device is no longer available"
            return
        }

        let pt = AudioPassthrough()
        pt.inputGain = Float(txPassthroughInputGain)
        pt.onLog = { [weak self] msg in
            DispatchQueue.main.async {
                self?.audioMonitorLog.append(msg)
                if (self?.audioMonitorLog.count ?? 0) > 50 {
                    self?.audioMonitorLog.removeFirst((self?.audioMonitorLog.count ?? 0) - 50)
                }
            }
        }
        pt.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.txPassthroughError = msg
                self?.isTXPassthroughRunning = false
            }
        }
        do {
            try pt.start(inputDeviceID: inputID, outputDeviceID: outputID)
            txPassthrough = pt
            isTXPassthroughRunning = true
            txPassthroughError = nil
        } catch {
            txPassthroughError = error.localizedDescription
            isTXPassthroughRunning = false
        }
    }

    func stopTXPassthrough() {
        txPassthrough?.stop()
        txPassthrough = nil
        isTXPassthroughRunning = false
    }

    /// Configures the radio for WSJT-X / digital mode.
    /// Saves the current operating mode, then sends OM0D (USB-DATA) + MS002 (Rear=USB Audio).
    func configureForDigitalMode() {
        previousOperatingModeForDigital = operatingMode
        send("OM0D;")   // USB-DATA mode (P2=D)
        send("MS002;")  // SEND/PTT (P1=0), Front=OFF (P2=0), Rear=USB Audio (P3=2)
        isConfiguredForDigitalMode = true
        AppFileLogger.shared.log("CAT: configured for digital mode — USB-DATA, USB audio source, previous mode=\(operatingMode?.label ?? "unknown")")
        postRadioNotification(
            title: "Radio Configured for WSJT-X",
            body: "TS-890S is now in USB-DATA mode with USB audio TX. Press Revert in the app when finished."
        )
    }

    /// Restores the radio to the mode it was in before configureForDigitalMode() was called.
    /// Sends the previous OM mode + MS010 (SEND/PTT, Front=Microphone, Rear=OFF).
    func revertFromDigitalMode() {
        let revertMode = previousOperatingModeForDigital ?? .usb
        send(KenwoodCAT.setOperatingMode(revertMode))
        send("MS010;")  // SEND/PTT (P1=0), Front=Microphone (P2=1), Rear=OFF (P3=0)
        isConfiguredForDigitalMode = false
        previousOperatingModeForDigital = nil
        AppFileLogger.shared.log("CAT: reverted from digital mode to \(revertMode.label)")
        postRadioNotification(
            title: "Radio Reverted to Voice Mode",
            body: "TS-890S restored to \(revertMode.label) with microphone input."
        )
    }

    // MARK: - FreeDV activation

    func activateFreeDV(mode: FreeDVEngine.Mode, audioPath: FreeDVAudioPath) {
        guard !freedvIsActive else { return }

        // Save the current mode and TX audio source so we can restore them on deactivate.
        previousModeBeforeFreeDV = operatingMode
        previousTxAudioSourceBeforeFreeDV = txAudioSource

        // Switch radio to USB-DATA.
        send("OM0D;")

        // Open the codec2 FreeDV engine.
        freedvEngine.open(mode: mode)
        freedvEngine.txCallsign = freedvTxCallsign
        freedvEngine.onStatsUpdate = { [weak self] sync, snr, ber, tb, tbe, status in
            DispatchQueue.main.async {
                guard let self else { return }
                let wasSync = self.freedvSync
                self.freedvSync            = sync
                self.freedvSnrDB           = snr
                self.freedvBer             = ber
                self.freedvTotalBits       = tb
                self.freedvTotalBitErrors  = tbe
                self.freedvRxStatus        = status
                if sync && !wasSync {
                    self.announceInfo("FreeDV synchronized, SNR \(Int(snr)) dB")
                } else if !sync && wasSync {
                    self.announceInfo("FreeDV sync lost")
                }
            }
        }
        freedvEngine.onTextReceived = { [weak self] char in
            DispatchQueue.main.async {
                guard let self else { return }
                self.freedvReceivedText.append(char)
                if self.freedvReceivedText.count > 500 {
                    self.freedvReceivedText = String(self.freedvReceivedText.suffix(500))
                }
            }
        }

        if audioPath == .lan {
            // LAN (KNS) audio path.
            send("MS003;") // Rear = LAN (KNS audio carries modem tones)

            let rxPipe = FreeDVLanRxPipeline(engine: freedvEngine)
            rxPipe.onAudio48kMono = { [weak self] samples in
                self?.lanPlayer?.enqueue48kMono(samples)
            }
            freedvLanRxPipeline = rxPipe

            // Ensure LAN audio is running first (receiver must exist before wiring TX).
            if !isLanAudioRunning && !currentHost.isEmpty {
                startLanAudio(host: currentHost)
            }

            if let receiver = lanReceiver {
                let txPipe = FreeDVLanTxPipeline(engine: freedvEngine, receiver: receiver)
                txPipe.onLog   = { msg in AppFileLogger.shared.log("FreeDV TX: \(msg)") }
                txPipe.onError = { [weak self] msg in
                    DispatchQueue.main.async { self?.freedvError = msg }
                }
                freedvLanTxPipeline = txPipe
            }

        } else {
            // USB AUDIO CODEC path.
            send("MS002;") // Rear = USB audio codec

            // Find the TS-890S USB AUDIO CODEC by name (partial, case-insensitive).
            let usbInfo = AudioDeviceManager.inputDevices()
                .first { $0.name.localizedCaseInsensitiveContains("USB Audio CODEC") }
            guard let usbID = usbInfo.map(\.id) else {
                freedvError = "USB Audio CODEC device not found — connect TS-890S USB cable"
                freedvEngine.close()
                return
            }
            let speakerID = AudioDeviceManager.defaultOutputDeviceID() ?? AudioDeviceID(kAudioObjectSystemObject)

            let usbPipe = FreeDVUsbPipeline(engine: freedvEngine)
            usbPipe.onLog   = { msg in AppFileLogger.shared.log("FreeDV USB: \(msg)") }
            usbPipe.onError = { [weak self] msg in
                DispatchQueue.main.async { self?.freedvError = msg }
            }
            do {
                try usbPipe.start(usbDeviceID: usbID, speakerDeviceID: speakerID)
                freedvUsbPipeline = usbPipe
            } catch {
                freedvError = "FreeDV USB pipeline: \(error.localizedDescription)"
                freedvEngine.close()
                return
            }
        }

        freedvMode      = mode
        freedvAudioPath = audioPath
        freedvIsActive  = true
        freedvError     = nil
        UserDefaults.standard.set(mode.rawValue, forKey: "freedv_mode")
        UserDefaults.standard.set(audioPath.rawValue, forKey: "freedv_audio_path")
        AppFileLogger.shared.log("FreeDV: activated mode=\(mode.label) path=\(audioPath.rawValue)")
    }

    func deactivateFreeDV() {
        guard freedvIsActive else { return }

        // Stop TX if app owns PTT — don't release if externally keyed.
        if isAppPTTActive { setPTT(down: false) }

        freedvLanTxPipeline?.stop()
        freedvLanTxPipeline = nil
        freedvLanRxPipeline = nil   // just a callback wrapper — no stop needed
        freedvUsbPipeline?.stop()
        freedvUsbPipeline   = nil
        freedvEngine.close()

        // Restore previous radio mode and TX audio source.
        let revertMode = previousModeBeforeFreeDV ?? .usb
        send(KenwoodCAT.setOperatingMode(revertMode))
        setTXAudioSource(previousTxAudioSourceBeforeFreeDV ?? .hardware)
        previousModeBeforeFreeDV = nil
        previousTxAudioSourceBeforeFreeDV = nil

        freedvIsActive        = false
        freedvSync            = false
        freedvSnrDB           = 0
        freedvBer             = 0
        freedvTotalBits       = 0
        freedvTotalBitErrors  = 0
        freedvRxStatus        = 0
        AppFileLogger.shared.log("FreeDV: deactivated, restored \(revertMode.label)")
    }

    private func postRadioNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil   // deliver immediately
            )
            center.add(request)
        }
    }

    func setAudioMonitorWetDry(_ value: Double) {
        audioMonitorWetDry = value
        audioMonitor?.wetDry = Float(value)
    }

    func setAudioMonitorInputGain(_ value: Double) {
        audioMonitorInputGain = value
        audioMonitor?.inputGain = Float(value)
    }

    func setAudioMonitorOutputGain(_ value: Double) {
        audioMonitorOutputGain = value
        audioMonitor?.outputGain = Float(value) * (isAudioMuted ? 0.0 : 1.0)
    }

    func startLanAudio(host: String) {
        AppFileLogger.shared.log("LAN: startLanAudio host=\(host) isRunning=\(isLanAudioRunning)")
        lanAudioError = nil
        guard !isLanAudioRunning else {
            AppFileLogger.shared.log("LAN: startLanAudio skipped — already running")
            return
        }
        lanAudioPacketCountRaw = 0
        lanAudioLastPacketAtRaw = nil
        lanAudioPacketCount = 0
        lanAudioLastPacketAt = nil

        // Start output first, so we can surface any errors early.
        let player = AudioOutputPlayer(sampleRate: 48_000)
        player.gain = Float(lanAudioOutputGain) * (isAudioMuted ? 0.0 : 1.0)
        do {
            try player.start(outputDeviceID: AudioDeviceManager.deviceID(forUID: selectedLanAudioOutputUID))
        } catch {
            let msg = "LAN audio player failed: \(error.localizedDescription)"
            AppFileLogger.shared.log(msg)
            lanAudioError = error.localizedDescription
            announceError(msg)
            return
        }

        let pipeline = LanAudioPipeline(processor: processorProxy, frameSize: 480)
        pipeline.wetDry = Float(lanAudioWetDry)

        let receiver = KenwoodLanAudioReceiver()
        receiver.onError = { [weak self] msg in
            AppLogger.error("LAN audio error: \(msg)")
            AppFileLogger.shared.log("LAN audio error: \(msg)")
            DispatchQueue.main.async {
                self?.lanAudioError = msg
            }
        }
        receiver.onLog = { [weak self] msg in
            AppLogger.info("LAN: \(msg)")
            AppFileLogger.shared.log("LAN: \(msg)")
            DispatchQueue.main.async {
                self?.connectionLog.append("LAN: \(msg)")
                if (self?.connectionLog.count ?? 0) > 50 {
                    self?.connectionLog.removeFirst((self?.connectionLog.count ?? 0) - 50)
                }
            }
        }
        receiver.onPacket = { [weak self] seq, ssrc, payloadBytes in
            guard let self else { return }
            self.lanAudioPacketCountRaw &+= 1
            self.lanAudioLastPacketAtRaw = Date()

            // Updating @Published 50 times/sec can make SwiftUI + VoiceOver feel hung.
            // Publish only occasionally while keeping accurate internal counts.
            let n = self.lanAudioPacketCountRaw
            if n == 1 || (n % 25) == 0 {
                let lastAt = self.lanAudioLastPacketAtRaw
                DispatchQueue.main.async {
                    self.lanAudioPacketCount = n
                    self.lanAudioLastPacketAt = lastAt
                    if n == 1 {
                        self.connectionLog.append("LAN: first packet seq=\(seq) ssrc=\(String(format: "0x%08X", ssrc)) bytes=\(payloadBytes)")
                        AppLogger.info("LAN: first packet seq=\(seq) ssrc=\(String(format: "0x%08X", ssrc)) bytes=\(payloadBytes)")
                        AppFileLogger.shared.log("LAN: first packet seq=\(seq) ssrc=\(String(format: "0x%08X", ssrc)) bytes=\(payloadBytes)")
                    }
                }
            }
        }
        receiver.onAudio48kMono = { [weak self] samples in
            guard let self else { return }
            if let tap = onLanRxAudio48kMono {
                // Copy the frame to decouple from any internal buffers.
                let frame = samples
                lanRxTapQueue.async { tap(frame) }
            }
            // When FreeDV LAN is active, decoded speech is enqueued by the RX pipeline.
            // Do not pass raw modem tones through the NR pipeline.
            if freedvIsActive && freedvAudioPath == .lan { return }
            pipeline.process48kMono(samples) { [weak self] outFrame in
                self?.lanPlayer?.enqueue48kMono(outFrame)
            }
        }
        receiver.onModemSamplesInt16 = { [weak self] samples in
            guard let self, freedvIsActive && freedvAudioPath == .lan else { return }
            freedvLanRxPipeline?.feed16kSamples(samples)
        }

        do {
            try receiver.start(host: host, port: 60001)
        } catch {
            player.stop()
            let msg = "LAN audio receiver failed: \(error.localizedDescription)"
            AppFileLogger.shared.log(msg)
            lanAudioError = error.localizedDescription
            announceError(msg)
            return
        }

        lanPlayer = player
        lanPipeline = pipeline
        lanReceiver = receiver
        isLanAudioRunning = true

        // If FreeDV LAN was activated before LAN audio was started, wire the TX pipeline now.
        if freedvIsActive && freedvAudioPath == .lan && freedvLanTxPipeline == nil {
            let txPipe = FreeDVLanTxPipeline(engine: freedvEngine, receiver: receiver)
            txPipe.onLog   = { msg in AppFileLogger.shared.log("FreeDV TX: \(msg)") }
            txPipe.onError = { [weak self] msg in DispatchQueue.main.async { self?.freedvError = msg } }
            freedvLanTxPipeline = txPipe
        }

        AppFileLogger.shared.log("LAN: output device uid=\(selectedLanAudioOutputUID.isEmpty ? "(default)" : selectedLanAudioOutputUID)")

        // Kenwood KNS VoIP: explicitly start voice communication; otherwise the radio may not emit UDP 60001.
        // P1: 0=Stop, 1=Start (high quality), 2=Start (low quality). (TS-890 PC command guide: ##VP)
        if useKnsLogin {
            connection.send("##VP1;")
        }
    }

    func stopLanAudio() {
        if useKnsLogin {
            // Tell the radio to stop its VoIP UDP stream. This runs before connection.disconnect()
            // in the explicit-disconnect path, so the NWConnection is still open.
            connection.send("##VP0;")
        }
        stopMicCapture()
        // Final publish snapshot (useful if UI throttling skipped the last updates).
        lanAudioPacketCount = lanAudioPacketCountRaw
        lanAudioLastPacketAt = lanAudioLastPacketAtRaw
        lanReceiver?.stop()
        lanReceiver = nil
        lanPipeline = nil
        lanPlayer?.stop()
        lanPlayer = nil
        isLanAudioRunning = false
    }

    func setLanAudioWetDry(_ value: Double) {
        lanAudioWetDry = value
        lanPipeline?.wetDry = Float(value)
    }

    func setLanAudioOutputGain(_ value: Double) {
        lanAudioOutputGain = value
        lanPlayer?.gain = Float(value) * (isAudioMuted ? 0.0 : 1.0)
    }

    func applyLanAudioOutputSelection() {
        // Explicit entrypoint for the View (helps debug when Combine observation is unreliable).
        AppFileLogger.shared.log("LAN: apply output selection uid=\(selectedLanAudioOutputUID.isEmpty ? "(default)" : selectedLanAudioOutputUID)")
        switchLanAudioOutputIfRunning()
    }

    private func switchLanAudioOutputIfRunning() {
        AppFileLogger.shared.log("LAN: switch output requested running=\(isLanAudioRunning) uid=\(selectedLanAudioOutputUID.isEmpty ? "(default)" : selectedLanAudioOutputUID)")
        guard isLanAudioRunning else { return }
        guard let player = lanPlayer else { return }
        let id = AudioDeviceManager.deviceID(forUID: selectedLanAudioOutputUID)
        AppFileLogger.shared.log("LAN: switch output deviceID=\(id ?? 0)")

        // Restart player to apply new output device. Keep receiver/pipeline running.
        player.stop()
        do {
            try player.start(outputDeviceID: id)
            player.gain = Float(lanAudioOutputGain) * (isAudioMuted ? 0.0 : 1.0)
            AppFileLogger.shared.log("LAN: switched output device uid=\(selectedLanAudioOutputUID.isEmpty ? "(default)" : selectedLanAudioOutputUID)")
        } catch {
            lanAudioError = error.localizedDescription
            AppFileLogger.shared.log("LAN: switch output failed: \(error.localizedDescription)")
        }
    }

    private func setNoiseReductionStrength(_ value: Double, persist: Bool) {
        let clamped = max(0.0, min(1.0, value))
        noiseReductionStrength = clamped
        // Drive both pipelines from one "strength" knob. Wet/dry mix is a stable,
        // artifact-safe way to tune aggressiveness without changing the RNNoise model.
        setLanAudioWetDry(clamped)
        setAudioMonitorWetDry(clamped)
        if persist { persistNoiseReductionSettings() }
        AppFileLogger.shared.log("NR: strength=\(String(format: "%.2f", clamped)) profile=\(noiseReductionProfileRaw)")
    }

    private func applyNoiseReductionProfile(persist: Bool) {
        let profile = NoiseReductionProfile(rawValue: noiseReductionProfileRaw) ?? .speech
        // Profile sets a good starting point; user can fine-tune with the strength slider.
        setNoiseReductionStrength(profile.recommendedStrength, persist: false)
        if persist { persistNoiseReductionSettings() }
        AppFileLogger.shared.log("NR: profile=\(profile.rawValue) recommendedStrength=\(String(format: "%.2f", profile.recommendedStrength))")
    }

    private func loadPersistedNoiseReductionSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: nrStrengthKey) != nil {
            noiseReductionStrength = d.double(forKey: nrStrengthKey)
        }
        if let raw = d.string(forKey: nrProfileKey), !raw.isEmpty {
            noiseReductionProfileRaw = raw
        }
        // Restore last-used backend — but never restore Passthrough as the default;
        // if no backend was saved or the saved one isn't valid, keep the auto-selected one.
        if let saved = d.string(forKey: nrBackendKey),
           !saved.isEmpty,
           saved != "Passthrough (disabled)",
           availableNoiseReductionBackends.contains(saved) {
            setNoiseReductionBackend(saved)
        }
        AppFileLogger.shared.log("Loaded saved NR settings strength=\(String(format: "%.2f", noiseReductionStrength)) profile=\(noiseReductionProfileRaw) backend=\(noiseReductionBackend)")
    }

    private func persistNoiseReductionSettings() {
        let d = UserDefaults.standard
        d.set(noiseReductionStrength, forKey: nrStrengthKey)
        d.set(noiseReductionProfileRaw, forKey: nrProfileKey)
        d.set(selectedNoiseReductionBackend, forKey: nrBackendKey)
    }

    private func loadPersistedFilterSlotSettings() {
        let d = UserDefaults.standard
        if let raw = d.array(forKey: "filterSlotDisplayModes") as? [String], raw.count == 3 {
            filterSlotDisplayModes = raw.map { FilterSlotDisplayMode(rawValue: $0) ?? .hiLoCut }
        }
        if let saved = d.array(forKey: "filterSlotIFShiftHz") as? [Int], saved.count == 3 {
            filterSlotIFShiftHz = saved
        }
    }

    func runSmokeTest() {
        smokeTestStatus = "Running"
        announceInfo("Smoke test started")
        DiagnosticsStore.shared.lastTXFrame = "SMOKE: TX"
        DiagnosticsStore.shared.lastRXFrame = "SMOKE: RX"
        smokeTestStatus = "Complete"
        announceInfo("Smoke test complete")
    }

    func loadSavedCredentials(host: String) {
        let typeRaw = knsAccountType
        if let u = KNSSettings.loadUsername(host: host, accountTypeRaw: typeRaw) {
            adminId = u
            if let p = KNSSettings.loadPassword(host: host, accountTypeRaw: typeRaw, username: u) {
                adminPassword = p
            } else {
                adminPassword = ""
            }
            knsCredentialCache["\(typeRaw)|\(host)"] = (u, adminPassword)
            AppFileLogger.shared.log("Loaded saved credentials for host \(host) type \(typeRaw)")
        } else {
            adminId = ""
            adminPassword = ""
        }
    }

    func handleFrame(_ frame: String) {
        let cleaned = frame.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let core = cleaned.hasSuffix(";") ? String(cleaned.dropLast()) : cleaned

        if core.hasPrefix("FA") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let hz = Int(digits) {
                vfoAFrequencyHz = hz
                autoSwitchModeIfBandChanged(newHz: hz)
                _scheduleBandFreqSave(hz: hz)
            }
            return
        }

        if core.hasPrefix("FB") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let hz = Int(digits) { vfoBFrequencyHz = hz }
            return
        }

        if core.hasPrefix("CK0"), core.count >= 15 {
            // CK0 read-back: payload = YYMMDDHHMMSS (12 digits after "CK0")
            let payload = String(core.dropFirst(3))
            if let cb = pendingCKReadback {
                pendingCKReadback = nil
                cb(payload)
            }
            return
        }

        if core.hasPrefix("OM"), core.count >= 4 {
            // Format: OM + P1 + P2 (P2 is a single hex digit: 1-9, A-F)
            let params = core.dropFirst(2)
            let modeChar = String(params.dropFirst().prefix(1))
            if let raw = Int(modeChar, radix: 16), let mode = KenwoodCAT.OperatingMode(rawValue: raw) {
                let prev = operatingMode
                operatingMode = mode
                // Query APF state when entering CW or CW-R (APF is CW-only hardware).
                if mode == .cw || mode == .cwR,
                   prev != .cw && prev != .cwR {
                    send(KenwoodCAT.getAPFEnabled())
                    send(KenwoodCAT.getAPFShift())
                    send(KenwoodCAT.getAPFBandwidth())
                    send(KenwoodCAT.getAPFGain())
                }
            }
            return
        }

        if core.hasPrefix("ID"), core.count >= 5 {
            let newModel = KenwoodRadioModel(idResponse: core)
            if newModel != radioModel {
                radioModel = newModel
                capabilities = KenwoodCapabilities.capabilities(for: newModel)
                AppFileLogger.shared.log("Radio identified: \(newModel) (\(newModel.description))")
                if !capabilities.hasLANAudio && isLanAudioRunning {
                    AppFileLogger.shared.log("LAN Audio: stopping — \(newModel) does not support LAN audio streaming")
                    stopLanAudio()
                }
            }
            return
        }

        if core.hasPrefix("MD") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { mdMode = v }
            return
        }

        if core.hasPrefix("BS4"), core.count >= 4 {
            let spanTable = [5, 10, 25, 50, 100, 200, 500]
            if let code = Int(core.dropFirst(3).prefix(1)), code < spanTable.count {
                scopeSpanKHz = spanTable[code]
            }
            return
        }

        if core.hasPrefix("DA"), core.count >= 3 {
            // DA + P1 (0/1). Some rigs may respond with `?;` instead.
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                dataModeEnabled = (raw == 1)
            }
            return
        }

        if core.hasPrefix("FR") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let vfo = KenwoodCAT.VFO(rawValue: raw) {
                rxVFO = vfo
            }
            return
        }

        if core.hasPrefix("FT") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let vfo = KenwoodCAT.VFO(rawValue: raw) {
                txVFO = vfo
            }
            return
        }

        if core.hasPrefix("NR") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let mode = KenwoodCAT.NoiseReductionMode(rawValue: raw) {
                transceiverNRMode = mode
            }
            return
        }

        if core.hasPrefix("RT") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                ritEnabled = (raw == 1)
            }
            return
        }

        if core.hasPrefix("XT") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                xitEnabled = (raw == 1)
            }
            return
        }

        if core.hasPrefix("RF"), core.count >= 7 {
            // RF + P1(direction 0/1) + P2P2P2P2 (Hz)
            let params = core.dropFirst(2)
            let dirChar = params.prefix(1)
            let hzDigits = params.dropFirst(1).prefix(4)
            if let dir = Int(dirChar), let hz = Int(hzDigits) {
                ritXitOffsetHz = (dir == 1) ? -hz : hz
            }
            return
        }

        if core.hasPrefix("IS"), core.count >= 7 {
            // IS + sign (+/-/space) + 4 digits
            let params = core.dropFirst(2)
            let signChar = params.prefix(1)
            let hzDigits = params.dropFirst(1).prefix(4)
            if let hz = Int(hzDigits) {
                let sign = (signChar == "-") ? -1 : 1
                rxFilterShiftHz = hz * sign
            }
            return
        }

        if core.hasPrefix("SL"), core.count >= 5 {
            // SL + P1(type) + P2P2
            let params = core.dropFirst(2)
            let typeChar = params.prefix(1)
            let idDigits = params.dropFirst(1).prefix(2)
            if typeChar == "0", let id = Int(idDigits) {
                rxFilterLowCutID = id
            }
            return
        }

        if core.hasPrefix("SH"), core.count >= 6 {
            // SH + P1(type) + P2P2P2
            let params = core.dropFirst(2)
            let typeChar = params.prefix(1)
            let idDigits = params.dropFirst(1).prefix(3)
            if typeChar == "0", let id = Int(idDigits) {
                rxFilterHighCutID = id
            }
            return
        }

        if core.hasPrefix("TF1"), core.count >= 6 {
            // TF1 + P1(type, 1 char) + P2P2 (2-digit ID 00–99). We use type=0 (settings).
            let typeChar = core.dropFirst(3).prefix(1)
            if typeChar == "0", let id = Int(core.dropFirst(4).prefix(2)) {
                txFilterLowCutID = id
            }
            return
        }

        // FL P1 P2; — filter slot for display area P1 (we use P1=0, main VFO).
        // Response: FL0n; where n=0(A),1(B),2(C).
        if core.hasPrefix("FL0"), core.count >= 4 {
            if let id = Int(core.dropFirst(3).prefix(1)),
               let slot = KenwoodCAT.FilterSlot(rawValue: id) {
                filterSlot = slot
            }
            return
        }

        if core.hasPrefix("TF2"), core.count >= 7 {
            // TF2 + P1(type, 1 char) + P2P2P2 (3-digit ID 000–999). We use type=0 (settings).
            let typeChar = core.dropFirst(3).prefix(1)
            if typeChar == "0", let id = Int(core.dropFirst(4).prefix(3)) {
                txFilterHighCutID = id
            }
            return
        }

        if core.hasPrefix("PC") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let w = Int(digits) { outputPowerWatts = w }
            return
        }

        if core.hasPrefix("MV") {
            // MV P1 ;; (0 = VFO, 1 = Memory Channel)
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                isMemoryMode = (raw == 1)
            }
            return
        }

        if core.hasPrefix("MN") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let ch = Int(digits) {
                memoryChannelNumber = ch
            }
            return
        }

        // SC0 P1 P2; — scan on/off state. P1: 0=stopped, 1=scanning. P2: slow-scan flag.
        if core.hasPrefix("SC0"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)) {
                scanActive = (v == 1)
            }
            return
        }

        // SC1 P1; — scan speed 1–9.
        if core.hasPrefix("SC1"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)) {
                scanSpeed = v
            }
            return
        }

        // SC2 P1; — tone/CTCSS scan mode. 0=Off, 1=Tone, 2=CTCSS (FM only).
        if core.hasPrefix("SC2"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)),
               let mode = KenwoodCAT.ToneScanMode(rawValue: v) {
                toneScanMode = mode
            }
            return
        }

        // SC3 P1; — scan type. 0=Program, 1=VFO.
        if core.hasPrefix("SC3"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)),
               let type = KenwoodCAT.ScanType(rawValue: v) {
                scanType = type
            }
            return
        }

        // AN P1 P2 P3 P4; — antenna selection
        if core.hasPrefix("AN"), core.count >= 6 {
            let p = core.dropFirst(2)
            if let p1 = Int(p.prefix(1)), let p2 = Int(p.dropFirst(1).prefix(1)),
               let p3 = Int(p.dropFirst(2).prefix(1)), let p4 = Int(p.dropFirst(3).prefix(1)) {
                antennaPort = p1
                rxAntennaInUse = (p2 == 1)
                driveOutEnabled = (p3 == 1)
                antennaOutputEnabled = (p4 == 1)
            }
            return
        }

        // AP0 P1; — APF on/off. 1=OFF, 2=ON.
        if core.hasPrefix("AP0"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)) {
                apfEnabled = (v == 2)
            }
            return
        }

        // AP1 P1 P1; — APF shift 00–80 (2-digit).
        if core.hasPrefix("AP1"), core.count >= 5 {
            if let v = Int(core.dropFirst(3).prefix(2)) {
                apfShift = v
            }
            return
        }

        // AP2 P1; — APF bandwidth. 0=NAR, 1=MID, 2=WIDE.
        if core.hasPrefix("AP2"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)),
               let bw = KenwoodCAT.APFBandwidth(rawValue: v) {
                apfBandwidth = bw
            }
            return
        }

        // AP3 P1; — APF gain 0–6.
        if core.hasPrefix("AP3"), core.count >= 4 {
            if let v = Int(core.dropFirst(3).prefix(1)) {
                apfGain = v
            }
            return
        }

        // BD P1 P3; / BU P1 P3; — band change response. State updates arrive via FA/FB.
        if core.hasPrefix("BD") || core.hasPrefix("BU") {
            return
        }

        if core.hasPrefix("MA0"), core.count >= 7 {
            // MA0 + channel(3) + freq(11) + mode(1) + ... + name(<=10)
            let params = core.dropFirst(3)
            let chStr = String(params.prefix(3)).trimmingCharacters(in: .whitespaces)
            let rest = params.dropFirst(3)
            if let ch = Int(chStr) {
                // Only overwrite details when the MA0 response matches the selected channel.
                if memoryChannelNumber == nil || memoryChannelNumber == ch {
                    memoryChannelNumber = ch

                    let freqField = String(rest.prefix(11))
                    let freqDigits = freqField.filter(\.isNumber)
                    if !freqDigits.isEmpty, let hz = Int(freqDigits) {
                        memoryChannelFrequencyHz = hz
                    } else {
                        memoryChannelFrequencyHz = nil
                    }

                    let modeField = String(rest.dropFirst(11).prefix(1))
                    if let raw = Int(modeField), let mode = KenwoodCAT.OperatingMode(rawValue: raw) {
                        memoryChannelMode = mode
                    } else {
                        memoryChannelMode = nil
                    }

                    // Name starts after freq(11) + mode(1) + narrow(1) = offset 13 within `rest`.
                    let name = String(rest.dropFirst(13).prefix(10)).trimmingCharacters(in: .whitespaces)
                    memoryChannelName = name.isEmpty ? nil : name

                    // Also populate the MemoryBrowserView array regardless of selected channel.
                    let hz = memoryChannelFrequencyHz ?? 0
                    let mode = memoryChannelMode ?? .usb
                    let isEmpty = (hz == 0)
                    let entry = MemoryChannel(id: ch, frequencyHz: hz, mode: mode, name: name, isEmpty: isEmpty)
                    if let idx = memoryChannels.firstIndex(where: { $0.id == ch }) {
                        memoryChannels[idx] = entry
                    } else {
                        // Insert in order
                        let insertIdx = memoryChannels.firstIndex(where: { $0.id > ch }) ?? memoryChannels.endIndex
                        memoryChannels.insert(entry, at: insertIdx)
                    }
                }
            }
            return
        }

        if core.hasPrefix("AC"), core.count >= 5 {
            // AC + P1(rx) + P2(tx) + P3(tune active)
            let params = core.dropFirst(2)
            let p1 = params.prefix(1)
            let p2 = params.dropFirst(1).prefix(1)
            let p3 = params.dropFirst(2).prefix(1)
            if let txRaw = Int(p2) { atuTxEnabled = (txRaw == 1) }
            if let tuneRaw = Int(p3) { atuTuningActive = (tuneRaw == 1) }
            // We don't surface rx AT yet; docs say use EX to set it.
            _ = p1
            return
        }

        if core.hasPrefix("SP") {
            // Answer is SP + P1 (0/1). Setting details are not echoed.
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                splitOffsetSettingActive = (raw == 1)
            }
            return
        }

        if core.hasPrefix("##KN3"), core.count >= 7 {
            // ##KN3 + P1(type) + P2P2P2(level)
            let params = core.dropFirst(5)
            let typeChar = params.prefix(1)
            let levelDigits = params.dropFirst(1).prefix(3)
            if let type = Int(typeChar), let level = Int(levelDigits) {
                if type == 0 { voipInputLevel = level }
                if type == 1 { voipOutputLevel = level }
            }
            return
        }

        // ##KN0 — KNS mode (0=off, 1=LAN, 2=internet)
        if core.hasPrefix("##KN0") {
            if let v = Int(core.dropFirst(5).prefix(1)) { knsMode = v }
            return
        }

        // ##KN1 — admin credentials change result
        //   failure: ##KN10 (exactly 6 chars); success: longer with new ID/PW echo
        if core.hasPrefix("##KN1") {
            knsAdminChangeResult = (core == "##KN10")
                ? "Failed: current credentials were incorrect."
                : "Admin credentials updated successfully."
            return
        }

        // ##KN2 — VoIP enabled (0/1)
        if core.hasPrefix("##KN2") {
            if let v = Int(core.dropFirst(5).prefix(1)) { knsVoipEnabled = v == 1 }
            return
        }

        // ##KN4 — VoIP jitter buffer (2-digit raw value: 04/10/25/40)
        if core.hasPrefix("##KN4") {
            if let v = Int(core.dropFirst(5).prefix(2)) { knsJitterBuffer = v }
            return
        }

        // ##KN5 — speaker mute; ##KN6 — access log; ##KN7 — user remote ops
        if core.hasPrefix("##KN5") {
            if let v = Int(core.dropFirst(5).prefix(1)) { knsSpeakerMute = v == 1 }
            return
        }
        if core.hasPrefix("##KN6") {
            if let v = Int(core.dropFirst(5).prefix(1)) { knsAccessLog = v == 1 }
            return
        }
        if core.hasPrefix("##KN7") {
            if let v = Int(core.dropFirst(5).prefix(1)) { knsUserRemoteOps = v == 1 }
            return
        }

        // ##KN8 — registered user count (3 digits)
        if core.hasPrefix("##KN8") {
            if let v = Int(core.dropFirst(5).prefix(3)) {
                knsUserCount = v
                if _knsLoadUsersAfterCount {
                    _knsLoadUsersAfterCount = false
                    for i in 0 ..< v { send(KenwoodKNS.readUser(number: i)) }
                }
            }
            return
        }

        // ##KNA — user record: P1(3,num) P2(2,IDlen) P3(2,PWlen) P4(3,descLen) ID PW desc R E
        if core.hasPrefix("##KNA") {
            let s = core.dropFirst(5)
            guard s.count >= 10,
                  let number  = Int(s.prefix(3)),
                  let idLen   = Int(s.dropFirst(3).prefix(2)),
                  let pwLen   = Int(s.dropFirst(5).prefix(2)),
                  let descLen = Int(s.dropFirst(7).prefix(3)) else { return }
            let body = s.dropFirst(10)
            guard body.count >= idLen + pwLen + descLen + 2 else { return }
            let userID   = String(body.prefix(idLen))
            let afterID  = body.dropFirst(idLen)
            let pw       = String(afterID.prefix(pwLen))
            let afterPW  = afterID.dropFirst(pwLen)
            let desc     = String(afterPW.prefix(descLen))
            let afterDesc = afterPW.dropFirst(descLen)
            let rxOnly   = afterDesc.prefix(1) == "1"
            let disabled = afterDesc.dropFirst(1).prefix(1) == "1"
            let user = KNSUser(id: number, userID: userID, password: pw,
                               description: desc, rxOnly: rxOnly, disabled: disabled)
            if let idx = knsUsers.firstIndex(where: { $0.id == number }) {
                knsUsers[idx] = user
            } else {
                knsUsers.append(user)
                knsUsers.sort { $0.id < $1.id }
            }
            return
        }

        // ##KNC — welcome message (P1 is always a space before the text)
        if core.hasPrefix("##KNC") {
            let after = core.dropFirst(5)
            knsWelcomeMessage = after.hasPrefix(" ") ? String(after.dropFirst()) : String(after)
            return
        }

        // ##KND — session timeout (2-digit raw value 00–13)
        if core.hasPrefix("##KND") {
            if let v = Int(core.dropFirst(5).prefix(2)) { knsSessionTimeout = v }
            return
        }

        // ##KNE — password change result (1 = OK, 0 = NG)
        if core.hasPrefix("##KNE") {
            knsPasswordChangeResult = core.dropFirst(5).prefix(1) == "1"
                ? "Password changed successfully."
                : "Password change failed."
            return
        }

        if core.hasPrefix("AG") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { afGain = v }
            return
        }

        if core.hasPrefix("RG") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { rfGain = v }
            return
        }

        if core.hasPrefix("NT") {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) {
                isNotchEnabled = (raw == 1)
            }
            return
        }

        if core.hasPrefix("SQ") {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { squelchLevel = v }
            return
        }

        if core.hasPrefix("SM"), core.count >= 3 {
            // Format: SMnnnn — 4-digit dot count (0000–0070).
            // No type selector in TS-890S reference: SM; reads S-meter (RX) or power (TX).
            // The first digit of the value is treated as typeIdx=0 → sMeterDots.
            let params = core.dropFirst(2)
            let typeStr = String(params.prefix(1))
            if let typeIdx = Int(typeStr) {
                let rest = params.dropFirst(1)
                let valueStr = rest.first == " " ? rest.dropFirst().prefix(while: { $0.isNumber }) : rest.prefix(while: { $0.isNumber })
                if let v = Int(valueStr) {
                    meterReadings[typeIdx] = Double(v)
                    if typeIdx == 0 {
                        sMeterDots = v
                    }
                }
            }
            return
        }

        if core.hasPrefix("EX"), core.count >= 9 {
            // Format: EX + P1(1) + P2(2) + P3(2) + P4(space) + P5(1+)
            // e.g. "EX00030 005" = P1=0, P2=00, P3=30, value=5
            // menuNumber key: P1=0 → P2*100+P3;  P1=1 → 10000+P3
            let afterEX = core.dropFirst(2)
            guard afterEX.count >= 6,
                  let p1 = Int(afterEX.prefix(1)),
                  let p2 = Int(afterEX.dropFirst(1).prefix(2)),
                  let p3 = Int(afterEX.dropFirst(3).prefix(2)) else { return }
            let menuNum = p1 == 0 ? p2 * 100 + p3 : 10000 + p3
            let afterParams = afterEX.dropFirst(5)  // starts at P4
            let rawValue = afterParams.first == " " ? afterParams.dropFirst() : Substring(afterParams)
            let value: Int
            if rawValue.hasPrefix("+") {
                value = Int(rawValue.dropFirst()) ?? 0
            } else if rawValue.hasPrefix("-") {
                value = -(Int(rawValue.dropFirst()) ?? 0)
            } else {
                value = Int(rawValue) ?? 0
            }
            // Store in general map (used by RadioMenuView)
            exMenuValues[menuNum] = value
            if menuDiscoveryRunning { menuDiscoveryResponseCount += 1 }
            return
        }

        // MARK: Built-in EQ band values (UT = TX, UR = RX)
        if core.hasPrefix("UT"), core.count == 38 {
            if let bands = KenwoodCAT.decodeBands(String(core.dropFirst(2))) {
                txEQBands = bands
            }
            return
        }

        if core.hasPrefix("UR"), core.count == 38 {
            if let bands = KenwoodCAT.decodeBands(String(core.dropFirst(2))) {
                rxEQBands = bands
            }
            return
        }

        // MARK: EQ preset responses (EQT0n / EQR0n)
        if core.hasPrefix("EQT0"), core.count == 5 {
            if let n = Int(core.dropFirst(4)), let p = KenwoodCAT.EQPreset(rawValue: n) {
                txEQPreset = p
            }
            return
        }

        if core.hasPrefix("EQR0"), core.count == 5 {
            if let n = Int(core.dropFirst(4)), let p = KenwoodCAT.EQPreset(rawValue: n) {
                rxEQPreset = p
            }
            return
        }

        // MARK: ARCP-890 parity frame parsers

        if core.hasPrefix("GC"), core.count >= 3 {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let mode = KenwoodCAT.AGCMode(rawValue: raw) {
                agcMode = mode
            }
            return
        }

        if core.hasPrefix("RA"), core.count >= 3 {
            // RA + P1 (attenuator level: 0=off, 1=6dB, 2=12dB, 3=18dB)
            let levelChar = core.dropFirst(2).prefix(1)
            if let raw = Int(levelChar), let level = KenwoodCAT.AttenuatorLevel(rawValue: raw) {
                attenuatorLevel = level
            }
            return
        }

        if core.hasPrefix("PA"), core.count >= 3 {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let level = KenwoodCAT.PreampLevel(rawValue: raw) {
                preampLevel = level
            }
            return
        }

        if core.hasPrefix("NB1"), core.count == 4 {
            // NB1P1; — NB1 is the primary noise blanker: P1=0 off, P1=1 on
            let p1 = core.dropFirst(3).prefix(1)
            if let raw = Int(p1) { noiseBlankerEnabled = (raw == 1) }
            return
        }

        if core.hasPrefix("BC"), core.count >= 3 {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let mode = KenwoodCAT.BeatCancelMode(rawValue: raw) {
                beatCancelMode = mode
            }
            return
        }

        if core.hasPrefix("MG"), core.count >= 5 {
            // MGP1P1P1; — 3-digit gain 000-100
            let gainStr = core.dropFirst(2).prefix(3)
            if let v = Int(gainStr) { micGain = v }
            return
        }

        if core.hasPrefix("VX"), core.count >= 3 {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1) { voxEnabled = (raw == 1) }
            return
        }

        if core.hasPrefix("ML"), core.count >= 5 {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { monitorLevel = v }
            return
        }

        if core.hasPrefix("PR0"), core.count >= 4 {
            // PR0 = Speech Processor ON/OFF: PR00;=off, PR01;=on
            let p1 = core.dropFirst(3).prefix(1)
            if let raw = Int(p1) { speechProcEnabled = (raw == 1) }
            return
        }

        if core.hasPrefix("KS"), core.count >= 5 {
            let digits = core.dropFirst(2).prefix { $0.isNumber }
            if let v = Int(digits) { cwKeySpeedWPM = v }
            return
        }

        if core.hasPrefix("BI"), core.count >= 3 {
            let p1 = core.dropFirst(2).prefix(1)
            if let raw = Int(p1), let mode = KenwoodCAT.CWBreakInMode(rawValue: raw) {
                cwBreakInMode = mode
            }
            return
        }

        // MARK: Batch 1 parsers — longer prefixes first

        // NB2 (must be before any bare NB check)
        if core.hasPrefix("NB2"), core.count >= 4 {
            if let raw = Int(core.dropFirst(3).prefix(1)) { noiseBlanker2Enabled = (raw == 1) }
            return
        }
        // NBT / NBD / NBW
        if core.hasPrefix("NBT"), core.count >= 4 {
            if let raw = Int(core.dropFirst(3).prefix(1)),
               let t = KenwoodCAT.NoiseBlanker2Type(rawValue: raw) { noiseBlanker2Type = t }
            return
        }
        if core.hasPrefix("NBD"), core.count >= 6 {
            if let v = Int(core.dropFirst(3).prefix(3)) { noiseBlanker2Depth = v }
            return
        }
        if core.hasPrefix("NBW"), core.count >= 6 {
            if let v = Int(core.dropFirst(3).prefix(3)) { noiseBlanker2Width = v }
            return
        }
        // NL1 / NL2
        if core.hasPrefix("NL1"), core.count >= 6 {
            if let v = Int(core.dropFirst(3).prefix(3)) { noiseBlanker1Level = v }
            return
        }
        if core.hasPrefix("NL2"), core.count >= 6 {
            if let v = Int(core.dropFirst(3).prefix(3)) { noiseBlanker2Level = v }
            return
        }
        // MO0 / MO1 / MO2
        if core.hasPrefix("MO0"), core.count >= 4 {
            if let raw = Int(core.dropFirst(3).prefix(1)) { txMonitorEnabled = (raw == 1) }
            return
        }
        if core.hasPrefix("MO1"), core.count >= 4 {
            if let raw = Int(core.dropFirst(3).prefix(1)) { rxMonitorEnabled = (raw == 1) }
            return
        }
        if core.hasPrefix("MO2"), core.count >= 4 {
            if let raw = Int(core.dropFirst(3).prefix(1)) { dspMonitorEnabled = (raw == 1) }
            return
        }
        // VG0 / VG1 (per input type)
        if core.hasPrefix("VG0"), core.count >= 7 {
            if let inputType = Int(core.dropFirst(3).prefix(1)), (0...3).contains(inputType),
               let v = Int(core.dropFirst(4).prefix(3)) { voxGain[inputType] = v }
            return
        }
        if core.hasPrefix("VG1"), core.count >= 7 {
            if let inputType = Int(core.dropFirst(3).prefix(1)), (0...3).contains(inputType),
               let v = Int(core.dropFirst(4).prefix(3)) { antiVOXLevel[inputType] = v }
            return
        }
        // RL1 / RL2
        if core.hasPrefix("RL1"), core.count >= 5 {
            if let v = Int(core.dropFirst(3).prefix(2)) { nrLevel = v }
            return
        }
        if core.hasPrefix("RL2"), core.count >= 5 {
            if let v = Int(core.dropFirst(3).prefix(2)) { nr2TimeConstant = v }
            return
        }
        // LK / MU / QS / PS / FV
        if core.hasPrefix("LK"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)) { isLocked = (raw == 1) }
            return
        }
        if core.hasPrefix("MU"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)) { isMuted = (raw == 1) }
            return
        }
        if core.hasPrefix("QS"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)) { isSpeakerMuted = (raw == 1) }
            return
        }
        if core.hasPrefix("PS"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)) { isPoweredOn = (raw == 1) }
            return
        }
        if core.hasPrefix("FV"), core.count > 2 {
            firmwareVersion = String(core.dropFirst(2))
            return
        }
        // CA / PT / SD
        if core.hasPrefix("CA"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)) { cwAutotuneActive = (raw == 1) }
            return
        }
        if core.hasPrefix("PT"), core.count >= 5 {
            if let raw = Int(core.dropFirst(2).prefix(3)) { cwPitchHz = 300 + raw * 5 }
            return
        }
        if core.hasPrefix("SD"), core.count >= 6 {
            if let v = Int(core.dropFirst(2).prefix(4)) { cwBreakInDelayMs = v }
            return
        }
        // BP / NW
        if core.hasPrefix("BP"), core.count >= 5 {
            if let v = Int(core.dropFirst(2).prefix(3)) { notchFrequency = v }
            return
        }
        if core.hasPrefix("NW"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)),
               let bw = KenwoodCAT.NotchBandwidth(rawValue: raw) { notchBandwidth = bw }
            return
        }
        // DV / VD
        if core.hasPrefix("DV"), core.count >= 3 {
            if let raw = Int(core.dropFirst(2).prefix(1)),
               let mode = KenwoodCAT.DataVOXMode(rawValue: raw) { dataVOXMode = mode }
            return
        }
        // MS - TX modulation source (answer: MS{P1}{P2}{P3} = 5 chars)
        if core.hasPrefix("MS"), core.count >= 5 {
            if let p1 = Int(core.dropFirst(2).prefix(1)),
               let p2 = Int(core.dropFirst(3).prefix(1)),
               let p3 = Int(core.dropFirst(4).prefix(1)) {
                if p1 == 0 { msPttFront = p2; msPttRear = p3 }
                else if p1 == 1 { msDataFront = p2; msDataRear = p3 }
            }
            return
        }
        if core.hasPrefix("VD"), core.count >= 6 {
            if let inputType = Int(core.dropFirst(2).prefix(1)), (0...3).contains(inputType),
               let v = Int(core.dropFirst(3).prefix(3)) { voxDelay[inputType] = v }
            return
        }

        if core == "RX" {
            isTransmitting = false
            isPTTDown = false
            isAppPTTActive = false  // clear app PTT if radio went RX for any reason
            return
        }

        if core.hasPrefix("TX") {
            isTransmitting = true
            isPTTDown = true
            return
        }
    }

    func setPTT(down: Bool) {
        setPTT(down: down, useMicAudio: true)
    }

    func setPTT(down: Bool, useMicAudio: Bool) {
        // Log synchronously: PTT debugging is high-value and these calls are infrequent.
        let hostLabel = currentHost.isEmpty ? "(empty)" : currentHost
        AppFileLogger.shared.logSync("PTT: request down=\(down) useMicAudio=\(useMicAudio) isAppPTTActive=\(isAppPTTActive) isPTTDown=\(isPTTDown) host=\(hostLabel) status=\(connectionStatus)")

        guard down != isAppPTTActive else {
            AppFileLogger.shared.logSync("PTT: ignored (already in requested state)")
            return
        }
        guard !currentHost.isEmpty else {
            AppFileLogger.shared.logSync("PTT: blocked (no host set)")
            announceError("No radio host set")
            return
        }

        if down {
            AppFileLogger.shared.logSync("UI: PTT down")
            // Only start VoIP stream if LAN audio is enabled — if the user wants hardware audio
            // only, skip ##VP1 so the radio doesn't stream UDP nobody is listening to.
            if useKnsLogin && autoStartLanAudio {
                connection.send("##VP1;")
                // If we haven't observed the input level yet, assume a sane default so TX isn't silent.
                if voipInputLevel == nil {
                    send(KenwoodCAT.setVoipInputLevel(50))
                    send(KenwoodCAT.getVoipInputLevel())
                }
            }
            if autoStartLanAudio, !isLanAudioRunning {
                startLanAudio(host: currentHost)
            }
            if freedvIsActive && freedvAudioPath == .lan {
                // FreeDV TX: push modem tones over KNS UDP.
                freedvLanTxPipeline?.start()
            } else if freedvIsActive && freedvAudioPath == .usb {
                // FreeDV USB: pipeline handles TX internally via AudioUnit — nothing extra needed.
                AppFileLogger.shared.logSync("FreeDV: USB TX started")
            } else if useMicAudio {
                micTxSource = .mic
                startMicCapture()
            } else {
                micTxSource = .generated
                stopMicCapture()
                // Ensure the paced sender exists so generated frames can be delivered.
                guard let receiver = lanReceiver else {
                    announceError("LAN audio receiver is not running")
                    return
                }
                micSendQueue.sync { micTxFrames.removeAll(keepingCapacity: true) }
                startMicTxTimerIfNeeded(receiver: receiver)
            }
            AppFileLogger.shared.logSync("PTT: sending TX0;")
            send(KenwoodCAT.pttDown())
            isAppPTTActive = true
            announceInfo("PTT down")
        } else {
            AppFileLogger.shared.logSync("UI: PTT up")
            if freedvIsActive && freedvAudioPath == .lan {
                freedvLanTxPipeline?.stop()
            } else {
                generatedTxState = nil
                generatedTxBuffer = []
                generatedTxBufferPos = 0
                stopMicCapture()
            }
            AppFileLogger.shared.logSync("PTT: sending RX;")
            send(KenwoodCAT.pttUp())
            isAppPTTActive = false
            announceInfo("PTT up")
        }
    }

    // Generated audio TX: used by digital modes like FT8. This does not use the selected microphone.
    // Current implementation sends a test tone; FT8 waveform generation will be added later.
    func transmitGeneratedTestTone(toneHz: Double, durationSeconds: Double, amplitude: Double = 0.2) {
        guard !isAppPTTActive else {
            AppFileLogger.shared.log("FT8: transmitGeneratedTestTone ignored (already TX)")
            return
        }
        guard durationSeconds > 0.1 else { return }
        guard toneHz > 10 else { return }

        // Ensure we're ready to send generated audio frames.
        setPTT(down: true, useMicAudio: false)

        // Timer sends 20ms frames (320 @ 16k). Convert duration to frames.
        let frames = max(1, Int((durationSeconds / 0.02).rounded()))
        generatedTxState = GeneratedTxState(framesRemaining: frames, phase: 0.0, frequencyHz: toneHz, amplitude: max(0.0, min(1.0, amplitude)))
        AppFileLogger.shared.log("FT8: generated test tone hz=\(toneHz) dur=\(String(format: "%.2f", durationSeconds))s frames=\(frames)")

        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
            guard let self else { return }
            if self.isPTTDown {
                self.setPTT(down: false, useMicAudio: false)
            }
        }
    }

    // Pre-computed audio TX for digital modes (FT8/FT4).
    // Accepts float PCM at 12 kHz, resamples to 16 kHz Int16, and queues for transmit.
    // PTT is automatically released when playback is complete.
    func transmitFT8Audio(samples12k: [Float], amplitude: Float = 0.15) {
        guard !isAppPTTActive else {
            AppFileLogger.shared.log("FT8: transmitFT8Audio ignored (already TX)")
            return
        }
        guard !samples12k.isEmpty else { return }

        // Resample and set up TX on a background thread to avoid blocking the main thread.
        let inCount = samples12k.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outCount = Int(Double(inCount) * 16_000.0 / 12_000.0 + 0.5)
            var buf16k   = [Int16](repeating: 0, count: outCount)
            for i in 0..<outCount {
                let srcIdx = Double(i) * 12_000.0 / 16_000.0
                let lo     = Int(srcIdx)
                let hi     = min(lo + 1, inCount - 1)
                let frac   = Float(srcIdx - Double(lo))
                let s      = (samples12k[lo] * (1.0 - frac) + samples12k[hi] * frac) * amplitude
                buf16k[i]  = Int16(max(-32767.0, min(32767.0, Double(s) * 32767.0)))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isAppPTTActive else { return }
                self.generatedTxBuffer    = buf16k
                self.generatedTxBufferPos = 0
                self.generatedTxState     = nil
                self.setPTT(down: true, useMicAudio: false)
                let dur = Double(inCount) / 12_000.0
                AppFileLogger.shared.log("FT8: transmitFT8Audio samples12k=\(inCount) dur=\(String(format: "%.2f", dur))s")
            }
        }
    }

    func setVoipOutputLevel(_ level: Int) {
        let clamped = max(0, min(level, 100))
        voipOutputLevel = clamped
        send(KenwoodCAT.setVoipOutputLevel(clamped))
        send(KenwoodCAT.getVoipOutputLevel())
    }

    func setVoipOutputLevelDebounced(_ level: Int) {
        let clamped = max(0, min(level, 100))
        voipOutputLevel = clamped
        debounceCAT(key: "voip_out", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setVoipOutputLevel(clamped))
            self.send(KenwoodCAT.getVoipOutputLevel())
        }
    }

    func setVoipInputLevel(_ level: Int) {
        let clamped = max(0, min(level, 100))
        voipInputLevel = clamped
        send(KenwoodCAT.setVoipInputLevel(clamped))
        send(KenwoodCAT.getVoipInputLevel())
    }

    func setVoipInputLevelDebounced(_ level: Int) {
        let clamped = max(0, min(level, 100))
        voipInputLevel = clamped
        debounceCAT(key: "voip_in", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setVoipInputLevel(clamped))
            self.send(KenwoodCAT.getVoipInputLevel())
        }
    }

    // MARK: - KNS Admin

    /// Query all readable KNS admin settings from the radio.
    /// Requires administrator login for most commands; safe to call as user (non-admin answers are ignored).
    func queryKNSAdminSettings() {
        send(KenwoodKNS.readKNSMode())
        send(KenwoodKNS.readVoIPEnabled())
        send(KenwoodKNS.readVoIPJitterBuffer())
        send(KenwoodKNS.readSpeakerMute())
        send(KenwoodKNS.readAccessLog())
        send(KenwoodKNS.readUserRemoteOps())
        send(KenwoodKNS.readUserCount())
        send(KenwoodKNS.readWelcomeMessage())
        send(KenwoodKNS.readSessionTimeout())
    }

    func setKNSMode(_ mode: KenwoodKNS.KNSMode) {
        knsMode = mode.rawValue
        send(KenwoodKNS.setKNSMode(mode))
        send(KenwoodKNS.readKNSMode())
    }

    func setKNSVoIPEnabled(_ on: Bool) {
        knsVoipEnabled = on
        send(KenwoodKNS.setVoIPEnabled(on))
        send(KenwoodKNS.readVoIPEnabled())
    }

    func setKNSJitterBuffer(_ buf: KenwoodKNS.JitterBuffer) {
        knsJitterBuffer = buf.rawValue
        send(KenwoodKNS.setVoIPJitterBuffer(buf))
        send(KenwoodKNS.readVoIPJitterBuffer())
    }

    func setKNSSpeakerMute(_ on: Bool) {
        knsSpeakerMute = on
        send(KenwoodKNS.setSpeakerMute(on))
        send(KenwoodKNS.readSpeakerMute())
    }

    func setKNSAccessLog(_ on: Bool) {
        knsAccessLog = on
        send(KenwoodKNS.setAccessLog(on))
        send(KenwoodKNS.readAccessLog())
    }

    func setKNSUserRemoteOps(_ on: Bool) {
        knsUserRemoteOps = on
        send(KenwoodKNS.setUserRemoteOps(on))
        send(KenwoodKNS.readUserRemoteOps())
    }

    func setKNSSessionTimeout(_ t: KenwoodKNS.SessionTimeout) {
        knsSessionTimeout = t.rawValue
        send(KenwoodKNS.setSessionTimeout(t))
        send(KenwoodKNS.readSessionTimeout())
    }

    func setKNSWelcomeMessage(_ msg: String) {
        knsWelcomeMessage = msg
        send(msg.isEmpty ? KenwoodKNS.clearWelcomeMessage() : KenwoodKNS.setWelcomeMessage(msg))
    }

    /// Clears the user list then queries the count; on ##KN8 response, fires ##KNA reads.
    func loadAllKNSUsers() {
        knsUsers = []
        _knsLoadUsersAfterCount = true
        send(KenwoodKNS.readUserCount())
    }

    func addKNSUser(userID: String, password: String, description: String,
                    rxOnly: Bool, disabled: Bool) {
        send(KenwoodKNS.addUser(userID: userID, password: password,
                                description: description, rxOnly: rxOnly, disabled: disabled))
        // Reload list after a brief settle — radio sends ##KN9 answer with new number.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.loadAllKNSUsers()
        }
    }

    func editKNSUser(number: Int, userID: String, password: String,
                     description: String, rxOnly: Bool, disabled: Bool) {
        send(KenwoodKNS.editUser(number: number, userID: userID, password: password,
                                 description: description, rxOnly: rxOnly, disabled: disabled))
        send(KenwoodKNS.readUser(number: number))
    }

    func deleteKNSUser(number: Int) {
        send(KenwoodKNS.deleteUser(number: number))
        knsUsers.removeAll { $0.id == number }
        send(KenwoodKNS.readUserCount())
    }

    func changeKNSAdminCredentials(currentID: String, currentPW: String,
                                   newID: String, newPW: String) {
        knsAdminChangeResult = ""
        send(KenwoodKNS.changeAdminCredentials(currentID: currentID, currentPW: currentPW,
                                               newID: newID, newPW: newPW))
    }

    func changeKNSPassword(_ newPassword: String) {
        knsPasswordChangeResult = ""
        send(KenwoodKNS.changePassword(newPassword))
    }

    func setRFGainDebounced(_ value: Int) {
        let clamped = max(0, min(value, 255))
        rfGain = clamped
        debounceCAT(key: "rf_gain", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setRFGain(clamped))
            // AI4 pushes RG confirmation automatically
        }
    }

    func setAFGainDebounced(_ value: Int) {
        let clamped = max(0, min(value, 255))
        afGain = clamped
        debounceCAT(key: "af_gain", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setAFGain(clamped))
            // AI4 pushes AG confirmation automatically
        }
    }

    func setSquelchLevelDebounced(_ value: Int) {
        let clamped = max(0, min(value, 255))
        squelchLevel = clamped
        debounceCAT(key: "squelch", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setSquelchLevel(clamped))
            // AI4 pushes SQ confirmation automatically
        }
    }

    func setReceiveFilterLowCutIDDebounced(_ id: Int) {
        let clamped = max(0, min(id, 35))
        rxFilterLowCutID = clamped
        debounceCAT(key: "rx_low_cut", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setReceiveFilterLowCutSettingID(clamped))
            self.send(KenwoodCAT.getReceiveFilterLowCutSettingID())
        }
    }

    func setReceiveFilterHighCutIDDebounced(_ id: Int) {
        let clamped = max(0, min(id, 27))
        rxFilterHighCutID = clamped
        debounceCAT(key: "rx_high_cut", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setReceiveFilterHighCutSettingID(clamped))
            self.send(KenwoodCAT.getReceiveFilterHighCutSettingID())
        }
    }

    func setReceiveFilterShiftHzDebounced(_ hz: Int) {
        let clamped = max(-9999, min(hz, 9999))
        rxFilterShiftHz = clamped
        debounceCAT(key: "rx_shift", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setReceiveFilterShiftHz(clamped))
            self.send(KenwoodCAT.getReceiveFilterShift())
        }
    }

    func setRitXitOffsetHzDebounced(_ hz: Int) {
        let clamped = max(-9999, min(hz, 9999))
        ritXitOffsetHz = clamped
        debounceCAT(key: "rit_xit_offset", delaySeconds: 0.15) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.ritXitSetOffsetHz(clamped))
            self.send(KenwoodCAT.ritXitGetOffset())
        }
    }

    // MARK: - ARCP-890 parity action methods

    func setAGCMode(_ mode: KenwoodCAT.AGCMode) {
        agcMode = mode
        send(KenwoodCAT.setAGC(mode))
        // AI4 pushes GT confirmation automatically
    }

    func cycleAGCMode() {
        setAGCMode((agcMode ?? .slow).next)
    }

    func setAttenuatorLevel(_ level: KenwoodCAT.AttenuatorLevel) {
        attenuatorLevel = level
        send(KenwoodCAT.setAttenuator(level))
        // AI4 pushes RA confirmation automatically
    }

    func cycleAttenuatorLevel() {
        setAttenuatorLevel((attenuatorLevel ?? .off).next)
    }

    func setPreampLevel(_ level: KenwoodCAT.PreampLevel) {
        preampLevel = level
        send(KenwoodCAT.setPreamp(level))
    }

    func cyclePreampLevel() {
        setPreampLevel((preampLevel ?? .off).next)
    }

    func setFilterSlot(_ slot: KenwoodCAT.FilterSlot) {
        filterSlot = slot
        send(KenwoodCAT.setFilterSlot(slot))
        // If this slot uses IF-Shift mode, restore the stored IS value for it.
        if filterSlotDisplayModes[slot.rawValue] == .ifShift {
            let hz = filterSlotIFShiftHz[slot.rawValue]
            rxFilterShiftHz = hz
            send(KenwoodCAT.setReceiveFilterShiftHz(hz))
        }
    }

    private var lastFilterSlotCycleDate: Date = .distantPast

    func cycleFilterSlot() {
        let now = Date()
        guard now.timeIntervalSince(lastFilterSlotCycleDate) >= 0.2 else { return }
        lastFilterSlotCycleDate = now
        setFilterSlot((filterSlot ?? .a).next)
    }

    func setNoiseBlankerEnabled(_ enabled: Bool) {
        noiseBlankerEnabled = enabled
        send(KenwoodCAT.setNoiseBlanker(enabled: enabled))
        // AI4 pushes NB confirmation automatically
    }

    func setBeatCancelMode(_ mode: KenwoodCAT.BeatCancelMode) {
        beatCancelMode = mode
        send(KenwoodCAT.setBeatCancel(mode))
    }

    func cycleBeatCancelMode() {
        setBeatCancelMode((beatCancelMode ?? .off).next)
    }

    func setMicGain(_ value: Int) {
        let clamped = max(0, min(value, 100))
        micGain = clamped
        send(KenwoodCAT.setMicGain(clamped))
        // AI4 pushes MG confirmation automatically
    }

    func setMicGainDebounced(_ value: Int) {
        let clamped = max(0, min(value, 100))
        micGain = clamped
        debounceCAT(key: "mic_gain", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setMicGain(clamped))
            // AI4 pushes MG confirmation automatically
        }
    }

    func setVOXEnabled(_ enabled: Bool) {
        voxEnabled = enabled
        send(KenwoodCAT.setVOX(enabled: enabled))
        // AI4 pushes VX confirmation automatically
    }

    func setMonitorLevel(_ level: Int) {
        let clamped = max(0, min(level, 100))
        monitorLevel = clamped
        send(KenwoodCAT.setMonitorLevel(clamped))
        // AI4 pushes MO confirmation automatically
    }

    func setMonitorLevelDebounced(_ level: Int) {
        let clamped = max(0, min(level, 100))
        monitorLevel = clamped
        debounceCAT(key: "monitor_level", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setMonitorLevel(clamped))
            // AI4 pushes MO confirmation automatically
        }
    }

    func setSpeechProcEnabled(_ enabled: Bool) {
        speechProcEnabled = enabled
        send(KenwoodCAT.setSpeechProc(enabled: enabled))
        // AI4 pushes PL confirmation automatically
    }

    func setCWKeySpeedWPM(_ wpm: Int) {
        let clamped = max(4, min(wpm, 100))
        cwKeySpeedWPM = clamped
        send(KenwoodCAT.setCWSpeed(clamped))
        // AI4 pushes KS confirmation automatically
    }

    func setCWKeySpeedWPMDebounced(_ wpm: Int) {
        let clamped = max(4, min(wpm, 100))
        cwKeySpeedWPM = clamped
        debounceCAT(key: "cw_speed", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setCWSpeed(clamped))
            // AI4 pushes KS confirmation automatically
        }
    }

    func setCWBreakInMode(_ mode: KenwoodCAT.CWBreakInMode) {
        cwBreakInMode = mode
        send(KenwoodCAT.setCWBreakIn(mode))
        // AI4 pushes BK confirmation automatically
    }

    func cycleCWBreakInMode() {
        setCWBreakInMode((cwBreakInMode ?? .off).next)
    }

    // MARK: - Batch 1 action methods

    // VFO swap / copy
    func swapVFOs() {
        send(KenwoodCAT.swapVFOs())
        // AI4 pushes FA/FB confirmations automatically
    }

    func copyVFOAtoB() {
        send(KenwoodCAT.copyVFOAtoB())
        // AI4 pushes FB confirmation automatically
    }

    // Lock / Mute
    func setLocked(_ on: Bool) {
        isLocked = on
        send(KenwoodCAT.setLock(on))
    }

    func setMuted(_ on: Bool) {
        isMuted = on
        send(KenwoodCAT.setMute(on))
    }

    func setSpeakerMuted(_ on: Bool) {
        isSpeakerMuted = on
        send(KenwoodCAT.setSpeakerMute(on))
    }

    // Monitor ON/OFF
    func setTXMonitorEnabled(_ on: Bool) {
        txMonitorEnabled = on
        send(KenwoodCAT.setTXMonitor(on))
    }

    func setRXMonitorEnabled(_ on: Bool) {
        rxMonitorEnabled = on
        send(KenwoodCAT.setRXMonitor(on))
    }

    func setDSPMonitorEnabled(_ on: Bool) {
        dspMonitorEnabled = on
        send(KenwoodCAT.setDSPMonitor(on))
    }

    // CW extended
    func setCWAutotuneActive(_ on: Bool) {
        cwAutotuneActive = on
        send(KenwoodCAT.setCWAutotune(on))
    }

    func setCWPitchHz(_ hz: Int) {
        let clamped = max(300, min(hz, 1100))
        cwPitchHz = clamped
        send(KenwoodCAT.setCWPitch(hz: clamped))
    }

    func setCWPitchHzDebounced(_ hz: Int) {
        let clamped = max(300, min(hz, 1100))
        cwPitchHz = clamped
        debounceCAT(key: "cw_pitch", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setCWPitch(hz: clamped))
        }
    }

    func setCWBreakInDelayMs(_ ms: Int) {
        let clamped = max(0, min(ms, 1000))
        cwBreakInDelayMs = clamped
        send(KenwoodCAT.setCWBreakInDelay(ms: clamped))
    }

    func setCWBreakInDelayMsDebounced(_ ms: Int) {
        let clamped = max(0, min(ms, 1000))
        cwBreakInDelayMs = clamped
        debounceCAT(key: "cw_breakin_delay", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setCWBreakInDelay(ms: clamped))
        }
    }

    // NB2 suite
    func setNoiseBlanker2Enabled(_ on: Bool) {
        noiseBlanker2Enabled = on
        send(KenwoodCAT.setNoiseBlanker2(on))
    }

    func setNoiseBlanker2Type(_ type: KenwoodCAT.NoiseBlanker2Type) {
        noiseBlanker2Type = type
        send(KenwoodCAT.setNoiseBlanker2Type(type))
    }

    func setNoiseBlanker1Level(_ level: Int) {
        let clamped = max(1, min(level, 20))
        noiseBlanker1Level = clamped
        send(KenwoodCAT.setNoiseBlanker1Level(clamped))
    }

    func setNoiseBlanker1LevelDebounced(_ level: Int) {
        let clamped = max(1, min(level, 20))
        noiseBlanker1Level = clamped
        debounceCAT(key: "nb1_level", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNoiseBlanker1Level(clamped))
        }
    }

    func setNoiseBlanker2Level(_ level: Int) {
        let clamped = max(1, min(level, 10))
        noiseBlanker2Level = clamped
        send(KenwoodCAT.setNoiseBlanker2Level(clamped))
    }

    func setNoiseBlanker2LevelDebounced(_ level: Int) {
        let clamped = max(1, min(level, 10))
        noiseBlanker2Level = clamped
        debounceCAT(key: "nb2_level", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNoiseBlanker2Level(clamped))
        }
    }

    func setNoiseBlanker2Depth(_ depth: Int) {
        let clamped = max(1, min(depth, 20))
        noiseBlanker2Depth = clamped
        send(KenwoodCAT.setNoiseBlanker2Depth(clamped))
    }

    func setNoiseBlanker2DepthDebounced(_ depth: Int) {
        let clamped = max(1, min(depth, 20))
        noiseBlanker2Depth = clamped
        debounceCAT(key: "nb2_depth", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNoiseBlanker2Depth(clamped))
        }
    }

    func setNoiseBlanker2Width(_ width: Int) {
        let clamped = max(1, min(width, 20))
        noiseBlanker2Width = clamped
        send(KenwoodCAT.setNoiseBlanker2Width(clamped))
    }

    func setNoiseBlanker2WidthDebounced(_ width: Int) {
        let clamped = max(1, min(width, 20))
        noiseBlanker2Width = clamped
        debounceCAT(key: "nb2_width", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNoiseBlanker2Width(clamped))
        }
    }

    // Notch extended
    func setNotchFrequency(_ value: Int) {
        let clamped = max(0, min(value, 255))
        notchFrequency = clamped
        send(KenwoodCAT.setNotchFrequency(clamped))
    }

    func setNotchFrequencyDebounced(_ value: Int) {
        let clamped = max(0, min(value, 255))
        notchFrequency = clamped
        debounceCAT(key: "notch_freq", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNotchFrequency(clamped))
        }
    }

    func setNotchBandwidth(_ bw: KenwoodCAT.NotchBandwidth) {
        notchBandwidth = bw
        send(KenwoodCAT.setNotchBandwidth(bw))
    }

    // NR level tuning
    func setNRLevel(_ level: Int) {
        let clamped = max(1, min(level, 10))
        nrLevel = clamped
        send(KenwoodCAT.setNRLevel(clamped))
    }

    func setNRLevelDebounced(_ level: Int) {
        let clamped = max(1, min(level, 10))
        nrLevel = clamped
        debounceCAT(key: "nr_level", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNRLevel(clamped))
        }
    }

    func setNR2TimeConstant(_ value: Int) {
        let clamped = max(0, min(value, 9))
        nr2TimeConstant = clamped
        send(KenwoodCAT.setNR2TimeConstant(clamped))
    }

    func setNR2TimeConstantDebounced(_ value: Int) {
        let clamped = max(0, min(value, 9))
        nr2TimeConstant = clamped
        debounceCAT(key: "nr2_tc", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setNR2TimeConstant(clamped))
        }
    }

    // DATA VOX
    func setDataVOXMode(_ mode: KenwoodCAT.DataVOXMode) {
        dataVOXMode = mode
        send(KenwoodCAT.setDataVOX(mode))
    }

    // TX Modulation Sources (MS)
    func setTxModulationSource(txMeans: Int, front: Int, rear: Int) {
        if txMeans == 0 { msPttFront = front; msPttRear = rear }
        else            { msDataFront = front; msDataRear = rear }
        send(KenwoodCAT.setTxAudioSource(txMeans: txMeans, front: front, rear: rear))
        send(KenwoodCAT.getTxAudioSource(txMeans: txMeans))
    }

    // VOX per-input parameters
    func setVOXDelay(inputType: Int, value: Int) {
        let clamped = max(0, min(value, 20))
        if (0...3).contains(inputType) { voxDelay[inputType] = clamped }
        send(KenwoodCAT.setVOXDelay(inputType: inputType, value: clamped))
    }

    func setVOXDelayDebounced(inputType: Int, value: Int) {
        let clamped = max(0, min(value, 20))
        if (0...3).contains(inputType) { voxDelay[inputType] = clamped }
        debounceCAT(key: "vox_delay_\(inputType)", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setVOXDelay(inputType: inputType, value: clamped))
        }
    }

    func setVOXGain(inputType: Int, gain: Int) {
        let clamped = max(0, min(gain, 20))
        if (0...3).contains(inputType) { voxGain[inputType] = clamped }
        send(KenwoodCAT.setVOXGain(inputType: inputType, gain: clamped))
    }

    func setVOXGainDebounced(inputType: Int, gain: Int) {
        let clamped = max(0, min(gain, 20))
        if (0...3).contains(inputType) { voxGain[inputType] = clamped }
        debounceCAT(key: "vox_gain_\(inputType)", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setVOXGain(inputType: inputType, gain: clamped))
        }
    }

    func setAntiVOXLevel(inputType: Int, level: Int) {
        let clamped = max(0, min(level, 20))
        if (0...3).contains(inputType) { antiVOXLevel[inputType] = clamped }
        send(KenwoodCAT.setAntiVOXLevel(inputType: inputType, level: clamped))
    }

    func setAntiVOXLevelDebounced(inputType: Int, level: Int) {
        let clamped = max(0, min(level, 20))
        if (0...3).contains(inputType) { antiVOXLevel[inputType] = clamped }
        debounceCAT(key: "antivox_\(inputType)", delaySeconds: 0.20) { [weak self] in
            guard let self else { return }
            self.send(KenwoodCAT.setAntiVOXLevel(inputType: inputType, level: clamped))
        }
    }

    private var lastCWKeyerSendDate: Date = .distantPast

    /// Send text via the radio's built-in CW keyer.
    /// Text is trimmed to 24 characters (radio buffer limit) and uppercased.
    /// Sends: KY {text}; — radio transmits as CW automatically.
    func sendCWKeyer(text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespaces).uppercased().prefix(24))
        guard !trimmed.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCWKeyerSendDate) >= 0.2 else { return }
        lastCWKeyerSendDate = now
        send("KY \(trimmed);")
    }

    /// Stop the CW keyer immediately.
    func stopCWKeyer() {
        send("KY0;")
    }

    /// Poll one or more meter types. Call from a periodic timer in the UI.
    func pollMeters(_ types: [KenwoodCAT.MeterType]) {
        for t in types where t.smIndex >= 0 {
            send(KenwoodCAT.getMeterValue(t))
        }
    }

    func setTransceiverNRMode(_ mode: KenwoodCAT.NoiseReductionMode) {
        transceiverNRMode = mode
        send(KenwoodCAT.setNoiseReduction(mode))
        send(KenwoodCAT.getNoiseReduction())
    }

    func cycleTransceiverNRMode() {
        let current = transceiverNRMode ?? .off
        let next: KenwoodCAT.NoiseReductionMode
        switch current {
        case .off: next = .nr1
        case .nr1: next = .nr2
        case .nr2: next = .off
        }
        setTransceiverNRMode(next)
    }

    /// Label shown on the unified front-panel NR button.
    var nrButtonLabel: String {
        switch nrButtonMode {
        case .hardware:
            switch transceiverNRMode ?? .off {
            case .off: return "NR: Off"
            case .nr1: return "NR1"
            case .nr2: return "NR2"
            }
        case .software:
            switch softwareNRState {
            case .off:     return "NR: Off"
            case .cascade: return "RNNoise+ANR"
            case .anr:     return "ANR"
            case .emnr:    return "EMNR"
            }
        }
    }

    /// Whether the unified front-panel NR button should be shown as active (lit).
    var nrButtonIsActive: Bool {
        switch nrButtonMode {
        case .hardware: return (transceiverNRMode ?? .off) != .off
        case .software: return softwareNRState != .off
        }
    }

    /// Single action for the unified front-panel NR button: cycles the appropriate path.
    func cycleNRFrontPanel() {
        switch nrButtonMode {
        case .hardware:
            cycleTransceiverNRMode()
        case .software:
            let next = softwareNRState.next
            softwareNRState = next
            setNoiseReduction(enabled: next != .off)
            switch next {
            case .cascade: setNoiseReductionBackend("RNNoise + ANR")
            case .anr:     setNoiseReductionBackend("WDSP ANR")
            case .emnr:    setNoiseReductionBackend("WDSP EMNR")
            case .off:     break
            }
            announceInfo("Software NR: \(next.rawValue)")
        }
    }

    func setNotchEnabled(_ enabled: Bool) {
        isNotchEnabled = enabled
        send(KenwoodCAT.setNotch(enabled: enabled))
        send(KenwoodCAT.getNotch())
    }

    func setDataMode(_ enabled: Bool) {
        dataModeEnabled = enabled
        send(KenwoodCAT.setDataMode(enabled: enabled))
        send(KenwoodCAT.getDataMode())
    }

    // MARK: - Antenna / APF / Scan actions

    func cycleAntennaPort() {
        let next = (antennaPort ?? 1) == 1 ? 2 : 1
        antennaPort = next
        // Change port only; use 9 (no-change) for rxAnt, driveOut, antennaOut.
        send(KenwoodCAT.setAntenna(port: next, rxAnt: 9, driveOut: 9, antennaOut: 9))
        send(KenwoodCAT.getAntenna())
    }

    func setAPFEnabled(_ on: Bool) {
        apfEnabled = on
        send(KenwoodCAT.setAPFEnabled(on))
    }

    func setAPFShift(_ value: Int) {
        let clamped = max(0, min(value, 80))
        apfShift = clamped
        send(KenwoodCAT.setAPFShift(clamped))
    }

    func setAPFBandwidth(_ bw: KenwoodCAT.APFBandwidth) {
        apfBandwidth = bw
        send(KenwoodCAT.setAPFBandwidth(bw))
    }

    func setAPFGain(_ gain: Int) {
        let clamped = max(0, min(gain, 6))
        apfGain = clamped
        send(KenwoodCAT.setAPFGain(clamped))
    }

    // MARK: - Band-change auto-mode switching (B-012)

    private static let _lsbBands: Set<String> = ["160m", "80m", "60m", "40m"]
    private static let _bandRanges: [(String, ClosedRange<Int>)] = [
        ("160m",  1_800_000...2_000_000), ("80m",   3_500_000...4_000_000),
        ("60m",   5_330_000...5_410_000), ("40m",   7_000_000...7_300_000),
        ("30m",  10_100_000...10_150_000), ("20m",  14_000_000...14_350_000),
        ("17m",  18_068_000...18_168_000), ("15m",  21_000_000...21_450_000),
        ("12m",  24_890_000...24_990_000), ("10m",  28_000_000...29_700_000),
        ("6m",   50_000_000...54_000_000),
    ]

    /// Called from the FA frame handler. Auto-switches LSB↔USB when crossing band boundaries.
    /// Only applies while in an SSB mode; CW/AM/FM/FSK are never touched.
    private func autoSwitchModeIfBandChanged(newHz: Int) {
        let newBand = Self._bandRanges.first { $0.1.contains(newHz) }?.0
        let prevBand = _lastBandLabel
        _lastBandLabel = newBand
        // Only switch when both bands are known and different.
        guard let newBand, let prevBand, newBand != prevBand else { return }
        // Only auto-switch in SSB modes; do not override CW, AM, FM, FSK, or DATA.
        guard let mode = operatingMode, mode == .lsb || mode == .usb else { return }
        let target: KenwoodCAT.OperatingMode = Self._lsbBands.contains(newBand) ? .lsb : .usb
        guard mode != target else { return }
        send(KenwoodCAT.setOperatingMode(target))
        send(KenwoodCAT.getOperatingMode())
    }

    // MARK: - EQ commands

    func queryAllEQ() {
        send(KenwoodCAT.getTXEQ())
        send(KenwoodCAT.getRXEQ())
        send(KenwoodCAT.getTXEQPreset())
        send(KenwoodCAT.getRXEQPreset())
    }

    func setTXEQBands(_ bands: [Int]) {
        txEQBands = bands
        send(KenwoodCAT.setTXEQ(bands))
    }

    func setRXEQBands(_ bands: [Int]) {
        rxEQBands = bands
        send(KenwoodCAT.setRXEQ(bands))
    }

    func loadTXEQPreset(_ preset: KenwoodCAT.EQPreset) {
        txEQPreset = preset
        send(KenwoodCAT.setTXEQPreset(preset))
        send(KenwoodCAT.getTXEQ())
    }

    func loadRXEQPreset(_ preset: KenwoodCAT.EQPreset) {
        rxEQPreset = preset
        send(KenwoodCAT.setRXEQPreset(preset))
        send(KenwoodCAT.getRXEQ())
    }

    // MARK: - General EX menu read/write

    func readMenuValue(_ menuNumber: Int) {
        send(KenwoodCAT.getMenuValue(menuNumber))
    }

    func writeMenuValue(_ menuNumber: Int, value: Int) {
        send(KenwoodCAT.setMenuValue(menuNumber, value: value))
        send(KenwoodCAT.getMenuValue(menuNumber))
    }

    // MARK: - EX menu discovery scan

    /// Queries all valid EX menu items using the correct 5-digit P1/P2/P3 format.
    /// Scans P1=0 (regular menu) categories 00–19, items 00–99, plus
    /// P1=1 (Advanced Menu) items 00–27.  Total ≈ 2028 queries at 20 ms each (~41 s).
    /// The radio silently ignores (returns ?;) queries for non-existent items;
    /// only valid responses are stored.
    func startMenuDiscovery() {
        guard !menuDiscoveryRunning else { return }
        // Defensively cancel any leftover timer from a previous partial run.
        _discoverySource?.cancel()
        _discoverySource = nil
        menuDiscoveryRunning = true
        menuDiscoveryProgress = 0
        menuDiscoverySnapshot = []
        menuDiscoveryResponseCount = 0
        menuDiscoverySentCount = 0
        exMenuValues.removeAll()

        // Silence AI4 push traffic during the scan so EX responses aren't
        // buried in FA/FB floods and the main thread stays responsive.
        send("AI0;")
        // Stop bandscope streaming (DD01 runs at ~30 Hz on LAN and isn't
        // silenced by AI0 — it would drown out EX responses).
        if connectionType == .lan { send("DD00;") }

        // Build the ordered list of queries using the correct 5-digit format.
        // Scan P2=00-29 to cover all known regular menu categories including
        // any undocumented items well beyond the confirmed P2=00-09 range.
        var queries: [String] = []
        for p2 in 0...29 {
            for p3 in 0...99 {
                queries.append(String(format: "EX0%02d%02d;", p2, p3))
            }
        }
        for p3 in 0...27 {
            queries.append(String(format: "EX100%02d;", p3))
        }

        var index = 0
        let total = queries.count
        menuDiscoveryTotalCount = total

        let source = DispatchSource.makeTimerSource(queue: .main)
        // Small delay before first query to let AI0/DD00 take effect.
        source.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(20))
        _discoverySource = source

        source.setEventHandler { [weak self] in
            guard let self, self.menuDiscoveryRunning else { source.cancel(); return }
            if index < total {
                self.send(queries[index])
                self.menuDiscoverySentCount = index + 1
                self.menuDiscoveryProgress = Double(index + 1) / Double(total)
                index += 1
            } else {
                source.cancel()
                self._discoverySource = nil
                // Allow 2 s for the last responses to arrive before snapshotting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.menuDiscoverySnapshot = self.exMenuValues
                        .sorted { $0.key < $1.key }
                        .map { (number: $0.key, value: $0.value) }
                    self.menuDiscoveryRunning = false
                    self.menuDiscoveryProgress = 1.0
                    // Restore AI4 push traffic and bandscope streaming.
                    self.send("AI4;")
                    if self.connectionType == .lan { self.send("DD01;") }
                }
            }
        }
        source.resume()
    }

    func stopMenuDiscovery() {
        _discoverySource?.cancel()
        _discoverySource = nil
        menuDiscoveryRunning = false
        // Restore AI4 push traffic and bandscope streaming.
        send("AI4;")
        if connectionType == .lan { send("DD01;") }
    }

    private func startMicCapture() {
        guard micCapture == nil else { return }
        guard let receiver = lanReceiver else {
            announceError("LAN audio receiver is not running")
            return
        }

        // Reset paced TX queue.
        micSendQueue.sync {
            micTxFrames.removeAll(keepingCapacity: true)
        }
        startMicTxTimerIfNeeded(receiver: receiver)

        let cap = KenwoodLanMicCapture()
        cap.onLog = { msg in
            AppLogger.info(msg)
            AppFileLogger.shared.log(msg)
        }
        cap.onError = { msg in
            AppLogger.error(msg)
            AppFileLogger.shared.log("LAN mic error: \(msg)")
        }
        cap.onFrame320 = { [weak self, weak receiver] ptr in
            guard let self else { return }
            // If we're in generated-TX mode, ignore microphone frames.
            guard self.micTxSource == .mic else { return }
            // Keep the audio callback lightweight: copy and send on a separate queue.
            var frame = [Int16](repeating: 0, count: 320)
            frame.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.assign(from: ptr, count: 320)
            }

            // Lightweight mic level indicator for debugging "keys but no modulation".
            // Log about once per second (50 frames @ 20ms).
            if self.micFrameLogCountdown <= 0 {
                var peak: Int16 = 0
                for s in frame {
                    let a = s == Int16.min ? Int16.max : abs(s)
                    if a > peak { peak = a }
                }
                AppFileLogger.shared.log("LAN mic: peak=\(peak)")
                self.micFrameLogCountdown = 50
            } else {
                self.micFrameLogCountdown -= 1
            }

            // Don't burst-send multiple frames back-to-back; queue and let the paced timer send at 20ms cadence.
            self.micSendQueue.async {
                self.micTxFrames.append(frame)
                // Bound latency: keep ~120ms max queued.
                if self.micTxFrames.count > 6 {
                    self.micTxFrames.removeFirst(self.micTxFrames.count - 6)
                }
            }
        }

        do {
            let inputID: AudioDeviceID? = {
                if !selectedLanMicInputUID.isEmpty {
                    return AudioDeviceManager.deviceID(forUID: selectedLanMicInputUID)
                }
                return AudioDeviceManager.defaultInputDeviceID()
            }()
            guard let inputID else {
                throw NSError(domain: "KenwoodLanMicCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "No microphone input device available"])
            }
            if let info = audioInputDevices.first(where: { $0.id == inputID }) {
                AppFileLogger.shared.log("LAN mic: input device \(info.name) uid=\(info.uid)")
            } else {
                AppFileLogger.shared.log("LAN mic: input deviceID=\(inputID)")
            }
            try cap.start(deviceID: inputID)
            micCapture = cap
        } catch {
            AppFileLogger.shared.log("LAN mic start failed: \(error.localizedDescription)")
            announceError("LAN mic failed: \(error.localizedDescription)")
            micCapture = nil
        }
    }

    private func stopMicCapture() {
        micCapture?.stop()
        micCapture = nil
        stopMicTxTimer()
        micSendQueue.async { [weak self] in
            self?.micTxFrames.removeAll(keepingCapacity: true)
        }
    }

    private func startMicTxTimerIfNeeded(receiver: KenwoodLanAudioReceiver) {
        guard micTxTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: micSendQueue)
        timer.schedule(deadline: .now() + 0.02, repeating: 0.02, leeway: .milliseconds(2))
        let silence = [Int16](repeating: 0, count: 320)
        timer.setEventHandler { [weak self, weak receiver] in
            guard let self, let receiver else { return }
            guard self.isPTTDown else { return }
            let frame: [Int16]
            switch self.micTxSource {
            case .mic:
                if !self.micTxFrames.isEmpty {
                    frame = self.micTxFrames.removeFirst()
                } else {
                    frame = silence
                }
            case .generated:
                // Pre-computed buffer (FT8/FT4 waveform) takes priority over real-time synthesis.
                if !self.generatedTxBuffer.isEmpty,
                   self.generatedTxBufferPos < self.generatedTxBuffer.count {
                    let start = self.generatedTxBufferPos
                    let end   = min(start + 320, self.generatedTxBuffer.count)
                    var out   = Array(self.generatedTxBuffer[start..<end])
                    if out.count < 320 {
                        out.append(contentsOf: [Int16](repeating: 0, count: 320 - out.count))
                    }
                    self.generatedTxBufferPos += 320
                    frame = out
                    // When the buffer is exhausted, release PTT after delivering the last frame.
                    if self.generatedTxBufferPos >= self.generatedTxBuffer.count {
                        self.generatedTxBuffer = []
                        self.generatedTxBufferPos = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.022) { [weak self] in
                            guard let self else { return }
                            if self.isPTTDown { self.setPTT(down: false, useMicAudio: false) }
                        }
                    }
                } else if var st = self.generatedTxState, st.framesRemaining > 0 {
                    var out = [Int16](repeating: 0, count: 320)
                    let sampleRate = 16_000.0
                    let step = 2.0 * Double.pi * st.frequencyHz / sampleRate
                    for i in 0..<320 {
                        let v = sin(st.phase) * st.amplitude
                        let s = Int16(max(-32767.0, min(32767.0, v * 32767.0)))
                        out[i] = s
                        st.phase += step
                        if st.phase > 2.0 * Double.pi { st.phase -= 2.0 * Double.pi }
                    }
                    st.framesRemaining -= 1
                    self.generatedTxState = st
                    frame = out
                } else {
                    frame = silence
                }
            }
            frame.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                receiver.sendMicFramePCM16(base, count: 320)
            }
        }
        micTxTimer = timer
        timer.resume()
    }

    private func stopMicTxTimer() {
        micTxTimer?.cancel()
        micTxTimer = nil
    }

    private func shouldPublishLastRXFrame(_ frame: String) -> Bool {
        let cleaned = frame.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let core = cleaned.hasSuffix(";") ? String(cleaned.dropLast()) : cleaned
        if core.hasPrefix("SM") {
            let now = Date()
            if now.timeIntervalSince(lastRXFrameSMAt) < 0.5 { return false }
            lastRXFrameSMAt = now
            return true
        }
        return true
    }

    private func loadPersistedKnsSettings() {
        if let useLogin = KNSSettings.loadUseLogin() {
            useKnsLogin = useLogin
        }
        if let t = KNSSettings.loadAccountTypeRaw() {
            knsAccountType = t
        }
        cwGreetingEnabled = UserDefaults.standard.bool(forKey: "CWGreetingEnabled")
        // Pre-fill credentials for the last host (ContentView also uses this for its initial Host field).
        if let host = KNSSettings.loadLastHost() {
            loadSavedCredentials(host: host)
        }
    }

    private func persistKnsSettings(host: String, port: Int, accountType: KenwoodKNS.AccountType) {
        KNSSettings.saveLastConnection(host: host, port: port)
        KNSSettings.saveUseLogin(useKnsLogin)
        KNSSettings.saveAccountTypeRaw(accountType.rawValue)

        // Save credentials for this host/account type. ID is not secret; password goes in Keychain.
        let username = adminId
        let password = adminPassword
        let cacheKey = "\(accountType.rawValue)|\(host)"
        if let cached = knsCredentialCache[cacheKey],
           cached.username == username,
           cached.password == password {
            // Avoid unnecessary keychain updates, which can trigger repeated macOS keychain prompts.
            return
        }
        if !username.isEmpty {
            KNSSettings.saveUsername(username, host: host, accountTypeRaw: accountType.rawValue)
            if !password.isEmpty {
                KNSSettings.savePassword(password, host: host, accountTypeRaw: accountType.rawValue, username: username)
            }
        }
        knsCredentialCache[cacheKey] = (username, password)
    }

    private func announceNoiseReductionChange(enabled: Bool) {
        #if canImport(AppKit)
        let message: String
        if !noiseProcessor.isAvailable {
            message = "Noise reduction unavailable"
        } else {
            message = enabled ? "Noise reduction enabled" : "Noise reduction disabled"
        }
        DispatchQueue.main.async {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: message,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
                ]
            )
        }
        #endif
    }

    private func announceConnectionStatus(_ status: ConnectionStatus) {
        #if canImport(AppKit)
        let message: String
        switch status {
        case .connected: message = "Radio connected"
        case .connecting: message = "Radio connecting"
        case .authenticating: message = "Radio authenticating"
        case .disconnected: message = "Radio disconnected"
        }
        DispatchQueue.main.async {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: message,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
                ]
            )
        }
        #endif
    }

    private func announceError(_ message: String) {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: "Error: \(message)",
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
                ]
            )
        }
        #endif
    }

    private func announceInfo(_ message: String) {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: message,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
                ]
            )
        }
        #endif
    }
}
