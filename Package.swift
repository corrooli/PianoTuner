// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PianoTuner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PianoTuner",
            path: "Sources/PianoTuner"
        )
    ]
)
