#!/bin/bash
# Report Lookit's running state without changing permissions or trackpad settings.
#
# The app writes this file itself, so the TCC answers belong to Lookit rather
# than to the shell running this script.
set -u

usage() {
  cat <<'EOF'
usage: diagnose.sh [--app /Applications/Lookit.app]

Reads ~/Library/Application Support/Lookit/diagnostics.txt and prints the
permission, event tap, trackpad, and DSH bridge state. It does not grant
permissions or modify settings.
EOF
}

APP="${LOOKIT_APP:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      APP="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ -z "$APP" ]; then
  for candidate in \
    "/Applications/Lookit.app" \
    "$HOME/Applications/Lookit.app" \
    "$HOME/Documents/DeepSeek/lookit/build/Lookit.app"; do
    if [ -d "$candidate" ]; then APP="$candidate"; break; fi
  done
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "error: Lookit.app was not found." >&2
  echo "       pass --app /Applications/Lookit.app" >&2
  exit 1
fi
APP="$(cd "$APP" && pwd -P)"
BIN="$APP/Contents/MacOS/Lookit"
DIAG="$HOME/Library/Application Support/Lookit/diagnostics.txt"
LOG="$HOME/Library/Logs/Lookit.log"
BRIDGE="$HOME/Library/Application Support/Lookit/dsh-bridge.json"
SOCK="$HOME/Library/Application Support/Lookit/dsh.sock"

RUNNING=no
if pgrep -f "$BIN" >/dev/null 2>&1; then RUNNING=yes; fi

# The app writes diagnostics shortly after launch. Give it a moment.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$DIAG" ] && break
  sleep 0.5
done

value() {
  awk -F': ' -v key="$1" '$1 == key { print $2; exit }' "$DIAG" 2>/dev/null
}

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$APP/Contents/Info.plist" 2>/dev/null || true)"

printf 'Lookit diagnostics\n'
printf '  app: %s\n' "$APP"
printf '  bundle: %s\n' "${bundle_id:-unknown}"
printf '  running: %s\n' "$RUNNING"

if [ ! -s "$DIAG" ]; then
  printf '  diagnostics: missing\n'
  echo
  if [ "$RUNNING" = no ]; then
    echo "Lookit is not running. Open it and run this again:"
    echo "  open \"$APP\""
  else
    echo "Lookit is running but has not written diagnostics yet."
    echo "Quit and reopen it, then run this again."
    echo "  osascript -e 'quit app \"Lookit\"'; sleep 1; open \"$APP\""
  fi
  if [ -f "$LOG" ]; then
    echo
    echo "Last Lookit log lines:"
    tail -n 8 "$LOG"
  fi
  exit 1
fi

if [ "$bundle_id" != "local.lookit" ]; then
  echo "  warning: expected bundle local.lookit, found ${bundle_id:-unknown}"
fi

updated="$(value updated)"
screen="$(value 'screen recording')"
access="$(value accessibility)"
tap="$(value 'event tap')"
touch="$(value multitouch)"
drag="$(value 'three-finger drag')"

# Older diagnostics, or a missing field, fall back to the system preference.
if [ "$drag" != enabled ] && [ "$drag" != disabled ]; then
  builtin="$(defaults read com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag 2>/dev/null || true)"
  bluetooth="$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag 2>/dev/null || true)"
  if [ "$builtin" = 1 ] || [ "$bluetooth" = 1 ]; then
    drag=enabled
  elif [ "$builtin" = 0 ] || [ "$bluetooth" = 0 ]; then
    drag=disabled
  else
    drag=unknown
  fi
fi

[ -n "$updated" ] && printf '  updated: %s\n' "$updated"
echo

FAIL=0
ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }

if [ "$screen" = true ]; then
  ok "Screen Recording"
else
  bad "Screen Recording (Lookit is not allowed to capture the screen)"
  FAIL=1
fi

if [ "$access" = true ]; then
  ok "Accessibility"
else
  bad "Accessibility (Lookit cannot install the global event tap)"
  FAIL=1
fi

if [ "$tap" = true ]; then
  ok "Event tap"
else
  bad "Event tap (starts at launch; relaunch after granting Accessibility)"
  FAIL=1
fi

if [ "$touch" = true ]; then
  ok "Trackpad reader"
else
  bad "Trackpad reader (MultitouchSupport is unavailable)"
  FAIL=1
fi

case "$drag" in
  enabled)  ok "Three-finger drag setting" ;;
  disabled) bad "Three-finger drag setting is off"; FAIL=1 ;;
  *)        warn "Three-finger drag setting is unknown"; FAIL=1 ;;
esac

if [ -f "$BRIDGE" ] && [ -S "$SOCK" ]; then
  ok "DSH bridge socket"
else
  warn "DSH bridge socket is not ready (DSH can still be used only after the bridge loads)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo
  echo "Core checks pass. Make a physical three-finger drag and verify a capture arrives."
  echo "If it does not, use Copy Diagnostics in Lookit's menu and check the log."
  exit 0
fi

cat <<EOF

Next steps:
  1. Screen Recording: open System Settings -> Privacy & Security -> Screen Recording,
     enable Lookit, then quit and reopen Lookit.
       open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  2. Accessibility: open System Settings -> Privacy & Security -> Accessibility
     (macOS 27: Device Control and Data Access), enable Lookit, then quit and reopen
     Lookit so the event tap is installed.
       open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  3. Three-finger drag: System Settings -> Accessibility -> Pointer Control ->
     Trackpad Options -> Use trackpad for dragging -> Three Finger Drag.
       open "x-apple.systempreferences:com.apple.preference.universalaccess"
  4. If the event tap is still unavailable after both grants and a relaunch, copy
     diagnostics from Lookit's menu and check:
       tail -n 30 "$LOG"

Use the diagnostics above, not \`--status\` from a shell: macOS can attribute that
process to the terminal instead of Lookit.
EOF
exit 1
