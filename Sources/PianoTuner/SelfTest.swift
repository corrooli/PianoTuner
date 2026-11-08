import Foundation

/// Synthetic accuracy check for the analyzer: `PianoTuner --selftest`.
enum SelfTest {
    static func run() -> Bool {
        let analyzer = PitchAnalyzer()
        let sr = 48_000.0
        var rng = SystemRandomNumberGenerator()
        var worst = 0.0
        var failures = 0
        let keys = [1, 6, 13, 20, 28, 33, 40, 49, 56, 64, 72, 80, 88]
        let offsets = [-23.0, -4.2, -0.7, 0.0, 0.4, 3.3, 17.5]

        print("key   offset   measured   error")
        for key in keys {
            for offset in offsets {
                let f0 = PianoKey.equalTempered(key, reference: 440) * pow(2, offset / 1200)
                let partial = Tuning.partial(for: key)
                let samples = tone(f0: f0, sampleRate: sr, seconds: 0.6, rng: &rng)
                // Inharmonic partials are slightly sharp; compare against the actual partial.
                let B = inharmonicity(key)
                let truePartial = Double(partial) * f0 * sqrt(1 + B * Double(partial * partial))
                let expected = PianoKey.equalTempered(key, reference: 440) * Double(partial)
                guard let m = analyzer.measure(samples: samples, sampleRate: sr, expected: expected) else {
                    print(String(format: "%3d  %+6.1f   no reading", key, offset))
                    failures += 1
                    continue
                }
                let err = Tuning.cents(m.frequency, relativeTo: truePartial)
                worst = max(worst, abs(err))
                if abs(err) > 0.3 { failures += 1 }
                print(String(format: "%3d  %+6.1f   %+7.2f¢   %+.3f¢  snr %.0f dB", key, offset, Tuning.cents(m.frequency, relativeTo: expected), err, m.snrDb))
            }
        }

        var detectHits = 0
        let detectKeys = Array(stride(from: 25, through: 84, by: 3))
        for key in detectKeys {
            let f0 = PianoKey.equalTempered(key, reference: 440)
            let s = tone(f0: f0, sampleRate: sr, seconds: 0.6, rng: &rng)
            if analyzer.detectKey(samples: s, sampleRate: sr, reference: 440) == key { detectHits += 1 }
        }

        print(String(format: "\nWorst partial error: %.3f cents, %d failures", worst, failures))
        print("Key detection: \(detectHits)/\(detectKeys.count)")
        return failures == 0
    }

    static func inharmonicity(_ key: Int) -> Double {
        0.00012 * pow(2, Double(key - 30) / 18)
    }

    /// A decaying, inharmonic, slightly noisy piano-ish tone.
    static func tone(f0: Double, sampleRate: Double, seconds: Double, rng: inout SystemRandomNumberGenerator) -> [Float] {
        let n = Int(seconds * sampleRate)
        let B = inharmonicity(Int((12 * log2(f0 / 440)).rounded()) + 49)
        var out = [Float](repeating: 0, count: n)
        for h in 1...10 {
            let fh = Double(h) * f0 * sqrt(1 + B * Double(h * h))
            guard fh < sampleRate / 2.2 else { break }
            // Weak fundamental in the bass, like a small microphone hears it.
            let amp = (f0 < 120 && h == 1 ? 0.15 : 1.0) / Double(h)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            let w = 2 * Double.pi * fh / sampleRate
            for i in 0..<n {
                let decay = exp(-Double(i) / sampleRate * (1.2 + Double(h) * 0.4))
                out[i] += Float(amp * decay * sin(w * Double(i) + phase))
            }
        }
        for i in 0..<n {
            out[i] = out[i] * 0.3 + Float.random(in: -0.004...0.004, using: &rng)
        }
        return out
    }
}
