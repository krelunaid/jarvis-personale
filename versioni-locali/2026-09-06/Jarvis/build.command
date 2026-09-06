#!/bin/zsh
set -eu
jarvis_dir="$(cd "$(dirname "$0")" && pwd)"
swiftc -parse-as-library "$jarvis_dir/Source/Jarvis.swift" "$jarvis_dir/Source/Realtime.swift" -o "$jarvis_dir/Jarvis.app/Contents/MacOS/Jarvis" -framework SwiftUI -framework AVFoundation -framework AppKit -framework Security -target arm64-apple-macosx13.0
codesign --force --sign - "$jarvis_dir/Jarvis.app"
codesign --verify --deep --strict "$jarvis_dir/Jarvis.app"
