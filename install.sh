#!/bin/bash
# Install DragShot to /Applications as a real copy, not a symlink.
#
# The system permission dialogs name the app by its path, and a symlink keeps reporting the
# path it points at — which makes the thing you granted in System Settings hard to match to
# the thing you launched. A real copy keeps the two in agreement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/build/DragShot.app"
DEST="/Applications/DragShot.app"

[ -d "$SRC" ] || { echo "no build at $SRC — run ./build.sh first"; exit 1; }

echo "==> quitting any running copy"
pkill -f "DragShot.app/Contents/MacOS/DragShot" 2>/dev/null || true
sleep 1

echo "==> installing to $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
codesign --verify "$DEST" 2>&1 | sed 's/^/    /'

echo
echo "installed: $DEST"
echo "run:       open $DEST"
echo
echo "Grants are read at process start. If you just rebuilt, quit DragShot from its menu bar"
echo "icon and reopen it, or the old grant stays in effect until it restarts."
