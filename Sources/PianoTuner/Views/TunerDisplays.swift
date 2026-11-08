import SwiftUI

// MARK: - Shared readout bits

enum Readout {
    static func centsText(_ cents: Double?) -> String {
        guard let cents else { return "--" }
        let v = (cents * 10).rounded() / 10
        if v == 0 { return "0.0" }
        return String(format: "%@%.1f", v > 0 ? "+" : "\u{2212}", abs(v))
    }

    static func status(_ cents: Double?, tolerance: Double) -> String {
        guard let cents else { return "Play the note" }
        if abs(cents) <= tolerance { return "In tune" }
        if abs(cents) > 50 { return cents < 0 ? "Far too low, raise pitch" : "Far too high, lower pitch" }
        return cents < 0 ? "Flat, raise pitch" : "Sharp, lower pitch"
    }

    static func hz(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: value < 100 ? "%.3f" : "%.2f", value)
    }
}

// MARK: - Analog gauge

struct AnalogGauge: View {
    var cents: Double?
    var tolerance: Double
    var holdProgress: Double
    var color: Color

    private var angle: Double { max(-56, min(56, cents ?? 0)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w * 0.5, h - 170, 320)
            let pivot = CGPoint(x: w / 2, y: 50 + radius + 6)

            ZStack {
                dial(pivot: pivot, radius: radius)

                readout
                    .position(x: pivot.x, y: pivot.y + 72)

                Needle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.95), color, .white],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 9, height: radius + 6)
                    .shadow(color: color.opacity(0.9), radius: 8)
                    .shadow(color: color.opacity(0.4), radius: 22)
                    .opacity(cents == nil ? 0.35 : 1)
                    .rotationEffect(.degrees(angle), anchor: .bottom)
                    .position(x: pivot.x, y: pivot.y - (radius + 6) / 2)
                    .animation(.interpolatingSpring(stiffness: 110, damping: 13), value: angle)

                pivotCap
                    .position(pivot)
            }
        }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Readout.centsText(cents))
                    .font(Theme.rounded(54, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: cents ?? 0))
                    .foregroundStyle(cents == nil ? Theme.textTertiary : Theme.text)
                Text("¢")
                    .font(Theme.rounded(24, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(Readout.status(cents, tolerance: tolerance).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(cents == nil ? Theme.textTertiary : color)
        }
        .animation(.snappy(duration: 0.2), value: cents)
    }

    private var pivotCap: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Theme.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 48, height: 48)
                .shadow(color: Theme.mint.opacity(0.8), radius: 6)
                .animation(.linear(duration: 0.1), value: holdProgress)
            Circle()
                .fill(
                    AngularGradient(
                        colors: [Theme.gold, Theme.goldDeep, Theme.ivory, Theme.goldDeep, Theme.gold],
                        center: .center
                    )
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.2), .black], center: .center, startRadius: 0, endRadius: 8))
                .frame(width: 12, height: 12)
        }
    }

    private func dial(pivot c: CGPoint, radius r: CGFloat) -> some View {
        Canvas { ctx, _ in
            func pt(_ deg: Double, _ rr: CGFloat) -> CGPoint {
                let a = deg * .pi / 180
                return CGPoint(x: c.x + rr * CGFloat(sin(a)), y: c.y - rr * CGFloat(cos(a)))
            }
            func arc(_ from: Double, _ to: Double, _ rr: CGFloat) -> Path {
                var p = Path()
                let steps = max(6, Int(abs(to - from) * 2))
                for i in 0...steps {
                    let d = from + (to - from) * Double(i) / Double(steps)
                    if i == 0 { p.move(to: pt(d, rr)) } else { p.addLine(to: pt(d, rr)) }
                }
                return p
            }

            let bandR = r - 16

            // Outer bezel line
            ctx.stroke(arc(-60, 60, r + 44), with: .color(.white.opacity(0.05)), lineWidth: 1)

            // Colour band from flat to sharp
            ctx.stroke(
                arc(-50, 50, bandR),
                with: .linearGradient(
                    Gradient(colors: [Theme.flat.opacity(0.32), Theme.mint.opacity(0.28), Theme.sharp.opacity(0.32)]),
                    startPoint: pt(-50, bandR),
                    endPoint: pt(50, bandR)
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )

            // In tune window
            let tol = max(0.6, tolerance)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.stroke(arc(-tol, tol, bandR), with: .color(Theme.mint.opacity(0.9)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            }
            ctx.stroke(arc(-tol, tol, bandR), with: .color(Theme.mint), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            // Live deflection trail
            if let cents {
                let d = max(-56, min(56, cents))
                if abs(d) > tol {
                    let trail = arc(d > 0 ? tol : d, d > 0 ? d : -tol, bandR)
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 9))
                        layer.stroke(trail, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    }
                    ctx.stroke(trail, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                }
            }

            // Ticks
            for i in -50...50 {
                let deg = Double(i)
                let major = i % 10 == 0
                let mid = i % 5 == 0
                let len: CGFloat = major ? 18 : mid ? 12 : 6
                var tick = Path()
                tick.move(to: pt(deg, r))
                tick.addLine(to: pt(deg, r + len))
                let opacity = i == 0 ? 0.95 : major ? 0.55 : mid ? 0.32 : 0.16
                ctx.stroke(tick, with: .color(i == 0 ? Theme.gold : .white.opacity(opacity)), lineWidth: major ? 2 : 1)

                if major {
                    let label = i == 0 ? "0" : (i > 0 ? "+\(i)" : "\u{2212}\(abs(i))")
                    ctx.draw(
                        Text(label)
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundColor(i == 0 ? Theme.gold : .white.opacity(0.42)),
                        at: pt(deg, r + 32)
                    )
                }
            }

            ctx.draw(
                Text("♭").font(Theme.display(30)).foregroundColor(Theme.flat.opacity(0.8)),
                at: pt(-50, bandR - 34)
            )
            ctx.draw(
                Text("♯").font(Theme.display(30)).foregroundColor(Theme.sharp.opacity(0.8)),
                at: pt(50, bandR - 34)
            )
        }
    }
}

struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        p.move(to: CGPoint(x: rect.midX - 0.8, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + 0.8, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + w / 2, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX - w / 2, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Digital readout

struct DigitalReadout: View {
    var cents: Double?
    var tolerance: Double
    var color: Color

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Readout.centsText(cents))
                    .font(Theme.rounded(138, weight: .ultraLight))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: cents ?? 0))
                    .foregroundStyle(
                        cents == nil
                        ? AnyShapeStyle(Theme.textTertiary)
                        : AnyShapeStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: color.opacity(cents == nil ? 0 : 0.45), radius: 24)
                Text("cents")
                    .font(Theme.rounded(20, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
            .animation(.snappy(duration: 0.2), value: cents)

            segmentBar

            HStack {
                indicator("FLAT", lit: (cents ?? 0) < -tolerance, color: Theme.flat, symbol: "arrow.up")
                Spacer()
                indicator("IN TUNE", lit: cents.map { abs($0) <= tolerance } ?? false, color: Theme.mint, symbol: "checkmark")
                Spacer()
                indicator("SHARP", lit: (cents ?? 0) > tolerance, color: Theme.sharp, symbol: "arrow.down")
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
    }

    private var segmentBar: some View {
        let c = cents
        return HStack(spacing: 3) {
            ForEach(-25...25, id: \.self) { i in
                let v = Double(i) * 2
                let lit: Bool = {
                    guard let c else { return false }
                    if i == 0 { return abs(c) <= max(1, tolerance) }
                    return v < 0 ? (c <= v + 1) : (c >= v - 1)
                }()
                let rgb = i == 0 ? Theme.mintRGB : Theme.mintRGB.mix(i < 0 ? Theme.flatRGB : Theme.sharpRGB, 0.3 + Double(abs(i)) / 25 * 0.7)
                RoundedRectangle(cornerRadius: 2)
                    .fill(lit ? rgb.color : Color.white.opacity(i % 5 == 0 ? 0.13 : 0.07))
                    .frame(width: i == 0 ? 7 : 5, height: i == 0 ? 40 : (i % 5 == 0 ? 30 : 22))
                    .shadow(color: lit ? rgb.color.opacity(0.8) : .clear, radius: 6)
            }
        }
        .animation(.easeOut(duration: 0.12), value: cents)
    }

    private func indicator(_ title: String, lit: Bool, color: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .black))
            Text(title).font(.system(size: 11, weight: .bold)).tracking(2)
        }
        .foregroundStyle(lit ? color : Theme.textTertiary.opacity(0.6))
        .shadow(color: lit ? color.opacity(0.8) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

// MARK: - Strobe

final class StrobeState {
    var offsets: [Double] = [0, 0, 0]
    var last: Date?
}

struct StrobeView: View {
    var cents: Double?
    var tolerance: Double
    var color: Color

    @State private var state = StrobeState()

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Readout.centsText(cents))
                    .font(Theme.rounded(46, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: cents ?? 0))
                    .foregroundStyle(cents == nil ? Theme.textTertiary : Theme.text)
                Text("¢").font(Theme.rounded(20, weight: .light)).foregroundStyle(Theme.textTertiary)
            }

            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let now = timeline.date
                    let dt = state.last.map { min(0.05, now.timeIntervalSince($0)) } ?? 0
                    state.last = now
                    let speed = max(-60, min(60, cents ?? 0)) * 9

                    let rows = 3
                    let gap: CGFloat = 12
                    let rowH = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                    for row in 0..<rows {
                        let mult = Double(row + 1)
                        state.offsets[row] += speed * mult * dt
                        let y = CGFloat(row) * (rowH + gap)
                        let rect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                        let shape = Path(roundedRect: rect, cornerRadius: rowH / 2)
                        ctx.fill(shape, with: .color(.black.opacity(0.45)))

                        var inner = ctx
                        inner.clip(to: shape)
                        let period = CGFloat(56 / mult) + 10
                        let stripe = period * 0.5
                        let skew: CGFloat = rowH * 0.45
                        let off = CGFloat(state.offsets[row].truncatingRemainder(dividingBy: Double(period)))
                        var x = -period * 2 + off
                        var stripes = Path()
                        while x < size.width + period * 2 {
                            stripes.move(to: CGPoint(x: x, y: y + rowH))
                            stripes.addLine(to: CGPoint(x: x + skew, y: y))
                            stripes.addLine(to: CGPoint(x: x + skew + stripe, y: y))
                            stripes.addLine(to: CGPoint(x: x + stripe, y: y + rowH))
                            stripes.closeSubpath()
                            x += period
                        }
                        let opacity = cents == nil ? 0.18 : 0.85 - Double(row) * 0.15
                        inner.drawLayer { layer in
                            layer.addFilter(.blur(radius: 4))
                            layer.fill(stripes, with: .color(color.opacity(opacity * 0.6)))
                        }
                        inner.fill(stripes, with: .color(color.opacity(opacity)))

                        // Soft vignette at the ends
                        inner.fill(
                            Path(rect),
                            with: .linearGradient(
                                Gradient(stops: [
                                    .init(color: Theme.backgroundBottom.opacity(0.95), location: 0),
                                    .init(color: .clear, location: 0.18),
                                    .init(color: .clear, location: 0.82),
                                    .init(color: Theme.backgroundBottom.opacity(0.95), location: 1),
                                ]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: size.width, y: 0)
                            )
                        )
                        ctx.stroke(shape, with: .color(.white.opacity(0.08)), lineWidth: 1)
                    }
                }
            }
            .frame(height: 170)
            .padding(.horizontal, 36)

            Text(cents == nil
                 ? "Strike the key. The bands drift when the string is off pitch."
                 : abs(cents ?? 0) <= tolerance
                    ? "Standing still. That string is home."
                    : (cents ?? 0) > 0 ? "Drifting right: sharp, ease the pin down." : "Drifting left: flat, bring the pin up.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(cents == nil ? Theme.textTertiary : Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
