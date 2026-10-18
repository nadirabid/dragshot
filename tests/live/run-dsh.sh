#!/bin/bash
set -euo pipefail
if [ "${1:-}" != --send-test ]; then
  echo 'Pass --send-test to create one real DSH test chat and verify navigation.'
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${LOOKIT_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p "$ROOT/build/live"
swiftc -parse-as-library -sdk "$SDK" -target arm64-apple-macos26.0 \
  "$ROOT/Sources/DSHIntegration.swift" "$ROOT/Sources/Storage.swift" \
  "$ROOT/Sources/Notice.swift" "$ROOT/Sources/Log.swift" \
  "$ROOT/tests/live/DSHSend.swift" -o "$ROOT/build/live/lookit-dsh-test"
"$ROOT/build/live/lookit-dsh-test" --send-test
