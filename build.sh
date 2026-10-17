#!/bin/bash
# Build DragShot.app without Xcode: swiftc + a hand-rolled bundle + a stable signature.
#
# The signature is the whole reason this script exists in this shape. macOS keys the Screen
# Recording and Accessibility grants to the app's code identity, and an ad-hoc signature has
# no identity to key to — it is just a hash of the binary, so every rebuild silently voids
# both grants and costs a trip to System Settings. Signing with a real local certificate
# gives a stable identity that survives rebuilds.
#
# Create the certificate once (see DEVELOPMENT.md) and the default below finds it.
# Passing DRAGSHOT_SIGN_ID=- falls back to ad-hoc, which is fine for a build you
# never have to grant.
set -euo pipefail

command -v xcrun >/dev/null 2>&1 || {
  echo "error: xcrun is required. Install Xcode Command Line Tools." >&2
  exit 1
}

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DragShot.app"
SOURCES=("$ROOT"/Sources/*.swift)
SWIFT_FLAGS=(-O -whole-module-optimization)
if [ "${1:-}" = "--tests" ]; then
  APP="$ROOT/build/tests/DragShot.app"
  SOURCES+=("$ROOT"/tests/*.swift)
  SWIFT_FLAGS+=(-D DRAGSHOT_TESTING)
fi
SWIFTC="${DRAGSHOT_SWIFTC:-$(xcrun --find swiftc)}"
TARGET="${DRAGSHOT_TARGET:-$(uname -m)-apple-macos26.0}"
SIGN_ID="${DRAGSHOT_SIGN_ID:-DragShot Local Signing}"

if [ ! -x "$SWIFTC" ]; then
  echo "error: Swift compiler not found: $SWIFTC" >&2
  echo "       install Xcode Command Line Tools." >&2
  exit 1
fi

# Command Line Tools can ship an SDK newer than the bundled compiler. Probe the
# available SDKs with this exact compiler and target instead of hardcoding one.
PROBE="/tmp/dragshot-sdk-probe-$$.swift"
printf 'import Foundation\n' > "$PROBE"
trap 'rm -f "$PROBE"' EXIT
try_sdk() {
  [ -d "$1" ] && "$SWIFTC" -sdk "$1" -target "$TARGET" -typecheck "$PROBE" >/dev/null 2>&1
}

if [ -n "${DRAGSHOT_SDK:-}" ]; then
  if ! try_sdk "$DRAGSHOT_SDK"; then
    echo "error: SDK does not work with this compiler: $DRAGSHOT_SDK" >&2
    exit 1
  fi
  SDK="$DRAGSHOT_SDK"
else
  CANDIDATES=()
  DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  [ -n "$DEFAULT_SDK" ] && CANDIDATES+=("$DEFAULT_SDK")
  while IFS= read -r sdk; do CANDIDATES+=("$sdk"); done < <(
    ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -r
  )
  DEVELOPER="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "$DEVELOPER" ] && [ -d "$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs" ]; then
    while IFS= read -r sdk; do CANDIDATES+=("$sdk"); done < <(
      ls -d "$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX"*.sdk 2>/dev/null | sort -r
    )
  fi
  SDK=""
  for candidate in "${CANDIDATES[@]}"; do
    if try_sdk "$candidate"; then SDK="$candidate"; break; fi
  done
  if [ -z "$SDK" ]; then
    echo "error: no macOS SDK works with this Swift compiler." >&2
    echo "       Install matching Xcode Command Line Tools, or set DRAGSHOT_SDK." >&2
    exit 1
  fi
fi

if [ "$SIGN_ID" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
  echo "warning: signing identity '$SIGN_ID' not found; falling back to ad-hoc."
  echo "         Ad-hoc builds lose Screen Recording and Accessibility on every rebuild."
  SIGN_ID="-"
fi

echo "==> cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling (target $TARGET, SDK $SDK)"
"$SWIFTC" \
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
# Brand images and any other flat resources.
if compgen -G "$ROOT/Sources/*.png" > /dev/null; then
  cp "$ROOT"/Sources/*.png "$APP/Contents/Resources/"
fi

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
