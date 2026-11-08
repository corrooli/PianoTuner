import SwiftUI

struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

enum Theme {
    static let goldRGB = RGB(r: 0.91, g: 0.75, b: 0.47)
    static let mintRGB = RGB(r: 0.38, g: 0.93, b: 0.70)
    static let flatRGB = RGB(r: 0.43, g: 0.67, b: 1.00)
    static let sharpRGB = RGB(r: 1.00, g: 0.49, b: 0.38)

    static let gold = goldRGB.color
    static let goldDeep = Color(red: 0.62, green: 0.46, blue: 0.22)
    static let mint = mintRGB.color
    static let flat = flatRGB.color
    static let sharp = sharpRGB.color
    static let felt = Color(red: 0.42, green: 0.07, blue: 0.10)

    static let ivory = Color(red: 0.97, green: 0.94, blue: 0.89)
    static let ivoryShade = Color(red: 0.86, green: 0.82, blue: 0.75)
    static let text = ivory
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.08)

    static let backgroundTop = Color(red: 0.065, green: 0.058, blue: 0.075)
    static let backgroundBottom = Color(red: 0.02, green: 0.02, blue: 0.028)

    static func rgb(forCents cents: Double?, tolerance: Double) -> RGB {
        guard let cents else { return goldRGB }
        let a = abs(cents)
        if a <= tolerance { return mintRGB }
        let t = min(1, (a - tolerance) / 10)
        return mintRGB.mix(cents < 0 ? flatRGB : sharpRGB, 0.35 + 0.65 * t)
    }

    static func color(forCents cents: Double?, tolerance: Double) -> Color {
        rgb(forCents: cents, tolerance: tolerance).color
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Shared modifiers

struct CardBackground: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.white.opacity(0.022)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            }
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 24) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct Backdrop: View {
    var accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: UnitPoint(x: 0.36, y: 0.42),
                startRadius: 10,
                endRadius: 720
            )
            RadialGradient(
                colors: [Theme.gold.opacity(0.07), .clear],
                center: UnitPoint(x: 0.95, y: 0.0),
                startRadius: 0,
                endRadius: 600
            )
            RadialGradient(
                colors: [Theme.felt.opacity(0.18), .clear],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 0,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}
