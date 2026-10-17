#!/bin/bash
# Build DragShot.app without Xcode: swiftc + a hand-rolled bundle + a stable signature.
#
# The signature is the whole reason this script exists in this shape. macOS keys the Screen
# Recording and Accessibility grants to the app's code identity, and an ad-hoc signature has
# no identity to key to — it is just a hash of the binary, so every rebuild silently voids
# both grants and costs a trip to System Settings. Signing with a real local certificate
# gives a stable identity that survives rebuilds.
#
# Create the certificate once (see README) and the default below finds it. Passing
# DRAGSHOT_SIGN_ID=- falls back to ad-hoc, which is fine for a build you never have to grant.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DragShot.app"
SOURCES=("$ROOT"/Sources/*.swift)
SWIFT_FLAGS=(-O -whole-module-optimization)
if [ "${1:-}" = "--tests" ]; then
  APP="$ROOT/build/tests/DragShot.app"
  SOURCES+=("$ROOT"/tests/*.swift)
  SWIFT_FLAGS+=(-D DRAGSHOT_TESTING)
fi
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
TARGET="arm64-apple-macos26.0"
SIGN_ID="${DRAGSHOT_SIGN_ID:-DragShot Local Signing}"

if [ "$SIGN_ID" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
  echo "warning: signing identity '$SIGN_ID' not found; falling back to ad-hoc."
  echo "         Ad-hoc builds lose Screen Recording and Accessibility on every rebuild."
  SIGN_ID="-"
fi

if [ ! -d "$SDK" ]; then
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
  echo "note: falling back to SDK $SDK"
fi

echo "==> cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling"
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -framework Cocoa \
  -framework ScreenCaptureKit \
  -framework ApplicationServices \
  -framework ImageIO \
  -o "$APP/Contents/MacOS/DragShot" \
  "${SWIFT_FLAGS[@]}" "${SOURCES[@]}"

echo "==> bundling"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "==> signing (identity: $SIGN_ID)"
codesign --force --deep --sign "$SIGN_ID" \
  --identifier local.dragshot \
  "$APP" 2>&1 | sed 's/^/    /'

echo "==> verifying"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo
echo "built: $APP"
echo
echo "run:      open '$APP'                 # no debug trigger"
echo "          open '$APP' --args --hotkey # also arms Command-Shift-4 as a trigger"
echo "log:      tail -f ~/Library/Logs/DragShot.log"
echo "captures: ~/Pictures/DragShot"
