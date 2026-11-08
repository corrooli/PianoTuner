import Accelerate
import Foundation

struct PartialMeasurement {
    /// Measured frequency of the partial in Hz.
    let frequency: Double
    /// Peak height above the local noise floor in dB.
    let snrDb: Double
}

/// Real-input FFT built on vDSP.
final class FFT {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    init(size: Int) {
        self.size = size
        log2n = vDSP_Length(log2(Double(size)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Returns real and imaginary parts for bins 0..<size/2. Bin 0 imag holds Nyquist.
    func forward(_ input: [Float]) -> (re: [Float], im: [Float]) {
        let half = size / 2
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withUnsafeBufferPointer { inp in
                    inp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        return (re, im)
    }
}

/// Measures one partial with sub-cent precision.
///
/// 1. A Hann windowed, 4x zero padded FFT finds the peak near the expected
///    partial, refined with Gaussian interpolation.
/// 2. A second frame a short hop later gives a phase difference at that bin,
///    which pins the frequency down far more precisely than the bin spacing
///    (the phase vocoder trick).
final class PitchAnalyzer: @unchecked Sendable {
    private var ffts: [Int: FFT] = [:]
    private var windows: [Int: [Float]] = [:]
    private let zeroPad = 4

    private func fft(_ size: Int) -> FFT {
        if let f = ffts[size] { return f }
        let f = FFT(size: size)
        ffts[size] = f
        return f
    }

    private func window(_ size: Int) -> [Float] {
        if let w = windows[size] { return w }
        let w = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windows[size] = w
        return w
    }

    /// Frame length used for a partial. Lower partials get longer frames for
    /// better precision; higher ones get shorter frames for snappier response.
    static func frameLength(for frequency: Double, sampleRate: Double) -> Int {
        let base: Int = frequency < 300 ? 16_384 : frequency < 1_000 ? 8_192 : 4_096
        return sampleRate > 60_000 ? base * 2 : base
    }

    static func samplesNeeded(for frequency: Double, sampleRate: Double) -> Int {
        let n = frameLength(for: frequency, sampleRate: sampleRate)
        return n + n / 4
    }

    static func detectionLength(sampleRate: Double) -> Int {
        sampleRate > 60_000 ? 32_768 : 16_384
    }

    func measure(samples: [Float], sampleRate: Double, expected: Double, searchCents: Double = 100) -> PartialMeasurement? {
        let n = Self.frameLength(for: expected, sampleRate: sampleRate)
        let hop = n / 4
        guard samples.count >= n + hop, expected > 0, expected < sampleRate / 2.2 else { return nil }

        let m = n * zeroPad
        let w = window(n)
        let engine = fft(m)

        func spectrum(at offset: Int) -> (re: [Float], im: [Float]) {
            var frame = [Float](repeating: 0, count: m)
            samples.withUnsafeBufferPointer { sp in
                frame.withUnsafeMutableBufferPointer { fp in
                    vDSP_vmul(sp.baseAddress! + offset, 1, w, 1, fp.baseAddress!, 1, vDSP_Length(n))
                }
            }
            return engine.forward(frame)
        }

        let start = samples.count - n - hop
        let a = spectrum(at: start)
        let b = spectrum(at: start + hop)

        let binHz = sampleRate / Double(m)
        let half = m / 2
        func power(_ k: Int) -> Double {
            let re = Double(b.re[k]), im = Double(b.im[k])
            return re * re + im * im
        }

        let lo = expected * pow(2, -searchCents / 1200)
        let hi = expected * pow(2, searchCents / 1200)
        let kLo = max(2, Int(lo / binHz))
        let kHi = min(half - 2, Int(hi / binHz) + 1)
        guard kHi > kLo + 2 else { return nil }

        var peakK = kLo
        var peakP = 0.0
        for k in kLo...kHi {
            let p = power(k)
            if p > peakP { peakP = p; peakK = k }
        }
        // A peak on the band edge means the real peak lies outside the window.
        guard peakK > kLo, peakK < kHi, peakP > 0 else { return nil }

        // Gaussian interpolation (parabola through log power).
        let la = log(power(peakK - 1) + 1e-30)
        let lb = log(peakP + 1e-30)
        let lc = log(power(peakK + 1) + 1e-30)
        let denom = la - 2 * lb + lc
        let delta = denom != 0 ? max(-0.5, min(0.5, 0.5 * (la - lc) / denom)) : 0
        let coarse = (Double(peakK) + delta) * binHz

        // Phase vocoder refinement.
        let phaseA = atan2(Double(a.im[peakK]), Double(a.re[peakK]))
        let phaseB = atan2(Double(b.im[peakK]), Double(b.re[peakK]))
        let predicted = 2 * Double.pi * coarse * Double(hop) / sampleRate
        let deviation = principal(phaseB - phaseA - predicted)
        let refined = coarse + deviation * sampleRate / (2 * Double.pi * Double(hop))
        let frequency = abs(refined - coarse) < 1.5 * binHz ? refined : coarse

        // Noise floor: median power across three semitones on either side.
        let nLo = max(2, Int(expected * pow(2, -3.0 / 12) / binHz))
        let nHi = min(half - 2, Int(expected * pow(2, 3.0 / 12) / binHz))
        var neighborhood: [Double] = []
        neighborhood.reserveCapacity(max(0, nHi - nLo + 1))
        if nHi > nLo {
            for k in nLo...nHi { neighborhood.append(power(k)) }
        }
        neighborhood.sort()
        let floor = neighborhood.isEmpty ? 1e-30 : max(neighborhood[neighborhood.count / 2], 1e-30)
        let snr = 10 * log10(peakP / floor)

        return PartialMeasurement(frequency: frequency, snrDb: snr)
    }

    /// Guesses which key is being played by scoring how well each key's
    /// harmonic series lines up with the spectrum.
    func detectKey(samples: [Float], sampleRate: Double, reference: Double) -> Int? {
        let n = Self.detectionLength(sampleRate: sampleRate)
        guard samples.count >= n else { return nil }
        let w = window(n)
        var frame = [Float](repeating: 0, count: n)
        samples.withUnsafeBufferPointer { sp in
            frame.withUnsafeMutableBufferPointer { fp in
                vDSP_vmul(sp.baseAddress! + (samples.count - n), 1, w, 1, fp.baseAddress!, 1, vDSP_Length(n))
            }
        }
        let spec = fft(n).forward(frame)
        let half = n / 2
        let binHz = sampleRate / Double(n)
        let maxHz = min(5_000, sampleRate / 2.2)
        let maxBin = min(half - 1, Int(maxHz / binHz))
        guard maxBin > 8 else { return nil }

        var db = [Double](repeating: -200, count: maxBin + 1)
        for k in 1...maxBin {
            let re = Double(spec.re[k]), im = Double(spec.im[k])
            db[k] = 10 * log10(re * re + im * im + 1e-30)
        }
        let sorted = db[1...maxBin].sorted()
        let floor = sorted[sorted.count / 2]

        func strength(at hz: Double) -> Double {
            let lo = max(1, Int(hz * pow(2, -35.0 / 1200) / binHz))
            let hi = min(maxBin, Int(hz * pow(2, 35.0 / 1200) / binHz) + 1)
            guard hi >= lo else { return 0 }
            var best = -200.0
            for k in lo...hi { best = max(best, db[k]) }
            return max(0, min(40, best - floor - 8))
        }

        var bestKey: Int?
        var bestScore = 0.0
        for key in 1...88 {
            let f0 = PianoKey.equalTempered(key, reference: reference)
            if f0 * 1.0 > maxHz { break }
            var score = 0.0
            for h in 1...6 {
                let f = f0 * Double(h)
                if f > maxHz { break }
                let s = strength(at: f)
                score += s > 0 ? s : -6
            }
            if score > bestScore {
                bestScore = score
                bestKey = key
            }
        }
        return bestScore > 24 ? bestKey : nil
    }

    private func principal(_ x: Double) -> Double {
        var v = x.truncatingRemainder(dividingBy: 2 * .pi)
        if v > .pi { v -= 2 * .pi }
        if v < -.pi { v += 2 * .pi }
        return v
    }
}
