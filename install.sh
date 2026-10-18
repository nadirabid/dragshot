#!/bin/bash
# One installation path for the app and an available DSH desktop profile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
SRC="$ROOT/build/Lookit.app"
WORKSPACE="$ROOT"
OPEN=1
ALLOW_SIGNING_CHANGE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="${2:?Missing workspace}"; shift 2 ;;
    --no-open) OPEN=0; shift ;;
    --allow-signing-change) ALLOW_SIGNING_CHANGE=1; shift ;;
    *) echo "Usage: ./install.sh [--workspace DIR] [--no-open] [--allow-signing-change]" >&2; exit 1 ;;
  esac
done
[ -d "$WORKSPACE" ] || { echo "Workspace is not a directory: $WORKSPACE" >&2; exit 1; }
[ -d "$SRC" ] || { echo 'Run ./build.sh first.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 from Command Line Tools is required for install verification.' >&2; exit 1; }
DEST_DIR="${LOOKIT_INSTALL_DIR:-/Applications}"
if [ "$DEST_DIR" = /Applications ] && [ ! -w "$DEST_DIR" ]; then DEST_DIR="$HOME/Applications"; fi
mkdir -p "$DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd -P)"
DEST="$DEST_DIR/Lookit.app"
[ "$SRC" != "$DEST" ] || { echo 'Build and installation directories must differ.' >&2; exit 1; }
[ ! -L "$DEST" ] || { echo "Installed app is a symlink; move it aside before installing: $DEST" >&2; exit 1; }
STAGE="$(mktemp -d "$DEST_DIR/.lookit-install.XXXXXX")"
PREVIOUS="$STAGE/Previous.app"
COMMITTED=0
cleanup() {
  if [ "$COMMITTED" = 0 ] && [ -d "$PREVIOUS" ]; then rm -rf "$DEST"; mv "$PREVIOUS" "$DEST"; fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
cp -R "$SRC" "$STAGE/Lookit.app"
codesign --verify --deep --strict "$STAGE/Lookit.app"
for file in install.sh package.json lib/index.js lib/bridge.js lib/client.js lib/navigation.js; do
  [ -s "$STAGE/Lookit.app/Contents/Resources/DSHBridge/$file" ] || {
    echo "Build is incomplete: bundled DSH bridge is missing $file. Rebuild Lookit." >&2; exit 1;
  }
done
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/Lookit.app/Contents/Info.plist")
[ "$BUNDLE" = local.lookit ] || { echo 'Refusing to install a test or unrelated app.' >&2; exit 1; }
if [ -d "$DEST" ] && [ "$ALLOW_SIGNING_CHANGE" = 0 ]; then
  OLD_REQUIREMENT="$(codesign -d -r- "$DEST" 2>&1 | sed -n 's/^\(# \)\{0,1\}designated => //p')"
  [ -n "$OLD_REQUIREMENT" ] && codesign --verify -R "=$OLD_REQUIREMENT" "$STAGE/Lookit.app" || {
    echo 'Signing identity changed. Existing app preserved. Use --allow-signing-change only if you intend to regrant macOS permissions.' >&2
    exit 1
  }
fi
# Install the self-contained bridge even on first installation, but do not
# initialize DSH profiles or change the chosen harness or target chat.
DSH_ROOT="${DSH_HOME:-$HOME/.dsh}"
PROFILE_VALUE="${DSH_PROFILE:-desktop}"
case "$PROFILE_VALUE" in /*) PROFILE="$PROFILE_VALUE" ;; *) PROFILE="$DSH_ROOT/profiles/$PROFILE_VALUE" ;; esac
if [ -d "$PROFILE" ]; then
  "$STAGE/Lookit.app/Contents/Resources/DSHBridge/install.sh" "$WORKSPACE"
else
  echo 'DSH profile not initialized. Local capture, Codex and Cursor remain available.'
  echo 'After opening DSH for the first time, rerun this installer to add its bridge.'
fi
# Stop only the copy being upgraded (and this checkout's development copy).
for pid in $(pgrep -x Lookit || true); do
  executable="$(ps -p "$pid" -o comm= || true)"
  if [ "$executable" = "$DEST/Contents/MacOS/Lookit" ] || [ "$executable" = "$SRC/Contents/MacOS/Lookit" ]; then
    kill "$pid"
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep .2
    done
    if kill -0 "$pid" 2>/dev/null; then echo 'Lookit did not quit; existing installation preserved.' >&2; exit 1; fi
  fi
done
[ ! -d "$DEST" ] || mv "$DEST" "$PREVIOUS"
mv "$STAGE/Lookit.app" "$DEST"
codesign --verify --deep --strict "$DEST"
COMMITTED=1
LSREGISTER="${LOOKIT_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$SRC" 2>/dev/null || true
  "$LSREGISTER" -u "$ROOT/build/tests/Lookit.app" 2>/dev/null || true
  "$LSREGISTER" -f "$DEST"
fi
defaults write local.lookit installedAppPath -string "$DEST"
if [ "$OPEN" = 1 ]; then
  open "$DEST" --args --setup
  python3 "$ROOT/scripts/check-install.py" --app "$DEST" --wait 8
else
  echo "Installed: $DEST"
  echo 'Readiness not checked (--no-open). Open Lookit Settings to finish setup.'
fi
