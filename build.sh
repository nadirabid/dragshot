#!/bin/bash
# Build Lookit.app without Xcode: swiftc + a hand-rolled bundle + a stable signature.
#
# The signature is the whole reason this script exists in this shape. macOS keys the Screen
# Recording and Accessibility grants to the app's code identity, and an ad-hoc signature has
# no identity to key to — it is just a hash of the binary, so every rebuild silently voids
# both grants and costs a trip to System Settings. Signing with a real local certificate
# gives a stable identity that survives rebuilds.
#
# Create the certificate once (see DEVELOPMENT.md) and the default below finds it.
# Passing LOOKIT_SIGN_ID=- falls back to ad-hoc, which is fine for a build you
# never have to grant.
set -euo pipefail

command -v xcrun >/dev/null 2>&1 || {
  echo "error: xcrun is required. Install Xcode Command Line Tools." >&2
  exit 1
}

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lookit.app"
SOURCES=("$ROOT"/Sources/*.swift)
SWIFT_FLAGS=(-O -whole-module-optimization)
BUNDLE_ID=local.lookit
if [ "${1:-}" = "--tests" ]; then
  APP="$ROOT/build/tests/Lookit.app"
  SOURCES+=("$ROOT"/tests/*.swift)
  SWIFT_FLAGS+=(-D LOOKIT_TESTING)
  BUNDLE_ID=local.lookit.tests
fi
SWIFTC="${LOOKIT_SWIFTC:-$(xcrun --find swiftc)}"
TARGET="${LOOKIT_TARGET:-$(uname -m)-apple-macos26.0}"
SIGN_ID="${LOOKIT_SIGN_ID:-Lookit Local Signing}"
# Renaming the product does not require renaming its signing certificate. Reuse
# the original identity on existing developer machines instead of losing TCC grants.
if [ -z "${LOOKIT_SIGN_ID:-}" ]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if ! grep -qF '"Lookit Local Signing"' <<< "$IDENTITIES" \
     && grep -qF '"DragShot Local Signing"' <<< "$IDENTITIES"; then
    SIGN_ID="DragShot Local Signing"
  fi
fi

if [ ! -x "$SWIFTC" ]; then
  echo "error: Swift compiler not found: $SWIFTC" >&2
  echo "       install Xcode Command Line Tools." >&2
  exit 1
fi

# Command Line Tools can ship an SDK newer than the bundled compiler. Probe the
# available SDKs with this exact compiler and target instead of hardcoding one.
PROBE="/tmp/lookit-sdk-probe-$$.swift"
printf 'import Foundation\n' > "$PROBE"
trap 'rm -f "$PROBE"' EXIT
try_sdk() {
  [ -d "$1" ] && "$SWIFTC" -sdk "$1" -target "$TARGET" -typecheck "$PROBE" >/dev/null 2>&1
}

if [ -n "${LOOKIT_SDK:-}" ]; then
  if ! try_sdk "$LOOKIT_SDK"; then
    echo "error: SDK does not work with this compiler: $LOOKIT_SDK" >&2
    exit 1
  fi
  SDK="$LOOKIT_SDK"
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
    echo "       Install matching Xcode Command Line Tools, or set LOOKIT_SDK." >&2
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
  -o "$APP/Contents/MacOS/Lookit" \
  "${SWIFT_FLAGS[@]}" "${SOURCES[@]}"

echo "==> bundling"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
if [ "$BUNDLE_ID" = local.lookit.tests ]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Lookit Tests' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Lookit Tests' "$APP/Contents/Info.plist"
fi
# Brand images and any other flat resources.
if compgen -G "$ROOT/Sources/*.png" > /dev/null; then
  cp "$ROOT"/Sources/*.png "$APP/Contents/Resources/"
fi
cp "$ROOT/assets/Lookit.icns" "$APP/Contents/Resources/Lookit.icns"

echo "==> signing (identity: $SIGN_ID)"
codesign --force --deep --sign "$SIGN_ID" \
  --identifier "$BUNDLE_ID" \
  "$APP" 2>&1 | sed 's/^/    /'

echo "==> verifying"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo
echo "built: $APP"
echo
echo "install:  ./install.sh (then open /Applications/Lookit.app)"
echo "dev:      open '$APP' --args --development"
echo "          open '$APP' --args --development --hotkey # also arms Command-Shift-4 as a trigger"
echo "log:      tail -f ~/Library/Logs/Lookit.log"
echo "captures: ~/Pictures/Lookit"
