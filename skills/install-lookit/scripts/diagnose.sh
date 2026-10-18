#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
if [ "$#" = 0 ]; then
  APP="$(defaults read local.lookit installedAppPath 2>/dev/null || true)"
  [ -n "$APP" ] || APP=/Applications/Lookit.app
  set -- --app "$APP"
fi
exec python3 "$REPO/scripts/check-install.py" "$@"
