#!/usr/bin/env bash
# Builds Piano Tuner.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary: build each architecture, then glue them together.
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0
ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/PianoTuner"
X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/PianoTuner"

APP="build/Piano Tuner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/PianoTuner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
