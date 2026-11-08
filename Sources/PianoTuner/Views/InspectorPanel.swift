import SwiftUI

struct InspectorPanel: View {
    @Bindable var model: TunerModel

    var body: some View {
        if model.demo {
            content
        } else {
            ScrollView(.vertical) { content }
                .scrollIndicators(.never)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            ProgressCard(model: model)
            TuningCard(model: model)
            AssistCard(model: model)
            StringsCard(model: model)
        }
    }
}

private struct ProgressCard: View {
    @Bindable var model: TunerModel
    @State private var confirmReset = false

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(
                        AngularGradient(colors: [Theme.goldDeep, Theme.gold, Theme.mint], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.mint.opacity(0.35), radius: 6)
                VStack(spacing: 0) {
                    Text("\(Int((model.progress * 100).rounded()))")
                        .font(Theme.rounded(24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 76, height: 76)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: model.progress)

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("This session")
                Text("\(model.doneStrings) of \(model.totalStrings) strings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(model.pianoType.title) piano, saved automatically")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    confirmReset = true
                } label: {
                    Text("Start over")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .confirmationDialog("Clear all tuned strings for this piano?", isPresented: $confirmReset) {
                    Button("Start over", role: .destructive) { model.resetSession() }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 16, radius: 22)
    }
}

private struct TuningCard: View {
    @Bindable var model: TunerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Tuning")
            SettingRow(title: "Concert pitch", subtitle: "A4 reference") {
                ValueStepper(
                    label: String(format: "%.1f", model.reference),
                    onMinus: { model.reference = max(415, model.reference - 0.5) },
                    onPlus: { model.reference = min(466, model.reference + 0.5) }
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingRow(title: "Stretch", subtitle: stretchDetail) { EmptyView() }
                GlassSegmented(options: StretchAmount.allCases, selection: $model.stretch, title: { $0.title }, compact: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingRow(title: "Order", subtitle: model.order.detail) { EmptyView() }
                GlassSegmented(options: TuningOrder.allCases, selection: $model.order, title: { $0.title }, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 22)
    }

    private var stretchDetail: String {
        switch model.stretch {
        case .off: "Pure equal temperament"
        case .gentle: "A light octave stretch"
        case .standard: model.pianoType == .upright ? "Typical curve for an upright" : "Typical curve for a grand"
        }
    }
}

private struct AssistCard: View {
    @Bindable var model: TunerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Assist")
            SettingRow(title: "Auto advance", subtitle: "Hold in tune, then move on") {
                GoldSwitch(isOn: $model.autoAdvance)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tolerance").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(String(format: "±%.1f¢", model.tolerance))
                        .font(Theme.rounded(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.gold)
                }
                GoldSlider(value: $model.tolerance, range: 0.5...3, step: 0.1)
            }
            SettingRow(title: "Follow played key", subtitle: "Jumps to the note you strike") {
                GoldSwitch(isOn: $model.followPlayedKey)
            }
            SettingRow(title: "Chime when tuned") {
                GoldSwitch(isOn: $model.chime)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 22)
    }
}

private struct StringsCard: View {
    @Bindable var model: TunerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel("Strings per note")
                Spacer()
                Button("Default") { model.resetLayout() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.gold)
            }
            SettingRow(title: "Single up to") {
                ValueStepper(
                    label: model.layout.singleThrough == 0 ? "None" : PianoKey(number: model.layout.singleThrough).name,
                    onMinus: { model.setSingleThrough(model.layout.singleThrough - 1) },
                    onPlus: { model.setSingleThrough(model.layout.singleThrough + 1) }
                )
            }
            SettingRow(title: "Double up to") {
                ValueStepper(
                    label: model.layout.doubleThrough <= model.layout.singleThrough ? "None" : PianoKey(number: model.layout.doubleThrough).name,
                    onMinus: { model.setDoubleThrough(model.layout.doubleThrough - 1) },
                    onPlus: { model.setDoubleThrough(model.layout.doubleThrough + 1) }
                )
            }
            Text("Peek inside and count the strings on the lowest notes. Every piano is a little different.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 22)
    }
}
