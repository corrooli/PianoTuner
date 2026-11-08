import SwiftUI

struct ContentView: View {
    @Bindable var model: TunerModel

    private var accent: Color { Theme.color(forCents: model.cents, tolerance: model.tolerance) }

    var body: some View {
        ZStack {
            Backdrop(accent: model.cents == nil ? Theme.gold : accent)
                .animation(.easeInOut(duration: 0.6), value: model.cents == nil)

            VStack(spacing: 18) {
                HeaderBar(model: model)

                HStack(alignment: .top, spacing: 18) {
                    TunerPanel(model: model, accent: accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    InspectorPanel(model: model)
                        .frame(width: 310)
                }
                .frame(maxHeight: .infinity)

                KeyboardView(
                    selected: model.selectedKey,
                    layout: model.layout,
                    accent: accent,
                    doneCount: { model.doneCount(for: $0) },
                    onSelect: { k in withAnimation(.snappy) { model.select(key: k) } }
                )
                .frame(height: 176)
                .card(padding: 16, radius: 22)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .background(KeyboardShortcuts(model: model))
    }
}

/// Invisible buttons that carry the keyboard shortcuts.
private struct KeyboardShortcuts: View {
    let model: TunerModel

    var body: some View {
        ZStack {
            Button("") { withAnimation(.snappy) { model.stepKey(-1) } }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { withAnimation(.snappy) { model.stepKey(1) } }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { withAnimation(.snappy) { model.stepString(-1) } }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { withAnimation(.snappy) { model.stepString(1) } }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { withAnimation(.snappy) { model.toggleDone() } }.keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Bindable var model: TunerModel
    @State private var showDevices = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                        .shadow(color: Theme.gold.opacity(0.4), radius: 10)
                    Image(systemName: "tuningfork")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.8))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Piano Tuner")
                        .font(Theme.display(22, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("\(model.pianoType.title)  ·  A4 = \(String(format: "%.1f", model.reference)) Hz  ·  \(model.stretch == .off ? "Equal temperament" : "\(model.stretch.title) stretch")")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.leading, 64)

            Spacer()

            GlassSegmented(
                options: PianoType.allCases,
                selection: $model.pianoType,
                title: { $0.title },
                symbol: { $0 == .upright ? "rectangle.portrait" : "rectangle.landscape.rotate" }
            )

            GlassSegmented(
                options: DisplayMode.allCases,
                selection: $model.displayMode,
                title: { $0.title },
                symbol: { $0.symbol }
            )

            Button { showDevices.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.permission == .denied ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(model.isListening ? Theme.mint : Theme.sharp)
                    Text(model.selectedDeviceName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: 170)
                    LevelMeter(db: model.signalDb, segments: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDevices, arrowEdge: .bottom) {
                DeviceList(model: model, dismiss: { showDevices = false })
            }
        }
        .frame(height: 44)
    }
}

private struct DeviceList: View {
    @Bindable var model: TunerModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Microphone").padding(.horizontal, 10).padding(.bottom, 4)
            row(name: "System default", detail: "Follows macOS sound settings", selected: model.selectedDeviceUID == nil) {
                model.selectedDeviceUID = nil
            }
            ForEach(model.devices) { device in
                row(name: device.name, detail: nil, selected: model.selectedDeviceUID == device.uid) {
                    model.selectedDeviceUID = device.uid
                }
            }
            Text("Tip: set the MacBook on top of the upright, or point an external mic at the soundboard.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.backgroundTop)
    }

    private func row(name: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tuner panel

private struct TunerPanel: View {
    @Bindable var model: TunerModel
    let accent: Color

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                NoteHeader(model: model)
                Spacer()
                StringSelector(model: model)
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    switch model.displayMode {
                    case .analog:
                        AnalogGauge(cents: model.cents, tolerance: model.tolerance, holdProgress: model.holdProgress, color: accent)
                            .padding(.top, 8)
                    case .digital:
                        DigitalReadout(cents: model.cents, tolerance: model.tolerance, color: accent)
                    case .strobe:
                        StrobeView(cents: model.cents, tolerance: model.tolerance, color: accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

                if model.currentIsDone {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("TUNED").tracking(1.6)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.mint.opacity(0.12)))
                    .padding(4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.displayMode)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.currentIsDone)
            .overlay { if model.permission == .denied { PermissionOverlay(model: model) } }

            InfoStrip(model: model)

            HStack(alignment: .center, spacing: 14) {
                InstructionView(instruction: model.instruction, accent: accent)
                Spacer(minLength: 10)
                PillButton(title: "Back", symbol: "chevron.left") { withAnimation(.snappy) { model.retreat() } }
                PillButton(title: model.currentIsDone ? "Unmark" : "Mark tuned", symbol: model.currentIsDone ? "arrow.uturn.backward" : "checkmark", shortcut: "Space") {
                    withAnimation(.snappy) { model.toggleDone() }
                }
                PillButton(title: "Next string", symbol: "chevron.right", prominent: true, shortcut: "↩") {
                    withAnimation(.snappy) { model.advance() }
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .card(padding: 24, radius: 28)
    }
}

private struct NoteHeader: View {
    let model: TunerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(model.key.letter)
                    .font(Theme.display(76, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.ivory, Theme.gold], startPoint: .top, endPoint: .bottom)
                    )
                Text("\(model.key.octave)")
                    .font(Theme.display(34, weight: .regular))
                    .foregroundStyle(Theme.gold.opacity(0.85))
                    .baselineOffset(-4)
            }
            .contentTransition(.interpolate)
            .shadow(color: Theme.gold.opacity(0.25), radius: 20)

            VStack(alignment: .leading, spacing: 5) {
                if let flat = model.key.flatName {
                    Text("also \(flat)")
                        .font(Theme.display(15).italic())
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Key \(model.selectedKey) of 88")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    Text(String(format: "%.2f Hz", model.targetFrequency))
                        .font(Theme.rounded(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.gold)
                    if abs(model.stretchOffset) >= 0.05 {
                        Text(String(format: "%@%.1f¢ stretch", model.stretchOffset > 0 ? "+" : "\u{2212}", abs(model.stretchOffset)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }
}

private struct StringSelector: View {
    let model: TunerModel

    var body: some View {
        let count = model.stringCount
        let names = model.stringNames
        VStack(alignment: .trailing, spacing: 10) {
            SectionLabel(count == 1 ? "1 string" : "\(count) strings  ·  \(names[model.selectedString]) now")
            HStack(spacing: 10) {
                ForEach(StringLayout.physicalOrder(count: count), id: \.self) { index in
                    let selected = index == model.selectedString
                    let done = model.isDone(key: model.selectedKey, string: index)
                    Button {
                        withAnimation(.snappy) { model.select(string: index) }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? Theme.gold.opacity(0.14) : Color.black.opacity(0.3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(selected ? Theme.gold.opacity(0.7) : Theme.hairline, lineWidth: selected ? 1.5 : 1)
                                    )
                                // The string itself
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: done
                                                ? [Theme.mint.opacity(0.6), Theme.mint]
                                                : selected ? [Theme.goldDeep, Theme.gold, Theme.ivory] : [Color.white.opacity(0.25), Color.white.opacity(0.45)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: model.selectedKey <= model.layout.doubleThrough ? 4 : 2.5, height: 46)
                                    .shadow(color: selected ? Theme.gold.opacity(0.8) : done ? Theme.mint.opacity(0.6) : .clear, radius: 6)
                                Text("\(index + 1)")
                                    .font(Theme.rounded(10, weight: .bold))
                                    .foregroundStyle(selected ? Theme.gold : Theme.textTertiary)
                                    .offset(x: 13, y: -19)
                            }
                            .frame(width: 46, height: 62)
                            Text(names[index])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? Theme.text : Theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct InfoStrip: View {
    let model: TunerModel

    var body: some View {
        HStack(spacing: 0) {
            cell("Target", Readout.hz(model.targetFrequency), unit: "Hz")
            divider
            cell("Heard", Readout.hz(model.heardFrequency), unit: "Hz")
            divider
            cell("Listening to", model.partial == 1 ? "Fundamental" : "Partial \(model.partial)", unit: nil)
            divider
            cell("Signal", nil, unit: nil) {
                LevelMeter(db: model.signalDb)
            }
            divider
            cell("Hold", nil, unit: nil) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 70, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.mint).frame(width: 70 * model.holdProgress, height: 5)
                            .shadow(color: Theme.mint, radius: 4)
                    }
                    .animation(.linear(duration: 0.1), value: model.holdProgress)
            }
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 28)
    }

    private func cell(_ title: String, _ value: String?, unit: String?, @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 5) {
            SectionLabel(title)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(Theme.rounded(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    if let unit { Text(unit).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textTertiary) }
                }
            } else {
                extra().frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InstructionView: View {
    let instruction: Instruction
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.gold.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(instruction.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(instruction.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}

private struct PermissionOverlay: View {
    let model: TunerModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.slash.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.sharp)
            Text("Microphone access is off")
                .font(Theme.display(22))
                .foregroundStyle(Theme.text)
            Text("Piano Tuner needs to hear the strings. Turn it on in System Settings, then come back.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            PillButton(title: "Open System Settings", symbol: "gearshape", prominent: true) {
                model.openMicrophoneSettings()
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.backgroundBottom.opacity(0.92)))
    }
}
