#!/bin/bash
# Install Lookit to /Applications (or ~/Applications) as a real copy, not a symlink.
#
# The system permission dialogs name the app by its path, and a symlink keeps reporting the
# path it points at — which makes the thing you granted in System Settings hard to match to
# the thing you launched. A real copy keeps the two in agreement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/build/Lookit.app"
DEST_DIR="${LOOKIT_INSTALL_DIR:-/Applications}"
if [ ! -w "$DEST_DIR" ] && [ "$DEST_DIR" = "/Applications" ]; then
  DEST_DIR="$HOME/Applications"
  echo "note: /Applications is not writable; using $DEST_DIR"
fi
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/Lookit.app"

[ -d "$SRC" ] || { echo "no build at $SRC — run ./build.sh first"; exit 1; }

echo "==> quitting any running copy"
pkill -f "Lookit.app/Contents/MacOS/Lookit" 2>/dev/null || true
sleep 1

echo "==> installing to $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
codesign --verify "$DEST" 2>&1 | sed 's/^/    /'

# Remove stale development registrations and make the installed path authoritative.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$SRC" 2>/dev/null || true
  "$LSREGISTER" -u "$ROOT/build/tests/Lookit.app" 2>/dev/null || true
  "$LSREGISTER" -f "$DEST"
fi
defaults write local.lookit installedAppPath -string "$DEST"
echo
echo "installed: $DEST"
echo "run:       open $DEST"
echo
echo "Setup checks access live. If macOS requires a relaunch, use Restart Lookit in setup."
