#!/bin/zsh
set -eu
jarvis_dir="$(cd "$(dirname "$0")" && pwd)"
jarvis_work="$jarvis_dir/.build/verification"
mkdir -p "$jarvis_work"
python3 - "$jarvis_dir" "$jarvis_work" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Source/Jarvis.swift').read_text()
(Path(sys.argv[2]) / 'Core.swift').write_text(source[:source.index('// Session changes')])
PY
swiftc -D TESTING -parse-as-library "$jarvis_work/Core.swift" "$jarvis_dir/Source/Realtime.swift" "$jarvis_dir/Source/Tests.swift" -o "$jarvis_work/checks" -framework SwiftUI -framework AVFoundation -framework AppKit -framework Security
"$jarvis_work/checks"
