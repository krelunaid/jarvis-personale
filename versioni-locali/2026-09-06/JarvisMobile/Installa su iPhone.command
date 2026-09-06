#!/bin/zsh
set -eu
jarvis_mobile_dir="$(cd "$(dirname "$0")" && pwd)"
jarvis_flutter="$jarvis_mobile_dir/../../work/flutter/bin/flutter"
if [[ ! -x "$jarvis_flutter" ]]; then jarvis_flutter="$(command -v flutter || true)"; fi
if [[ -z "$jarvis_flutter" ]]; then echo 'Flutter non trovato. Apri questo progetto sul Mac dove è stato preparato.'; read; exit 1; fi
cd "$jarvis_mobile_dir"
jarvis_device="$($jarvis_flutter devices --machine | python3 -c 'import json,sys; print(next((d["id"] for d in json.load(sys.stdin) if d.get("targetPlatform")=="ios" and not d.get("emulator",False)),""))')"
if [[ -z "$jarvis_device" ]]; then echo 'Collega e sblocca il tuo iPhone. Autorizza il Mac sul telefono, poi riapri questo comando.'; read; exit 1; fi
"$jarvis_flutter" run --release -d "$jarvis_device"
