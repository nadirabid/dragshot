---
name: install-lookit
description: Build, install, upgrade, repair, and verify Lookit and its local DSH bridge without resetting user preferences.
---

# Install Lookit

Use the existing checkout and the workspace named by the user or unambiguously established in the current task. Ask only if either is unknown. Resolve this skill's checkout two directories above this file.

Run the single install workflow:

```sh
"$REPO/skills/install-lookit/scripts/install.sh" --repo "$REPO" --workspace "$WORKSPACE"
```

The wrapper builds and signs, then calls the root installer. It verifies the staged app before replacing the installed copy. Existing signing requirements must match; do not pass `--allow-signing-change` without an intentional signing migration. Do not create signing certificates or enter keys automatically.

The installer preserves preferences and existing bridge configuration. If a DSH desktop profile exists, it installs the bundled host and client into `~/Library/Application Support/Lookit/Integrations/dsh-lookit`, independently of the checkout and npm. An uninitialized DSH profile is left alone. After opening DSH for the first time, use Settings → Harnesses → Set Up / Repair Bridge. Do not forcibly restart DSH while work is running.

## Verify

The default install launches the installed app and checks its fresh diagnostics, process, permissions, gesture listener, and selected DSH bridge's live handshake and UI heartbeat. Exit status 2 means installed but setup still needs attention; report the exact remaining checks. `--no-open` skips readiness verification and must not be reported as ready.

```sh
"$REPO/skills/install-lookit/scripts/diagnose.sh" --app "/Applications/Lookit.app"
```

Use app-written diagnostics, not a shell-launched `--status` process whose macOS permissions may differ. Open Lookit Settings → Permissions for guided permission grants and the draggable installed-app tile. macOS permission grants and the system three-finger drag setting require the user. Never modify TCC programmatically. Use General → Copy Diagnostics / Reveal Log for investigation.

Distinguish automated readiness from physical gesture and delivery validation. A physical three-finger capture must still be tested. Validate the chosen destination visibly; a bridge acknowledgement alone is not proof that the image arrived on screen.

## Regression and live tests

```sh
python3 -m unittest discover -s tests -p 'test_install.py' -v
node --test dsh-lookit/test/*.test.mjs
./build.sh --tests
build/tests/Lookit.app/Contents/MacOS/Lookit --selftest
```

The optional `tests/live/run-dsh.sh --send-test` creates a real DSH chat. Run only when sending a test is authorized. It verifies the production sender and client selection; inspect the attachment and response for image receipt. Never claim this simulates physical trackpad input.
