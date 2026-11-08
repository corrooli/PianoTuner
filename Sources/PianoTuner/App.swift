import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PianoTunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = TunerModel()

    var body: some Scene {
        WindowGroup("Piano Tuner") {
            ContentView(model: model)
                .frame(minWidth: 1220, minHeight: 860)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1420, height: 940)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
enum Snapshot {
    /// Renders the UI with demo data to a PNG. Used for README screenshots.
    static func render(to path: String, mode: DisplayMode, cents: Double?) {
        _ = NSApplication.shared
        let model = TunerModel(demo: true)
        model.displayMode = mode
        model.applyDemo(
            key: 52,
            string: 0,
            cents: cents,
            hold: cents.map { abs($0) < 1 ? 0.62 : 0 } ?? 0,
            done: Array(33...51)
        )
        let view = ContentView(model: model)
            .frame(width: 1440, height: 1120)
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Snapshot failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }
}
