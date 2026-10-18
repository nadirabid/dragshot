#!/bin/bash
# Dependency-free host/client payload, installed independently of the checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE_VALUE="${DSH_PROFILE:-desktop}"
case "$PROFILE_VALUE" in /*) PROFILE="$PROFILE_VALUE" ;; *) PROFILE="$DSH_HOME_DIR/profiles/$PROFILE_VALUE" ;; esac
MODULES="$DSH_HOME_DIR/profiles/node_modules"
SUPPORT="${LOOKIT_SUPPORT_DIR:-$HOME/Library/Application Support/Lookit}"
DEST="$SUPPORT/Integrations/dsh-lookit"
WORKSPACE="${1:-$PWD}"
PATCH="$PROFILE/cordis.patch.yml"
[ -d "$PROFILE" ] || { echo "DSH profile is not initialized: $PROFILE" >&2; exit 1; }
[ -d "$WORKSPACE" ] || { echo "Workspace does not exist: $WORKSPACE" >&2; exit 1; }
WORKSPACE="$(cd "$WORKSPACE" && pwd -P)"
case "$WORKSPACE" in *$'\n'*|*$'\r'*) echo 'Workspace path must not contain a newline.' >&2; exit 1;; esac
for file in package.json lib/index.js lib/bridge.js lib/client.js lib/navigation.js; do
  [ -s "$ROOT/$file" ] || { echo "Bridge payload is incomplete: $file" >&2; exit 1; }
done
# Never replace an unmanaged real package directory.
[ ! -e "$MODULES/dsh-lookit" ] || [ -L "$MODULES/dsh-lookit" ] || {
  echo "An unmanaged package exists at $MODULES/dsh-lookit; leaving it untouched." >&2; exit 1;
}
mkdir -p "$SUPPORT/Integrations" "$MODULES"
[ ! -e "$PATCH" ] || [ -w "$PATCH" ] || { echo "DSH profile is not writable: $PATCH" >&2; exit 1; }
STAGE="$(mktemp -d "$SUPPORT/Integrations/.lookit-stage.XXXXXX")"
PATCH_STAGE="$(mktemp "$PROFILE/.lookit-patch.XXXXXX")"
BACKUP=""
COMMITTED=0
PUBLISHED=0
OLD_LINK="$(readlink "$MODULES/dsh-lookit" || true)"
cleanup() {
  if [ "$COMMITTED" = 0 ]; then
    if [ "$PUBLISHED" = 1 ]; then rm -rf "$DEST"; fi
    if [ -n "$BACKUP" ]; then mv "$BACKUP" "$DEST"; fi
    if [ "$PUBLISHED" = 1 ]; then
      rm -f "$MODULES/dsh-lookit"
      if [ -n "$OLD_LINK" ]; then ln -s "$OLD_LINK" "$MODULES/dsh-lookit"; fi
    fi
  fi
  rm -rf "$STAGE"
  rm -f "$PATCH_STAGE"
}
trap cleanup EXIT
cp "$ROOT/package.json" "$STAGE/"
cp -R "$ROOT/lib" "$STAGE/lib"
chmod -R u+rwX,go-rwx "$STAGE"
[ ! -f "$PATCH" ] || cp "$PATCH" "$PATCH_STAGE"
# Upgrade the former managed product row without introducing a second bridge.
sed -E 's/(id: *)dragshot-bridge([[:space:]]*)$/\1lookit-bridge\2/; s/(name: *)dsh-dragshot([[:space:]]*)$/\1dsh-lookit\2/' "$PATCH_STAGE" > "$PATCH_STAGE.next"
mv "$PATCH_STAGE.next" "$PATCH_STAGE"
if ! grep -Eq '^[[:space:]-]*id:[[:space:]]*lookit-bridge[[:space:]]*$' "$PATCH_STAGE"; then
  ESCAPED="$(printf '%s' "$WORKSPACE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat >> "$PATCH_STAGE" <<ROW

# Lookit capture bridge, managed by the Lookit installer.
- insert:
    - id: lookit-bridge
      name: dsh-lookit
      config:
        enabled: true
        defaultCwd: "$ESCAPED"
ROW
fi
# Do not let a development watcher keep pointing at a deleted checkout. Only
# replace single-root Lookit/DragShot watch rows; preserve other HMR settings.
ESCAPED_DEST="$(printf '%s' "$DEST" | sed 's/\\/\\\\/g; s/"/\\"/g')"
awk -v dest="$ESCAPED_DEST" '
  /^[[:space:]]*root: *\[ *"[^"]*\/dsh-(lookit|dragshot)" *\] *$/ {
    sub(/root:.*/, "root: [\"" dest "\"]")
  } { print }
' "$PATCH_STAGE" > "$PATCH_STAGE.next"
mv "$PATCH_STAGE.next" "$PATCH_STAGE"
# Retain the prior payload until profile publication succeeds.
if [ -e "$DEST" ]; then BACKUP="$DEST.previous.$$"; mv "$DEST" "$BACKUP"; fi
mv "$STAGE" "$DEST"
PUBLISHED=1
ln -sfn "$DEST" "$MODULES/dsh-lookit"
if [ -f "$PATCH" ]; then cp -p "$PATCH" "$PATCH.lookit-backup"; fi
mv "$PATCH_STAGE" "$PATCH"
COMMITTED=1
[ -z "$BACKUP" ] || rm -rf "$BACKUP"
printf 'DSH bridge installed: %s\n' "$DEST"
printf 'Profile: %s\n' "$PATCH"
printf 'Saved destinations and profile configuration preserved.\n'
