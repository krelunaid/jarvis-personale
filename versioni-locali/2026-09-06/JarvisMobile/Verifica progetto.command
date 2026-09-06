#!/bin/zsh
set -eu
jarvis_mobile_dir="$(cd "$(dirname "$0")" && pwd)"
jarvis_flutter="$jarvis_mobile_dir/../../work/flutter/bin/flutter"
if [[ ! -x "$jarvis_flutter" ]]; then jarvis_flutter="$(command -v flutter)"; fi
cd "$jarvis_mobile_dir"
"$jarvis_flutter" pub get
"$jarvis_flutter" analyze
"$jarvis_flutter" test
