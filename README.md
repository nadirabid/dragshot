# DragShot

A three-finger drag selects a screen region. Release to capture it and open an image-and-message composer.
Return saves the PNG and note to `~/Pictures/DragShot/` and copies the image to the clipboard.
Shift-Return inserts a new line; Escape cancels.

Return also sends to DeepSeek Harness when the DSH integration is enabled and the
`dsh-dragshot` host plugin is installed. Choose the destination from the composer's bottom
dock; it defaults to the most recent session. The capture is always saved locally and copied
to the clipboard first; DSH delivery is additive. Without the integration, Return behaves as
before.

## Interaction

The desktop stays live and unchanged during selection. A transparent window draws only a
system crosshair, a softly rounded outline, and a compact pixel-size readout. It never paints a replacement desktop.
A tap or movement under three points does not flash a selection overlay.

The drag is intercepted before it reaches the underlying app. Escape consumes the remainder
of that mouse sequence, so cancellation cannot leave another app dragging or selecting text.
The selection is confined to the display where the drag began. Lifting the last finger ends
selection immediately; DragShot consumes the system's delayed mouse-up without finishing twice.

On release, ScreenCaptureKit captures the selected region without DragShot's windows or
cursor. The selection outline disappears immediately and the composer takes typing focus,
while capture finishes asynchronously. The screenshot settles into a rounded attachment
preview above the message without moving the editor. Capture requests time out after four seconds.
Late results cannot reopen cancelled UI.

A native glass input panel takes keyboard focus without activating or switching apps.
It opens blank with a blinking cursor, follows the system appearance, and grows for multiline
instructions. Longer input scrolls within a bounded panel. The image preview preserves the
full screenshot's aspect ratio. Its brief arrival animation respects Reduce Motion; the
composer itself appears immediately, with no fade or capture wait. A subtle paper-plane
button and Return both submit the image and message through the existing local save/clipboard
pipeline.

Drag the composer's background or attachment to reposition it using native window dragging.
The message stays editable, and growing text preserves the position you chose.

Clicking or scrolling outside, losing typing focus (except while the session picker is open),
or switching apps or Spaces cancels both the input and selection. Outside interactions still
reach the app underneath. Clicking away during capture cancels the pending screenshot too.
Return immediately dismisses both
surfaces and saves as soon as the image is ready, preserving early submissions. A failed save
restores the composer and attachment for retry.

## DSH integration

DragShot can send the finished image and note into DSH. Choose the destination in the
composer's bottom dock: the searchable picker lists new and recent sessions, and the default
follows the newest session. The menu bar menu has the switch, a Most recent/New session
fallback, and the bridge status.

DSH runs a small Cordis host plugin, [`dsh-dragshot`](../dsh-dragshot), that owns a local
Unix socket. DragShot writes one JSON request to that socket; the plugin calls the live
`sessionController` in the DSH desktop host. This is necessary because the desktop app's
web server is token-gated and its ACP profile is a separate process that cannot attach to a
session the desktop app currently holds.

Install the plugin once:

    cd ../dsh-dragshot
    ./install.sh /path/to/default/workspace

If DSH is already running, its HMR watcher normally loads the new row. If the menu says
“DSH bridge: Not loaded”, restart DSH once:

    osascript -e 'quit app "DeepSeek Harness"'
    sleep 2
    open -a "DeepSeek Harness"

The plugin writes its discovery file and socket here:

    ~/Library/Application Support/DragShot/dsh-bridge.json
    ~/Library/Application Support/DragShot/dsh.sock

The composer's bottom dock shows “Send to [whale] DSH · <target>”. Click the chip to open the
searchable picker. New session is always first; recent rows show the workspace, age, and
running state. Choosing a row pins that session for subsequent captures; the menu's Most
recent session clears the pin. Search is focused when the picker opens, arrow keys and Return
work, and closing returns the cursor to the message field with the draft intact.

Shortcuts while composing: `⌘/` toggles the picker. A leading `/` in an empty message opens
it and is consumed; `/` after text stays literal.

Known limits:

- there is no screenshot-based routing heuristic yet;
- a newly created session is not auto-selected in the DSH window; DSH is activated and the
  session is visible in its sidebar, but selecting it still takes a click;
- the picker reads the session list when it opens and does not live-update while open;
- the bridge is local-only and trusts processes running as the same user.

## Trackpad setup

Enable:

    System Settings → Accessibility → Pointer Control → Trackpad Options
      Use trackpad for dragging: on
      Dragging style: Three Finger Drag

macOS supplies mouse coordinates and acceleration. The private MultitouchSupport framework
confirms three contacts and detects the final finger lift; ordinary mouse and one-finger drags pass through.
This setting changes the gestures available to Mission Control and Spaces.

## Permissions

| Grant | Why | Needed for |
|---|---|---|
| Screen Recording | read screen pixels | the selected region after release |
| Accessibility | watch the global mouse/keyboard stream | the three-finger trigger and the debug hotkey |

On **macOS 27 and later the Accessibility list is labelled "Device Control and Data Access"**
under Privacy & Security; it was called "Accessibility" up to macOS 26. The label changed, the
service did not: `tccutil` still calls it `Accessibility`, and the settings URL is still
`Privacy_Accessibility`. Screen Recording kept its own name and lives elsewhere in the same pane.

Run and grant permissions to the signed app through LaunchServices (`open` or Finder).
A binary launched directly from a shell may have a different permission context. Use the
app's menu to check readiness; the event tap and trackpad reader must also be running.

**A rebuild voids an ad-hoc signature's grants.** Ad-hoc signing has no identity, only a hash of
the binary, so every rebuild silently invalidated both grants. The build therefore signs with a
local certificate by default, which gives a real code identity:

    codesign -d -r- build/DragShot.app
    # designated => identifier "local.dragshot" and certificate leaf = H"520575..."

Create that certificate once, then the grants survive every rebuild:

    # 1. a self-signed code-signing certificate
    openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
      -subj "/CN=DragShot Local Signing" \
      -addext "basicConstraints=critical,CA:false" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning"
    openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 \
      -name "DragShot Local Signing" -passout pass:temppass

    # 2. into the login keychain, usable by codesign without a prompt
    security import identity.p12 -k ~/Library/Keychains/login.keychain-db \
      -P temppass -T /usr/bin/codesign
    security add-trusted-cert -d -r trustRoot -p codeSign \
      -k ~/Library/Keychains/login.keychain-db cert.pem

Without it, the build warns and falls back to ad-hoc, and grants will not survive a rebuild.

## Build and run

Requires Apple silicon and macOS 26 or later.

    ./build.sh
    open build/DragShot.app

The build uses the existing “DragShot Local Signing” certificate when available. It verifies
the signature before reporting success. `./install.sh` installs a real copy in Applications;
quit any running copy before switching between installed and development builds.

Modes:

    --status                print permissions for this launch context and exit
    --hotkey                also enable Command-Shift-4, then click and drag
    --request-permissions   raise the permission prompts

The debug hotkey is consumed by DragShot when enabled; it does not also launch Apple's
screenshot UI. Normal launches leave the system shortcut alone.

Log: `~/Library/Logs/DragShot.log`.

## Verification

Test-only code lives in `tests/` and is excluded from the normal app.

    ./build.sh --tests
    build/tests/DragShot.app/Contents/MacOS/DragShot --selftest
    open -n -W build/tests/DragShot.app --args --e2e

Quit the normal app before running E2E so only one event tap is active.

Self-tests assert coordinate conversion, event suppression, final mouse-up position,
Escape cancellation, transparent pixels, and selection geometry at 1× and 2×. They also render
the actual AppKit view to catch double backing-scale transforms and produce visual previews.

E2E posts keyboard and mouse events through the system event tap, performs a real screen
capture, checks note-field focus, and verifies a newly created PNG's dimensions and exact note.
It checks clipboard output, cancellation during capture, outside clicks and scrolls,
focus loss, app/Space changes, finger-lift release before mouse-up, synchronous input focus,
early Return while capture is pending, immediate submission cleanup, and multiline input. It also
captures the glass panel against light, dark, and colored backgrounds, then removes its
capture and note. It writes evidence and a verdict to `$TMPDIR/dragshot-ux-tests/`.
E2E changes the clipboard. Physical three-finger recognition and trackpad feel still need
a hands-on check.

## Files

    Sources/DragShot.swift          selection, capture, composition, and cleanup
    Sources/EventTap.swift          gesture ownership and keyboard cancellation
    Sources/Multitouch.swift        three-finger recognition
    Sources/OverlayWindow.swift     transparent selection window
    Sources/OverlayRenderer.swift   border, crosshair, and readout in Cocoa points
    Sources/PanelWindow.swift       transient native glass input and target dock
    Sources/TargetChipView.swift    DSH whale, target chip, and send dock appearance
    Sources/SessionPicker.swift     searchable session list and picker panel
    Sources/ScreenCapture.swift     bounded asynchronous region capture
    Sources/Storage.swift           PNG, note, and clipboard output
    Sources/DSHIntegration.swift    DSH socket client, launch, and status
    tests/SelfTest.swift            geometry, event, and visual checks
    tests/E2E.swift                 system-event and capture integration checks
    tests/UITests.swift             dismissal, focus, multiline input, and material previews
