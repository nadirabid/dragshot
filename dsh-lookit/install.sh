#!/bin/bash
# Install the Lookit bridge into a DSH profile without touching the app bundle.
#
# DSH resolves plugins from ~/.dsh/profiles/node_modules. The desktop profile's
# own patch layer inserts this row by package name. HMR watches that patch, so
# an already-running desktop usually loads the bridge without a restart; if the
# discovery file does not appear, restart DSH once.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE_VALUE="${DSH_PROFILE:-desktop}"
case "$PROFILE_VALUE" in
  /*) PROFILE="$PROFILE_VALUE" ;;
  *) PROFILE="$DSH_HOME_DIR/profiles/$PROFILE_VALUE" ;;
esac
PROFILE_MODULES="$DSH_HOME_DIR/profiles/node_modules"
DEFAULT_CWD="${1:-$(pwd)}"

if [ ! -d "$PROFILE" ]; then
  echo "error: DSH profile not found: $PROFILE" >&2
  echo "       Set DSH_PROFILE to the profile directory to use." >&2
  exit 1
fi
if [ ! -d "$DEFAULT_CWD" ]; then
  echo "error: default cwd is not a directory: $DEFAULT_CWD" >&2
  exit 1
fi

echo "==> linking plugin"
mkdir -p "$PROFILE_MODULES"
ln -sfn "$ROOT" "$PROFILE_MODULES/dsh-lookit"

# The plugin imports @deepseek-ai/schemastery. Node resolves that from the
# plugin's real path, so give it the same local link dsh-self uses.
if [ -d "$PROFILE_MODULES/@deepseek-ai/schemastery" ]; then
  mkdir -p "$ROOT/node_modules/@deepseek-ai"
  ln -sfn "$PROFILE_MODULES/@deepseek-ai/schemastery" \
    "$ROOT/node_modules/@deepseek-ai/schemastery"
fi

PATCH="$PROFILE/cordis.patch.yml"
touch "$PATCH"
if grep -q 'id: lookit-bridge' "$PATCH"; then
  echo "==> profile already contains lookit-bridge"
else
  echo "==> appending lookit-bridge to $PATCH"
  cp "$PATCH" "$PATCH.bak.$(date +%Y%m%d-%H%M%S)"
  cat >> "$PATCH" <<EOF

# Lookit capture bridge. Local Unix socket, owner-only; no TCP port.
- insert:
    - id: lookit-bridge
      name: dsh-lookit
      config:
        enabled: true
        defaultCwd: "$DEFAULT_CWD"
EOF
fi

echo
echo "installed:"
echo "  plugin:    $PROFILE_MODULES/dsh-lookit"
echo "  profile:   $PATCH"
echo "  default:   $DEFAULT_CWD"
echo "  socket:    $HOME/Library/Application Support/Lookit/dsh.sock"
echo "  discovery: $HOME/Library/Application Support/Lookit/dsh-bridge.json"
echo
echo "If DSH is already running, its HMR watcher normally loads the new row."
echo "If the discovery file does not appear, restart DSH once:"
echo "  osascript -e 'quit app \"DeepSeek Harness\"'; sleep 2; open -a 'DeepSeek Harness'"
