import AppKit
import Foundation

let arguments = CommandLine.arguments

if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    let path = arguments[i + 1]
    let mode = arguments.firstIndex(of: "--mode").flatMap { j in
        j + 1 < arguments.count ? DisplayMode(rawValue: arguments[j + 1]) : nil
    } ?? .analog
    let cents = arguments.firstIndex(of: "--cents").flatMap { j in
        j + 1 < arguments.count ? Double(arguments[j + 1]) : nil
    }
    MainActor.assumeIsolated {
        Snapshot.render(to: path, mode: mode, cents: cents)
    }
    exit(0)
}

if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

PianoTunerApp.main()
