#!/bin/bash
# Install DragShot and its DSH bridge from this repository.
#
# This is intentionally a thin wrapper around the app's build/install scripts and
# the bridge installer. It is safe to rerun after a git pull to upgrade.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: install.sh [--workspace DIR] [--repo DIR]

  --workspace DIR  default cwd for new DSH sessions (default: current directory)
  --repo DIR       DragShot checkout (default: resolved from this skill's path)
EOF
}

WORKSPACE="$PWD"
REPO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      WORKSPACE="$2"; shift 2 ;;
    --repo)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      REPO="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ -z "$REPO" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
  REPO="$(cd "$SKILL_DIR/../.." && pwd -P)"
fi

if [ ! -x "$REPO/build.sh" ] || [ ! -x "$REPO/install.sh" ] \
   || [ ! -x "$REPO/dsh-dragshot/install.sh" ]; then
  echo "error: $REPO does not look like a DragShot checkout" >&2
  echo "       pass --repo /path/to/dragshot" >&2
  exit 1
fi
if [ "$(uname -s)" != Darwin ]; then
  echo "error: DragShot is macOS-only" >&2
  exit 1
fi
if [ "$(uname -m)" != arm64 ]; then
  echo "error: the build requires Apple silicon" >&2
  exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 26 ]; then
  echo "error: macOS 26 or later is required" >&2
  exit 1
fi
if [ ! -d "$WORKSPACE" ]; then
  echo "error: workspace is not a directory: $WORKSPACE" >&2
  exit 1
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd -P)"

echo "==> building DragShot"
( cd "$REPO" && ./build.sh )

echo "==> installing DragShot to /Applications"
( cd "$REPO" && ./install.sh )

DSH_BRIDGE_READY=0
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE_VALUE="${DSH_PROFILE:-desktop}"
case "$PROFILE_VALUE" in
  /*) PROFILE="$PROFILE_VALUE" ;;
  *) PROFILE="$DSH_HOME_DIR/profiles/$PROFILE_VALUE" ;;
esac
if [ -d "$PROFILE" ]; then
  echo "==> installing the DSH bridge"
  if ( cd "$REPO/dsh-dragshot" && ./install.sh "$WORKSPACE" ); then
    DSH_BRIDGE_READY=1
    defaults write local.dragshot dsh.enabled -bool true
    defaults write local.dragshot dsh.target -string recent
    defaults delete local.dragshot dsh.targetSessionID 2>/dev/null || true
    defaults delete local.dragshot dsh.targetSessionTitle 2>/dev/null || true
  else
    echo "warning: DSH bridge install failed; DragShot is installed without DSH sending." >&2
  fi
else
  echo "warning: no DSH profile found at $PROFILE; skipping the bridge." >&2
fi

DEST="/Applications/DragShot.app"
echo
echo "==> opening DragShot"
open "$DEST"

cat <<EOF

Installed: $DEST
Workspace: $WORKSPACE
DSH bridge: $([ "$DSH_BRIDGE_READY" -eq 1 ] && echo installed || echo "not installed")

Finish these user actions:
  1. Grant Screen Recording and Accessibility. On macOS 27, Accessibility is
     labelled Device Control and Data Access.
  2. Enable three-finger drag in System Settings -> Accessibility -> Pointer
     Control -> Trackpad Options.
  3. In DragShot's menu bar menu, confirm Send captures to DSH is on and the
     bridge says Connected. Restart DSH once if it still says not loaded.
EOF
