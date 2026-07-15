#!/bin/bash
# Build RelayBarGlass (light glass menu bar app) and assemble a .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="RelayBarGlass.app"
BIN=".build/release/RelayBarGlass"
BUNDLE_RES=".build/release/RelayBarGlass_RelayBarGlass.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RelayBarGlass"
cp Info.plist "$APP/Contents/Info.plist"
# SwiftPM emits bundled resources in a .bundle next to the binary; ship it inside the app.
[ -d "$BUNDLE_RES" ] && cp -R "$BUNDLE_RES" "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
