import SwiftUI

/// Pill shaped segmented control with a sliding gold highlight.
struct GlassSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String
    var symbol: ((Value) -> String)? = nil
    var compact = false

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol {
                            Image(systemName: symbol(option)).font(.system(size: 11, weight: .semibold))
                        }
                        Text(title(option)).font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textSecondary)
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 6 : 7)
                    .frame(maxWidth: compact ? .infinity : nil)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                                .shadow(color: Theme.gold.opacity(0.35), radius: 8)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct GoldSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.2 : 0.08), lineWidth: 1))
                Circle()
                    .fill(LinearGradient(colors: [.white, Theme.ivoryShade], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(2.5)
            }
            .frame(width: 38, height: 22)
        }
        .buttonStyle(.plain)
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct GoldSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(t) * (w - 16) + 8
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.goldDeep, Theme.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x, height: 4)
                Circle()
                    .fill(LinearGradient(colors: [.white, Theme.ivoryShade], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 16)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 6)
                    .offset(x: x - 8)
            }
            .frame(height: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let t = Double(max(0, min(1, (g.location.x - 8) / (w - 16))))
                    let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
                    value = (raw / step).rounded() * step
                }
            )
        }
        .frame(height: 20)
    }
}

struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ValueStepper: View {
    let label: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RoundIconButton(symbol: "minus", action: onMinus)
            Text(label)
                .font(Theme.rounded(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
                .frame(minWidth: 58)
            RoundIconButton(symbol: "plus", action: onPlus)
        }
    }
}

struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var shortcut: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(prominent ? 0.18 : 0.3)))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(
                    prominent
                    ? AnyShapeStyle(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.white.opacity(hovering ? 0.12 : 0.07))
                )
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0.25 : 0.09), lineWidth: 1))
            .shadow(color: prominent ? Theme.gold.opacity(hovering ? 0.45 : 0.25) : .clear, radius: 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct LevelMeter: View {
    var db: Double
    var segments = 14

    var body: some View {
        let lit = Int(((db + 70) / 60 * Double(segments)).rounded())
        HStack(spacing: 2.5) {
            ForEach(0..<segments, id: \.self) { i in
                let t = Double(i) / Double(segments - 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < lit ? Theme.mintRGB.mix(Theme.sharpRGB, max(0, t - 0.6) * 2.5).color : Color.white.opacity(0.09))
                    .frame(width: 4, height: 6 + CGFloat(t) * 8)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeOut(duration: 0.08), value: lit)
    }
}
