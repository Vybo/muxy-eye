#!/usr/bin/env bash
# Builds the app and its hook helper, then assembles and ad-hoc signs "build/Muxy Eye.app".
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail

configuration="${1:-debug}"
case "$configuration" in
    debug | release) ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 64
        ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Build output goes to stderr so stdout carries only the app path.
swift build -c "$configuration" --product MuxyEye >&2
swift build -c "$configuration" --product muxy-eye-hook >&2
bin="$(swift build -c "$configuration" --show-bin-path)"

app="build/Muxy Eye.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
cp "$bin/MuxyEye" "$app/Contents/MacOS/MuxyEye"
cp "$bin/muxy-eye-hook" "$app/Contents/Helpers/muxy-eye-hook"
cp Support/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - --options runtime --identifier io.github.vybo.muxy-eye.hook "$app/Contents/Helpers/muxy-eye-hook"
codesign --force --sign - --options runtime "$app"

echo "$root/$app"
