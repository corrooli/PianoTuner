import Foundation

// MARK: - Piano type

enum PianoType: String, CaseIterable, Identifiable, Codable {
    case upright
    case grand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upright: "Upright"
        case .grand: "Grand"
        }
    }

    /// Highest key (1...88) that has a single string by default.
    var defaultSingleThrough: Int { self == .upright ? 8 : 10 }
    /// Highest key (1...88) that has two strings by default.
    var defaultDoubleThrough: Int { self == .upright ? 30 : 28 }

    /// Stretch at the very top of the keyboard, in cents. Shorter upright strings
    /// are stiffer, so they need more stretch than a grand.
    var trebleStretch: Double { self == .upright ? 30 : 20 }
    /// Stretch at the very bottom of the keyboard, in cents (applied as flat).
    var bassStretch: Double { self == .upright ? 16 : 10 }

    var muteTool: String { self == .upright ? "rubber wedges" : "a felt strip" }
}

// MARK: - Stretch

enum StretchAmount: String, CaseIterable, Identifiable, Codable {
    case off, gentle, standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .gentle: "Gentle"
        case .standard: "Full"
        }
    }

    var factor: Double {
        switch self {
        case .off: 0
        case .gentle: 0.6
        case .standard: 1
        }
    }
}

// MARK: - Tuning order

enum TuningOrder: String, CaseIterable, Identifiable, Codable {
    case temperamentFirst
    case lowToHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperamentFirst: "Middle out"
        case .lowToHigh: "Low to high"
        }
    }

    var detail: String {
        switch self {
        case .temperamentFirst: "F3 to F4 first, then up to C8, then down to A0"
        case .lowToHigh: "Every key from A0 to C8"
        }
    }

    var sequence: [Int] {
        switch self {
        case .temperamentFirst: Array(33...45) + Array(46...88) + Array((1...32).reversed())
        case .lowToHigh: Array(1...88)
        }
    }
}

// MARK: - Keys

struct PianoKey: Identifiable, Hashable {
    /// 1 = A0, 49 = A4, 88 = C8
    let number: Int

    var id: Int { number }
    var midi: Int { number + 20 }
    var pitchClass: Int { midi % 12 }
    var octave: Int { midi / 12 - 1 }
    var isBlack: Bool { [1, 3, 6, 8, 10].contains(pitchClass) }

    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    var letter: String { Self.sharpNames[pitchClass] }
    var name: String { "\(letter)\(octave)" }
    var flatName: String? { isBlack ? "\(Self.flatNames[pitchClass])\(octave)" : nil }

    static let all: [PianoKey] = (1...88).map(PianoKey.init)
    static let whites: [PianoKey] = all.filter { !$0.isBlack }
    static let blacks: [PianoKey] = all.filter { $0.isBlack }

    /// Number of white keys strictly below this key.
    static let whitesBelow: [Int: Int] = {
        var map: [Int: Int] = [:]
        var count = 0
        for key in all {
            map[key.number] = count
            if !key.isBlack { count += 1 }
        }
        return map
    }()

    static func equalTempered(_ key: Int, reference: Double) -> Double {
        reference * pow(2, Double(key - 49) / 12)
    }
}

// MARK: - Tuning math

enum Tuning {
    /// Railsback style stretch offset in cents for a key.
    static func stretchCents(key: Int, type: PianoType, amount: StretchAmount) -> Double {
        let f = amount.factor
        guard f > 0 else { return 0 }
        if key > 49 {
            let x = Double(key - 49) / 39
            return f * type.trebleStretch * pow(x, 2.4)
        } else if key < 49 {
            let x = Double(49 - key) / 48
            return -f * type.bassStretch * pow(x, 2.2)
        }
        return 0
    }

    /// Which partial the analyzer listens to. Laptop microphones barely hear
    /// the fundamental of low bass strings, so we follow a higher partial there,
    /// much like an aural tuner compares octaves.
    static func partial(for key: Int) -> Int {
        switch key {
        case ...12: 4
        case ...24: 3
        case ...36: 2
        default: 1
        }
    }

    static func cents(_ frequency: Double, relativeTo target: Double) -> Double {
        1200 * log2(frequency / target)
    }
}

// MARK: - Strings per key

struct StringLayout: Codable, Equatable {
    var singleThrough: Int
    var doubleThrough: Int

    init(singleThrough: Int, doubleThrough: Int) {
        self.singleThrough = singleThrough
        self.doubleThrough = doubleThrough
    }

    init(for type: PianoType) {
        self.init(singleThrough: type.defaultSingleThrough, doubleThrough: type.defaultDoubleThrough)
    }

    func count(for key: Int) -> Int {
        if key <= singleThrough { return 1 }
        if key <= doubleThrough { return 2 }
        return 3
    }

    var totalStrings: Int { (1...88).reduce(0) { $0 + count(for: $1) } }

    /// Names in tuning order. For a three string unison the center goes first.
    static func names(count: Int) -> [String] {
        switch count {
        case 1: ["Single"]
        case 2: ["Left", "Right"]
        default: ["Center", "Left", "Right"]
        }
    }

    /// Tuning order indices laid out physically from left to right.
    static func physicalOrder(count: Int) -> [Int] {
        switch count {
        case 1: [0]
        case 2: [0, 1]
        default: [1, 0, 2]
        }
    }
}

// MARK: - Guidance

struct Instruction {
    let title: String
    let detail: String
}

enum Guidance {
    static func instruction(stringCount: Int, index: Int, type: PianoType) -> Instruction {
        let tool = type.muteTool
        switch (stringCount, index) {
        case (1, _):
            return Instruction(
                title: "Single string",
                detail: "Nothing to mute here. Strike the key firmly, then turn the pin in tiny moves until the needle rests on zero."
            )
        case (2, 0):
            return Instruction(
                title: "Mute the right string",
                detail: "Use \(tool) so only the left string sounds. Bring it to zero."
            )
        case (2, _):
            return Instruction(
                title: "Unison: right string",
                detail: "Pull the mute. Turn the right pin until the beating slows to nothing and the needle settles on zero."
            )
        case (_, 0):
            return Instruction(
                title: "Mute left and right",
                detail: "Use \(tool) so only the center string sounds. Bring it to zero. This string is the anchor for the other two."
            )
        case (_, 1):
            return Instruction(
                title: "Unison: left string",
                detail: "Free the left string, keep the right one muted. Turn the left pin until the beats vanish and the needle sits still."
            )
        default:
            return Instruction(
                title: "Unison: right string",
                detail: "Remove the last mute. Turn the right pin until all three strings sing as one clean note."
            )
        }
    }
}
