import SwiftUI

/// Full 88 key keyboard. Click a key to tune it. Dots show finished strings.
struct KeyboardView: View {
    var selected: Int
    var layout: StringLayout
    var accent: Color
    var doneCount: (Int) -> Int
    var onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let ww = geo.size.width / 52
            let zoneH: CGFloat = 20
            let labelH: CGFloat = 16
            let keyH = geo.size.height - zoneH - labelH - 6
            let blackW = ww * 0.6
            let blackH = keyH * 0.63
            let frame = { (key: Int) -> (x: CGFloat, w: CGFloat) in
                Self.keyFrame(key, whiteWidth: ww)
            }

            VStack(spacing: 0) {
                zoneBar(width: geo.size.width, frame: frame)
                    .frame(height: zoneH)
                    .padding(.bottom, 6)

                ZStack(alignment: .topLeading) {
                    // Key slip felt
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.felt, Theme.felt.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 4)
                        .offset(y: -4)

                    ForEach(PianoKey.whites) { key in
                        WhiteKey(
                            key: key,
                            selected: key.number == selected,
                            strings: layout.count(for: key.number),
                            done: doneCount(key.number)
                        )
                        .frame(width: ww - 1.2, height: keyH)
                        .offset(x: frame(key.number).x)
                        .onTapGesture { onSelect(key.number) }
                    }

                    ForEach(PianoKey.blacks) { key in
                        BlackKey(
                            selected: key.number == selected,
                            strings: layout.count(for: key.number),
                            done: doneCount(key.number)
                        )
                        .frame(width: blackW, height: blackH)
                        .offset(x: frame(key.number).x)
                        .onTapGesture { onSelect(key.number) }
                    }
                }
                .frame(width: geo.size.width, height: keyH, alignment: .topLeading)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 12)

                ZStack(alignment: .topLeading) {
                    ForEach(PianoKey.whites.filter { $0.pitchClass == 0 }) { key in
                        Text(key.name)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: ww)
                            .offset(x: frame(key.number).x)
                    }
                }
                .frame(width: geo.size.width, height: labelH, alignment: .bottomLeading)
            }
        }
    }

    static func keyFrame(_ key: Int, whiteWidth ww: CGFloat) -> (x: CGFloat, w: CGFloat) {
        let below = CGFloat(PianoKey.whitesBelow[key] ?? 0)
        let blackW = ww * 0.6
        return PianoKey(number: key).isBlack ? (below * ww - blackW / 2, blackW) : (below * ww, ww)
    }

    private func zoneBar(width: CGFloat, frame: @escaping (Int) -> (x: CGFloat, w: CGFloat)) -> some View {
        var zones: [(String, ClosedRange<Int>, Color)] = []
        if layout.singleThrough >= 1 {
            zones.append(("Single", 1...layout.singleThrough, Theme.flat))
        }
        if layout.doubleThrough > layout.singleThrough {
            zones.append(("Double", (layout.singleThrough + 1)...layout.doubleThrough, Theme.gold))
        }
        if layout.doubleThrough < 88 {
            zones.append(("Triple", (layout.doubleThrough + 1)...88, Theme.mint))
        }

        return ZStack(alignment: .topLeading) {
            ForEach(zones, id: \.0) { zone in
                let a = frame(zone.1.lowerBound)
                let b = frame(zone.1.upperBound)
                let x0 = a.x
                let x1 = b.x + b.w
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(zone.0.uppercased())  \(PianoKey(number: zone.1.lowerBound).name)–\(PianoKey(number: zone.1.upperBound).name)")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(zone.2.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                    Capsule()
                        .fill(LinearGradient(colors: [zone.2.opacity(0.55), zone.2.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, x1 - x0 - 3), height: 3)
                }
                .offset(x: x0 + 1)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

private struct DoneDots: View {
    let strings: Int
    let done: Int
    let onDark: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<strings, id: \.self) { i in
                Circle()
                    .fill(i < done ? Theme.mint : (onDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)))
                    .frame(width: 4, height: 4)
                    .shadow(color: i < done ? Theme.mint.opacity(0.9) : .clear, radius: 3)
            }
        }
    }
}

private struct WhiteKey: View {
    let key: PianoKey
    let selected: Bool
    let strings: Int
    let done: Int

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .fill(
                    LinearGradient(
                        colors: selected
                            ? [Theme.gold.opacity(0.75), Theme.gold, Color(red: 1, green: 0.9, blue: 0.7)]
                            : [Theme.ivoryShade, Theme.ivory, hovering ? .white : Theme.ivory.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 5)
                }
            DoneDots(strings: strings, done: done, onDark: false)
                .padding(.bottom, 12)
        }
        .shadow(color: selected ? Theme.gold.opacity(0.8) : .clear, radius: 10)
        .zIndex(selected ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct BlackKey: View {
    let selected: Bool
    let strings: Int
    let done: Int

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                .fill(
                    LinearGradient(
                        colors: selected
                            ? [Theme.goldDeep, Theme.gold]
                            : [Color(white: 0.04), Color(white: hovering ? 0.22 : 0.15), Color(white: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    // Glossy sheen
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, 2)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 10)
                        .padding(.top, 2)
                }
                .shadow(color: .black.opacity(0.7), radius: 3, x: 1, y: 3)
            DoneDots(strings: strings, done: done, onDark: true)
                .scaleEffect(0.8)
                .padding(.bottom, 8)
        }
        .shadow(color: selected ? Theme.gold.opacity(0.8) : .clear, radius: 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
