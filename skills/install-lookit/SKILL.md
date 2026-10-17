---
name: install-lookit
description: >-
  Install or upgrade Lookit from its repository checkout: build and sign the
  macOS app, install it, install the dsh-lookit Cordis bridge, enable DSH
  sending, and verify Screen Recording, Accessibility, the event tap, the
  Trackpad reader, the three-finger drag setting, and the bridge. Use when the
  user asks to install, set up, upgrade, or diagnose Lookit.
---

# Install Lookit

Use this when the user asks to install, upgrade, or diagnose Lookit from a
checkout of this repository.

## Before you start

- Confirm the checkout path if it is not the current directory.
- Ask which directory new DSH chats should use as their default workspace unless
  the user already named one. Do not silently choose `$HOME`.
- Do not create signing certificates or enter keys. If the build falls back to
  ad-hoc signing, tell the user that permissions may need regranting after a
  rebuild.
- Use the app's diagnostics file, not `--status` from a shell. macOS can
  attribute a command-line launch to the terminal, so its TCC answers may not
  describe the running Lookit app.

## Get the checkout

If this skill is already linked at `~/.dsh/skills/install-lookit`, resolve the
checkout from it:

```sh
SKILL="$HOME/.dsh/skills/install-lookit"
SKILL_DIR="$(cd "$SKILL" && pwd -P)"
REPO="$(cd "$SKILL_DIR/../.." && pwd -P)"
```

If you were given only this skill file, clone the repository into a temporary
directory:

```sh
REPO="$(mktemp -d /tmp/lookit-install.XXXXXX)"
git clone --depth 1 https://github.com/nadirabid/lookit.git "$REPO"
```

If the checkout is somewhere else, ask the user for its path.

## Install

Run the wrapper from that checkout:

```sh
"$REPO/skills/install-lookit/scripts/install.sh" --repo "$REPO" --workspace "<workspace>"
```

The installer builds, signs, installs the app, installs the Cordis bridge,
enables DSH sending, opens Lookit, and prints the app's diagnostics. It is safe
to rerun for an upgrade.

## Verify permissions and gesture

Run the diagnostics against the installed app (use the path the installer
printed; normally `/Applications/Lookit.app`):

```sh
"$REPO/skills/install-lookit/scripts/diagnose.sh" --app "/Applications/Lookit.app"
```

The script reads the file written by the running app:
`~/Library/Application Support/Lookit/diagnostics.txt`. Required core state:

- **Screen Recording**: `true`
- **Accessibility**: `true`
- **Event tap**: `running`
- **Trackpad reader**: `running`
- **Three-finger drag setting**: `enabled`

Do not treat the install as verified until these pass and the user has made a
physical test capture.

If a check fails, open Lookit's guided setup first:

```sh
open /Applications/Lookit.app --args --setup
```

If Lookit is already running, use **Configure Permissions…** in its menu instead. The guide
shows live status, opens the relevant Settings pane, and provides a draggable app tile for
adding the installed Lookit app to the list. Input Monitoring is checked separately; a working
event tap satisfies that step without an extra grant. Always launch the installed copy, not
the build directory. Use its **Restart Lookit** button if macOS requires a relaunch.

For manual diagnosis, fix checks in this order and rerun the script:

1. **Screen Recording is false.** Open System Settings → Privacy & Security →
   Screen Recording, enable Lookit, then quit and reopen Lookit.
   ```sh
   open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
   ```
2. **Accessibility is false.** Open System Settings → Privacy & Security →
   Accessibility. On macOS 27 this is **Device Control and Data Access**. Enable
   Lookit, then quit and reopen it; the event tap attaches when the new grant is detected.
   ```sh
   open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
   ```
3. **Event tap is false while both grants are true.** Check Input Monitoring in
   the setup guide, then quit and reopen Lookit once. If it is still false, use **Copy Diagnostics** in Lookit's menu and
   check `~/Library/Logs/Lookit.log`; do not guess.
4. **Three-finger drag setting is disabled or unknown.** System Settings →
   Accessibility → Pointer Control → Trackpad Options → Use trackpad for
   dragging → **Three Finger Drag**. The setting is global, not per-app; Lookit
   reads the raw trackpad contacts and needs the event tap for the gesture.
   Quit and reopen Lookit after changing it.
   ```sh
   open "x-apple.systempreferences:com.apple.preference.universalaccess?Mouse"
   ```
5. **Trackpad reader is unavailable.** Check the log and copy diagnostics. Do
   not promise three-finger capture; report the failure plainly.
6. **DSH bridge socket is missing.** Restart DSH once, then rerun the bridge
   installer from `"$REPO/dsh-lookit/install.sh"`. The app still captures
   locally while the bridge is absent.

The Settings window shows permission and gesture status under **Permissions**.
**General** includes launch at login, the captures folder, **Copy Diagnostics**,
**Reveal Diagnostics**, **Reveal Log**, and Quit. The menu bar contains only
Settings, Configure Permissions, Launch at Login, and Quit. The explicit
`--request-permissions` launch argument opens the setup guide without raising
system permission prompts.

## Physical test

Ask the user to drag three fingers across a region. Confirm that the composer
opens, then make a capture and check that a new PNG appears in
`~/Pictures/Lookit/` (and, when enabled, that it arrives in the chosen DSH
session). Do not claim success until the physical gesture and delivery work.

## If something goes wrong

- Run `diagnose.sh` again and report the exact failing lines.
- Read the latest lines of `~/Library/Logs/Lookit.log`; the app logs the
  Multitouch reader, event tap, permissions, and three-finger setting at launch.
- Use **Copy Diagnostics** in Lookit's menu for a complete local report. It
  contains no captures or note text.
- If the app is not running, open it and rerun. If diagnostics are missing,
  quit and reopen the app before checking the log.

## Constraints

- Do not grant TCC permissions or change trackpad settings programmatically.
  Those are user actions.
- Do not run destructive commands outside the checkout and the installed
  Lookit app.
- Keep the workspace choice explicit.
- Do not claim success from installation alone; verify the diagnostics and the
  physical test capture.
