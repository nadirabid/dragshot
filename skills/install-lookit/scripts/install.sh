#!/bin/bash
# Thin source-build wrapper. Installation and preferences have one owner.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
WORKSPACE="$PWD"
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?Missing repository}"; shift 2 ;;
    --workspace) WORKSPACE="${2:?Missing workspace}"; shift 2 ;;
    --no-open|--allow-signing-change) ARGS+=("$1"); shift ;;
    *) echo 'Usage: install.sh [--repo DIR] [--workspace DIR] [--no-open] [--allow-signing-change]' >&2; exit 1 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo 'Lookit requires macOS.' >&2; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || { echo 'Lookit requires macOS 26 or later.' >&2; exit 1; }
[ -d "$WORKSPACE" ] || { echo 'Workspace is not a directory.' >&2; exit 1; }
"$REPO/build.sh"
exec "$REPO/install.sh" --workspace "$WORKSPACE" "${ARGS[@]}"
