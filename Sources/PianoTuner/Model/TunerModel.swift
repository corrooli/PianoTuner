import AppKit
import AVFoundation
import Foundation
import Observation

enum DisplayMode: String, CaseIterable, Identifiable, Codable {
    case analog, digital, strobe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analog: "Analog"
        case .digital: "Digital"
        case .strobe: "Strobe"
        }
    }

    var symbol: String {
        switch self {
        case .analog: "gauge.with.needle"
        case .digital: "textformat.123"
        case .strobe: "line.3.horizontal"
        }
    }
}

enum MicPermission {
    case unknown, granted, denied
}

private struct AnalysisResult {
    let token: Int
    let expected: Double
    let levelDb: Double
    var partial: PartialMeasurement?
    var detectedKey: Int?
}

@Observable
@MainActor
final class TunerModel {
    // MARK: Settings

    var pianoType: PianoType = .upright {
        didSet { save(); targetChanged(); clampString() }
    }
    var displayMode: DisplayMode = .analog { didSet { save() } }
    var reference: Double = 440 { didSet { save(); targetChanged() } }
    var stretch: StretchAmount = .standard { didSet { save(); targetChanged() } }
    var order: TuningOrder = .temperamentFirst { didSet { save() } }
    var autoAdvance = true { didSet { save() } }
    var tolerance: Double = 1.0 { didSet { save() } }
    var followPlayedKey = false { didSet { save() } }
    var chime = true { didSet { save() } }
    var layouts: [PianoType: StringLayout] = [
        .upright: StringLayout(for: .upright),
        .grand: StringLayout(for: .grand),
    ] { didSet { save(); clampString() } }
    var completed: [PianoType: Set<String>] = [.upright: [], .grand: []] { didSet { save() } }
    var selectedDeviceUID: String? {
        didSet { save(); if oldValue != selectedDeviceUID { restartAudio() } }
    }

    // MARK: Selection

    private(set) var selectedKey: Int = 49
    private(set) var selectedString: Int = 0

    // MARK: Live reading

    private(set) var cents: Double?
    private(set) var heardFrequency: Double?
    private(set) var signalDb: Double = -120
    private(set) var confidence: Double = 0
    private(set) var holdProgress: Double = 0
    private(set) var completionPulse = 0
    private(set) var devices: [AudioDevice] = []
    private(set) var permission: MicPermission = .unknown
    private(set) var audioError: String?
    private(set) var isListening = false

    let demo: Bool

    // MARK: Internals

    @ObservationIgnored private let audio = AudioInput()
    @ObservationIgnored private let analyzer = PitchAnalyzer()
    @ObservationIgnored private let queue = DispatchQueue(label: "PianoTuner.analysis", qos: .userInteractive)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var recent: [Double] = []
    @ObservationIgnored private var lastValid = Date.distantPast
    @ObservationIgnored private var lastApply = Date()
    @ObservationIgnored private var holdSeconds = 0.0
    @ObservationIgnored private var followCandidate: (key: Int, count: Int)?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observingDevices = false

    static let holdDuration = 1.4

    init(demo: Bool = false) {
        self.demo = demo
        if !demo { load() }
    }

    // MARK: Derived values

    var layout: StringLayout {
        get { layouts[pianoType] ?? StringLayout(for: pianoType) }
        set { layouts[pianoType] = newValue }
    }

    var key: PianoKey { PianoKey(number: selectedKey) }
    var stringCount: Int { layout.count(for: selectedKey) }
    var stringNames: [String] { StringLayout.names(count: stringCount) }
    var partial: Int { Tuning.partial(for: selectedKey) }

    var stretchOffset: Double {
        Tuning.stretchCents(key: selectedKey, type: pianoType, amount: stretch)
    }

    /// Target fundamental including stretch.
    var targetFrequency: Double {
        PianoKey.equalTempered(selectedKey, reference: reference) * pow(2, stretchOffset / 1200)
    }

    var expectedPartialFrequency: Double { targetFrequency * Double(partial) }

    var instruction: Instruction {
        Guidance.instruction(stringCount: stringCount, index: selectedString, type: pianoType)
    }

    var isInTune: Bool {
        guard let cents else { return false }
        return abs(cents) <= tolerance
    }

    var totalStrings: Int { layout.totalStrings }
    var doneStrings: Int { completed[pianoType]?.count ?? 0 }
    var progress: Double { totalStrings > 0 ? Double(doneStrings) / Double(totalStrings) : 0 }

    func isDone(key: Int, string: Int) -> Bool {
        completed[pianoType]?.contains(Self.id(key, string)) ?? false
    }

    func doneCount(for key: Int) -> Int {
        (0..<layout.count(for: key)).filter { isDone(key: key, string: $0) }.count
    }

    var currentIsDone: Bool { isDone(key: selectedKey, string: selectedString) }

    private static func id(_ key: Int, _ string: Int) -> String { "\(key)-\(string)" }

    // MARK: Actions

    func select(key: Int, string: Int = 0) {
        let k = max(1, min(88, key))
        selectedKey = k
        selectedString = max(0, min(layout.count(for: k) - 1, string))
        targetChanged()
    }

    func select(string: Int) {
        selectedString = max(0, min(stringCount - 1, string))
        targetChanged()
    }

    func stepKey(_ delta: Int) { select(key: selectedKey + delta) }

    func stepString(_ delta: Int) {
        let next = selectedString + delta
        if next >= stringCount {
            stepKey(1)
        } else if next < 0 {
            let k = max(1, selectedKey - 1)
            select(key: k, string: layout.count(for: k) - 1)
        } else {
            select(string: next)
        }
    }

    /// Next string of this key, or the first string of the next key in the chosen order.
    func advance() {
        if selectedString + 1 < stringCount {
            select(string: selectedString + 1)
            return
        }
        let seq = order.sequence
        if let i = seq.firstIndex(of: selectedKey), i + 1 < seq.count {
            select(key: seq[i + 1])
        }
    }

    func retreat() {
        if selectedString > 0 {
            select(string: selectedString - 1)
            return
        }
        let seq = order.sequence
        if let i = seq.firstIndex(of: selectedKey), i > 0 {
            let k = seq[i - 1]
            select(key: k, string: layout.count(for: k) - 1)
        }
    }

    func toggleDone() {
        let id = Self.id(selectedKey, selectedString)
        var set = completed[pianoType] ?? []
        if set.contains(id) { set.remove(id) } else { set.insert(id); completionPulse += 1 }
        completed[pianoType] = set
    }

    func resetSession() {
        completed[pianoType] = []
        select(key: order.sequence.first ?? 49)
    }

    func setSingleThrough(_ value: Int) {
        var l = layout
        l.singleThrough = max(0, min(value, l.doubleThrough))
        layout = l
    }

    func setDoubleThrough(_ value: Int) {
        var l = layout
        l.doubleThrough = max(l.singleThrough, min(value, 88))
        layout = l
    }

    func resetLayout() { layout = StringLayout(for: pianoType) }

    // MARK: Audio lifecycle

    func start() {
        guard !demo, timer == nil else { return }
        refreshDevices()
        if !observingDevices {
            observingDevices = true
            AudioDevices.observeChanges { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshDevices()
                    if self.selectedDeviceUID == nil { self.restartAudio() }
                }
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permission = .granted
            startAudio()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.startAudio() }
                }
            }
        default:
            permission = .denied
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    var selectedDeviceName: String {
        if let uid = selectedDeviceUID, let d = devices.first(where: { $0.uid == uid }) { return d.name }
        if let id = AudioDevices.defaultInputID(), let d = devices.first(where: { $0.id == id }) { return d.name }
        return "System default"
    }

    private func refreshDevices() {
        devices = AudioDevices.inputDevices()
    }

    private func startAudio() {
        guard permission == .granted else { return }
        let id = selectedDeviceUID.flatMap { uid in devices.first(where: { $0.uid == uid })?.id }
        do {
            try audio.start(deviceID: id)
            audioError = nil
            isListening = true
        } catch {
            audioError = error.localizedDescription
            isListening = false
        }
    }

    private func restartAudio() {
        guard !demo, permission == .granted, !loading else { return }
        audio.stop()
        isListening = false
        startAudio()
    }

    // MARK: Analysis loop

    private func tick() {
        guard !busy, audio.isRunning else { return }
        busy = true
        let token = self.token
        let expected = expectedPartialFrequency
        let follow = followPlayedKey
        let ref = reference
        let audio = self.audio
        let analyzer = self.analyzer

        queue.async {
            let sr = audio.sampleRate
            let need = max(
                PitchAnalyzer.samplesNeeded(for: expected, sampleRate: sr),
                follow ? PitchAnalyzer.detectionLength(sampleRate: sr) : 0
            )
            var result = AnalysisResult(token: token, expected: expected, levelDb: audio.levelDb)
            if let samples = audio.latest(count: need) {
                result.partial = analyzer.measure(samples: samples, sampleRate: sr, expected: expected)
                if follow {
                    result.detectedKey = analyzer.detectKey(samples: samples, sampleRate: sr, reference: ref)
                }
            }
            Task { @MainActor [weak self] in
                self?.busy = false
                self?.apply(result)
            }
        }
    }

    private func apply(_ r: AnalysisResult) {
        let now = Date()
        let dt = min(0.2, now.timeIntervalSince(lastApply))
        lastApply = now
        signalDb = r.levelDb > signalDb ? r.levelDb : signalDb * 0.7 + r.levelDb * 0.3

        guard r.token == token else { return }

        let audible = r.levelDb > -64
        var valid = false
        if let p = r.partial, audible, p.snrDb > 14 {
            valid = true
            let c = Tuning.cents(p.frequency, relativeTo: r.expected)
            if let m = Self.median(recent), abs(c - m) > 25 { recent.removeAll() }
            recent.append(c)
            if recent.count > 5 { recent.removeFirst() }
            let smoothed = Self.median(recent) ?? c
            cents = smoothed
            heardFrequency = p.frequency / Double(partial)
            confidence = min(1, max(0, (p.snrDb - 14) / 22))
            lastValid = now

            if abs(smoothed) <= tolerance && recent.count >= 3 {
                holdSeconds += dt
            } else {
                holdSeconds = max(0, holdSeconds - dt * 2)
            }
        } else if now.timeIntervalSince(lastValid) > 1.6 {
            cents = nil
            heardFrequency = nil
            confidence = 0
            recent.removeAll()
            holdSeconds = 0
        }

        holdProgress = min(1, holdSeconds / Self.holdDuration)
        if holdSeconds >= Self.holdDuration {
            holdSeconds = 0
            holdProgress = 0
            completeCurrentString()
        }

        if followPlayedKey, let k = r.detectedKey, audible, !valid || abs(cents ?? 0) > 60 {
            if followCandidate?.key == k {
                followCandidate?.count += 1
            } else {
                followCandidate = (k, 1)
            }
            if let c = followCandidate, c.count >= 4, c.key != selectedKey {
                followCandidate = nil
                select(key: c.key)
            }
        } else if valid {
            followCandidate = nil
        }
    }

    private func completeCurrentString() {
        let id = Self.id(selectedKey, selectedString)
        var set = completed[pianoType] ?? []
        let wasDone = set.contains(id)
        set.insert(id)
        completed[pianoType] = set
        completionPulse += 1
        if chime && !wasDone {
            let sound = NSSound(named: NSSound.Name("Glass"))
            sound?.volume = 0.35
            sound?.play()
        }
        guard autoAdvance else { return }
        let expectedToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.token == expectedToken else { return }
                self.advance()
            }
        }
    }

    private func targetChanged() {
        token += 1
        recent.removeAll()
        cents = nil
        heardFrequency = nil
        confidence = 0
        holdSeconds = 0
        holdProgress = 0
        lastValid = .distantPast
        followCandidate = nil
        if !loading { saveSelection() }
    }

    private func clampString() {
        if selectedString >= stringCount { selectedString = stringCount - 1 }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    // MARK: Persistence

    private struct Stored: Codable {
        var pianoType: PianoType
        var displayMode: DisplayMode
        var reference: Double
        var stretch: StretchAmount
        var order: TuningOrder
        var autoAdvance: Bool
        var tolerance: Double
        var followPlayedKey: Bool
        var chime: Bool
        var layouts: [String: StringLayout]
        var completed: [String: [String]]
        var deviceUID: String?
    }

    private func save() {
        guard !loading, !demo else { return }
        let stored = Stored(
            pianoType: pianoType,
            displayMode: displayMode,
            reference: reference,
            stretch: stretch,
            order: order,
            autoAdvance: autoAdvance,
            tolerance: tolerance,
            followPlayedKey: followPlayedKey,
            chime: chime,
            layouts: Dictionary(uniqueKeysWithValues: layouts.map { ($0.key.rawValue, $0.value) }),
            completed: Dictionary(uniqueKeysWithValues: completed.map { ($0.key.rawValue, Array($0.value)) }),
            deviceUID: selectedDeviceUID
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: "settings.v1")
        }
    }

    private func saveSelection() {
        guard !demo else { return }
        defaults.set(selectedKey, forKey: "selection.key")
        defaults.set(selectedString, forKey: "selection.string")
    }

    private func load() {
        loading = true
        defer { loading = false }
        if let data = defaults.data(forKey: "settings.v1"),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            pianoType = s.pianoType
            displayMode = s.displayMode
            reference = s.reference
            stretch = s.stretch
            order = s.order
            autoAdvance = s.autoAdvance
            tolerance = s.tolerance
            followPlayedKey = s.followPlayedKey
            chime = s.chime
            for (k, v) in s.layouts { if let t = PianoType(rawValue: k) { layouts[t] = v } }
            for (k, v) in s.completed { if let t = PianoType(rawValue: k) { completed[t] = Set(v) } }
            selectedDeviceUID = s.deviceUID
        }
        if defaults.object(forKey: "selection.key") != nil {
            let k = defaults.integer(forKey: "selection.key")
            let s = defaults.integer(forKey: "selection.string")
            select(key: k == 0 ? 49 : k, string: s)
        }
    }

    // MARK: Demo state for screenshots

    func applyDemo(key: Int, string: Int, cents: Double?, hold: Double, done: [Int]) {
        select(key: key, string: string)
        var set = Set<String>()
        for k in done {
            for s in 0..<layout.count(for: k) { set.insert(Self.id(k, s)) }
        }
        completed[pianoType] = set
        self.cents = cents
        if let cents {
            heardFrequency = targetFrequency * pow(2, cents / 1200)
            confidence = 0.85
            signalDb = -26
        }
        holdProgress = hold
        isListening = true
        permission = .granted
        devices = [AudioDevice(id: 1, uid: "demo", name: "MacBook Pro Microphone")]
        selectedDeviceUID = "demo"
    }
}
