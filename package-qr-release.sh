#!/bin/bash
set -euo pipefail
umask 077

if [[ $# != 2 ]]; then
    printf 'Usage: %s EchoGram.app output.zip\n' "$0" >&2
    exit 2
fi

app="$1"
output="$2"
build_root="$(pwd -P)"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
staging="$(mktemp -d "$output_dir/.echogram-release.XXXXXX")"
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$staging"' EXIT
staged_app="$staging/EchoGram.app"

codesign --verify --deep --strict "$app"
ditto --norsrc "$app" "$staged_app"
xpc="$staged_app/Contents/XPCServices/WidgetEngineService.xpc"

test ! -e "$staged_app/Contents/Resources/telegram-api.json"
python3 - "$staged_app" "$xpc" "$build_root" <<'PYTHON'
from pathlib import Path
import sys

app, widget, root = sys.argv[1:]
app, widget = Path(app), Path(widget)
prefix = (root.rstrip("/") + "/").encode()
if root.startswith("/Users/") and len(prefix) >= len(b"/build/echogram/"):
    replacement = b"/build/echogram/".ljust(len(prefix), b"/")
    for executable in (app / "Contents/MacOS/EchoGram", widget / "Contents/MacOS/WidgetEngineService"):
        if not executable.is_file():
            continue
        contents = executable.read_bytes()
        if prefix in contents:
            executable.write_bytes(contents.replace(prefix, replacement))
PYTHON

if [[ -d "$xpc" ]]; then
    codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,runtime "$xpc"
fi
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,runtime "$staged_app"
codesign --verify --deep --strict "$staged_app"
ditto -c -k --norsrc --keepParent "$staged_app" "$staging/EchoGram.zip"
unzip -tq "$staging/EchoGram.zip"
mv "$staging/EchoGram.zip" "$output"
