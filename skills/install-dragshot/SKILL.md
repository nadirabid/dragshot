---
name: install-dragshot
description: >-
  Install or upgrade DragShot from its repository checkout: build and sign the
  macOS app, install it, install the dsh-dragshot Cordis bridge, enable DSH
  sending, and hand off the Trackpad and privacy permission steps. Use when the
  user asks to install, set up, or upgrade DragShot from this repository.
---

# Install DragShot

Use this when the user asks to install or upgrade DragShot from a checkout of
this repository.

## Before you start

- Confirm the checkout path if it is not the current directory.
- Ask which directory new DSH chats should use as their default workspace unless
  the user already named one. Do not silently choose `$HOME`.
- Do not create signing certificates or enter keys. If the build falls back to
  ad-hoc signing, tell the user that permissions may need regranting after a
  rebuild.

## Get the checkout

If this skill is already linked at `~/.dsh/skills/install-dragshot`, resolve the
checkout from it:

```sh
SKILL="$HOME/.dsh/skills/install-dragshot"
SKILL_DIR="$(cd "$SKILL" && pwd -P)"
REPO="$(cd "$SKILL_DIR/../.." && pwd -P)"
```

If you were given only this skill file, clone the repository into a temporary
directory:

```sh
REPO="$(mktemp -d /tmp/dragshot-install.XXXXXX)"
git clone --depth 1 https://github.com/nadirabid/dragshot.git "$REPO"
```

If the checkout is somewhere else, ask the user for its path.

## Install

Run the wrapper from that checkout:

```sh
"$REPO/skills/install-dragshot/scripts/install.sh" --repo "$REPO" --workspace "<workspace>"
```

The installer builds, signs, installs the app, installs the Cordis bridge,
enables DSH sending, and opens DragShot. It is safe to rerun for an upgrade.

## Finish

1. Grant **Screen Recording** and **Accessibility** when DragShot prompts. On
   macOS 27, Accessibility is labelled **Device Control and Data Access**. The
   app's menu status should show both permissions ready.
2. Enable three-finger drag in **System Settings → Accessibility → Pointer
   Control → Trackpad Options**: use the trackpad for dragging, and choose
   Three Finger Drag.
3. Confirm **Send captures to DSH** is on and the bridge says **Connected** in
   DragShot's menu bar menu. If it says the bridge is not loaded, restart DSH
   once and check again.
4. Make a test capture and report whether it arrives in the chosen DSH session.
   Do not claim success until the app is installed, permissions are ready, and
   the test capture arrives.

## Constraints

- Do not grant TCC permissions or change trackpad settings programmatically.
  Those are user actions.
- Do not run destructive commands outside the checkout and the installed
  DragShot app.
- Keep the workspace choice explicit.
