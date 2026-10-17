# DragShot development

Technical notes for building, extending, and verifying DragShot. The [README](README.md)
is the short user guide.

## Using it

Three-finger drag across a region. Release to open the composer. Return saves a PNG and note
to `~/Pictures/DragShot/` and copies the image to the clipboard. Shift-Return inserts a newline;
Escape cancels. When DSH sending is enabled, the bottom target chip chooses the chat; the
default is the most recent session, and `⌘/` or a leading slash opens the picker.

## Install with DSH

The repository ships the `install-dragshot` skill at
[`skills/install-dragshot/SKILL.md`](skills/install-dragshot/SKILL.md). Link it into the DSH
skill catalog once from the checkout root:

```sh
mkdir -p ~/.dsh/skills
ln -sfn "$PWD/skills/install-dragshot" ~/.dsh/skills/install-dragshot
```

Then ask DSH to install DragShot from this repo. The skill builds and installs the app, sets up
the Cordis bridge, enables DSH sending, and hands off the permission and three-finger trackpad
steps. Restart DSH once if the skill does not appear in the catalog.

The skill's wrapper is `skills/install-dragshot/scripts/install.sh`; it is safe to rerun for an
upgrade. The manual build path is below.

## Privacy

DragShot collects no data and has no network client. No account, analytics, telemetry,
crash reporter, API key, or remote service is involved. Everything the app and its local
bridge do happens on the Mac.

The DSH handoff is local: DragShot writes one request to an owner-only Unix domain socket that
the `dsh-dragshot` host plugin listens on. DSH itself is a separate application; any network
behavior it has for its own model calls is outside DragShot.

### What is stored locally

- Captures and notes: `~/Pictures/DragShot/` (PNG plus the text note).
- Settings: the `local.dragshot` `UserDefaults` domain (enabled state, target session id/title,
  and whether to activate DSH after send).
- Diagnostics: `~/Library/Logs/DragShot.log` and
  `~/Library/Logs/DragShotDshBridge.log`. These contain metadata such as method names, session
  ids, image dimensions, and error descriptions; the bridge never logs note text or image
  bytes.
- While DSH sending is enabled: `~/Library/Application Support/DragShot/dsh-bridge.json` and
  `dsh.sock`, plus the DSH profile's plugin row.
- The captured image is copied to the system pasteboard.

None of these are uploaded or collected by DragShot.

### Network audit

- No `URLSession`, `URLRequest`, `NSURLConnection`, `NWConnection`, WebSocket, HTTP client, or
  `fetch` in `Sources/` or `dsh-dragshot/lib/`.
- The app links Cocoa, ScreenCaptureKit, ApplicationServices, ImageIO, and their system
  dependencies; no CFNetwork/Network framework.
- The DSH client uses `AF_UNIX`/`SOCK_STREAM`; the plugin uses `node:net` to `listen` on a Unix
  socket path, not a TCP port.
- The signed app has no entitlements, including no network entitlement.
- The app has no third-party dependencies. The bridge's only peer dependencies are DSH host
  packages that DSH already provides.

### Verification

Run these from the repository:

```sh
grep -RInE 'URLSession|URLRequest|NSURLConnection|NWConnection|WebSocket|https?://|fetch\(' \
  Sources dsh-dragshot/lib
otool -L build/DragShot.app/Contents/MacOS/DragShot
codesign -d --entitlements :- build/DragShot.app
wc -l Sources/*.swift dsh-dragshot/lib/*.js
```

At the time of the audit the network search returns no matches, `otool` shows no
CFNetwork/Network dependency, the entitlements output is empty, and the app plus bridge are
under 4,000 lines. The plugin listens only on its Unix socket. These are source and build checks, not browser-visible claims in a separate dashboard.

## Selection and event ownership

The desktop stays live during selection. DragShot draws only a system crosshair, a softly
rounded outline, and a compact pixel-size readout; it never paints a replacement desktop. A
tap or a movement under three contacts does not flash an overlay.

The global event tap owns the whole mouse sequence, including the mouse-up after Escape. It
intercepts the drag before it reaches the app underneath, and Escape consumes the remainder of
that sequence so cancellation cannot leave another app dragging or selecting text. The
selection is confined to the display where the drag began. Lifting the last finger ends
selection immediately; DragShot consumes the system's delayed mouse-up so it cannot finish
twice.

## Capture

ScreenCaptureKit captures the selected region without DragShot's windows or cursor. The
outline disappears immediately and the composer takes typing focus while capture finishes
asynchronously. Capture requests time out after four seconds. Late results cannot reopen
cancelled UI.

## Composer

The composer is a nonactivating native glass panel. It takes typing focus without switching
apps, follows the system appearance, opens blank with a blinking cursor, and grows for
multiline notes. The screenshot preview preserves aspect ratio and settles in above the
message. The arrival animation respects Reduce Motion; the composer itself appears immediately.

Return submits through the local save/clipboard pipeline. Shift-Return inserts a newline.
Dragging the glass background or the attachment repositions the window with native window
dragging, and growing text preserves the chosen position.

Clicking or scrolling outside, losing typing focus, or switching apps or Spaces cancels the
composer and selection. The exception is the DSH session picker: it deliberately takes key
focus, so the composer stays alive while it is open. Outside interactions still reach the app
underneath. Clicking away during capture cancels the pending screenshot. Early Return while
capture is pending is preserved and submitted when the image is ready.

## DeepSeek Harness integration

The composer's bottom dock targets a DSH session. The chip defaults to **Most recent** and can
pin a specific session or **New chat**. The target is stored in `UserDefaults` and survives
later captures and relaunches. The local PNG/note save and clipboard copy always happen first;
DSH delivery is additive.

Clicking the chip opens a nonactivating searchable picker. New chat is pinned first, followed
by recent sessions with workspace, age, and running state. Search takes focus on open; Up/Down
and Return work; selecting a row pins it and returns the cursor to the message field with the
draft intact. Escape or an outside click closes the picker first. The target list is read from
the bridge when the picker opens.

Shortcuts while composing:

- `⌘/` toggles the picker.
- `/` opens it when the message is empty and the caret is at the start; the slash is consumed.
- A slash after text remains literal.

The menu bar menu can switch back to **Most recent** or **New chat**, which clears a pin.
When DSH is disabled the target dock is hidden and Return behaves as a local-only capture.

### Architecture

The DSH desktop app owns its live sessions; ACP and the SDK are separate processes and cannot
attach to a session the desktop UI currently holds. A Cordis host plugin runs in the same
process as the UI and calls `ctx.sessionController` directly.

The plugin lives in [`dsh-dragshot/`](dsh-dragshot/). It publishes a newline-delimited JSON
protocol over an owner-only Unix socket:

    ~/Library/Application Support/DragShot/dsh-bridge.json
    ~/Library/Application Support/DragShot/dsh.sock

DragShot reads the discovery file, starts DSH when needed, and sends one request on the socket.
The plugin calls the live session controller and returns the resulting session id and title.
No TCP port is opened.

See [dsh-dragshot/README.md](dsh-dragshot/README.md) for the protocol, bridge limits, and
diagnostic log.

### Install the bridge

```sh
cd dsh-dragshot
./install.sh /path/to/default/workspace
```

The installer links the plugin into `~/.dsh/profiles/node_modules/dsh-dragshot` and appends one
`dragshot-bridge` row to the desktop profile's `cordis.patch.yml`. It leaves the DSH app bundle
untouched. If DSH is already running, its HMR watcher normally loads the row; if the menu says
“DSH bridge: Not loaded”, restart DSH once:

```sh
osascript -e 'quit app "DeepSeek Harness"'
sleep 2
open -a "DeepSeek Harness"
```

Then enable **Send captures to DSH** in DragShot's menu bar menu.

### Known limits

- There is no screenshot-based routing heuristic yet.
- A newly created session is not auto-selected in the DSH window; sent sessions are visible in
  its sidebar, but selecting one still takes a click.
- The picker reads the session list when it opens and does not live-update while open.
- The bridge is local-only and trusts processes running as the same user.

## Trackpad setup

Enable three-finger drag:

    System Settings → Accessibility → Pointer Control → Trackpad Options
      Use trackpad for dragging: on
      Dragging style: Three Finger Drag

macOS supplies mouse coordinates and acceleration. The private `MultitouchSupport` framework
confirms three contacts and detects the final finger lift; ordinary mouse and one-finger drags
pass through. This setting changes which gestures are available to Mission Control and Spaces.

## Permissions and signing

| Grant | Why | Needed for |
|---|---|---|
| Screen Recording | read screen pixels | the selected region after release |
| Accessibility | watch the global mouse/keyboard stream | the three-finger trigger and debug hotkey |

On **macOS 27 and later the Accessibility list is labelled “Device Control and Data Access”**
under Privacy & Security; it was called “Accessibility” up to macOS 26. The service did not
change: `tccutil` still calls it `Accessibility`, and the settings URL is still
`Privacy_Accessibility`. Screen Recording kept its name and lives in the same pane.

Run and grant permissions to the signed app through LaunchServices (`open` or Finder). A binary
launched directly from a shell can have a different permission context. Use the app's menu to
check readiness; the event tap and trackpad reader must also be running.

**A rebuild voids an ad-hoc signature's grants.** Ad-hoc signing has no identity, only a hash of
the binary. The build therefore signs with a local certificate by default:

```sh
codesign -d -r- build/DragShot.app
# designated => identifier "local.dragshot" and certificate leaf = ...
```

Create the certificate once, then grants survive every rebuild:

```sh
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
```

Without it, the build warns and falls back to ad-hoc; grants will not survive a rebuild. The
generated `*.pem` and `*.p12` files are gitignored.

## Build and run

Requires macOS 26 or later. Tested on Apple silicon.

```sh
./build.sh
open build/DragShot.app
```

The build uses the existing “DragShot Local Signing” certificate when available, verifies the
signature, and reports success. `./install.sh` installs a copy in Applications (or `~/Applications` if
`/Applications` is not writable); quit a running copy before switching between installed and
development builds.

Modes:

```sh
build/DragShot.app/Contents/MacOS/DragShot --status
build/DragShot.app/Contents/MacOS/DragShot --hotkey
build/DragShot.app/Contents/MacOS/DragShot --request-permissions
```

`--hotkey` also enables Command-Shift-4, then click and drag. The debug hotkey is consumed by
DragShot when enabled. Normal launches leave the system shortcut alone.

Log: `~/Library/Logs/DragShot.log`.

## Verification

Test-only code lives in `tests/` and is excluded from the normal app.

```sh
./build.sh --tests
build/tests/DragShot.app/Contents/MacOS/DragShot --selftest
open -n -W build/tests/DragShot.app --args --e2e
```

Quit the normal app before running E2E so only one event tap is active.

Self-tests assert coordinate conversion, event suppression, final mouse-up position, Escape
cancellation, transparent pixels, and selection geometry at 1× and 2×. They render the actual
AppKit view to catch double backing-scale transforms, exercise the picker, and verify the
leading-slash trigger and focus return.

E2E posts keyboard and mouse events through the system event tap, performs a real screen
capture, checks note focus, and verifies a newly created PNG's dimensions and exact note. It
covers clipboard output, cancellation during capture, outside clicks and scrolls, focus loss,
app/Space changes, finger-lift release before mouse-up, synchronous input focus, early Return
while capture is pending, immediate submission cleanup, and multiline input. It captures the
glass panel against light, dark, and colored backgrounds, then removes its capture and note.
Evidence and a verdict are written to `$TMPDIR/dragshot-ux-tests/`. E2E changes the clipboard.
Physical three-finger recognition and trackpad feel still need a hands-on check.

The README image can be regenerated with the test-only clockwork:

```sh
./build.sh --tests
build/tests/DragShot.app/Contents/MacOS/DragShot --readme-shot /path/to/wallpaper.png
```

It writes `readme-shot.png` under `$TMPDIR/dragshot-ux-tests/`. It uses sample content and
contains no personal desktop data.

## Repository notes

- `mockups/` contains local design renders and screenshots; it is gitignored and must not be
  published.
- The README image is a clean capture of the real AppKit composer using sample content and the built-in macOS 27 Golden Gate Sunset wallpaper. It contains no personal desktop content.
- Test evidence stays in `$TMPDIR` and is not committed.
- `build/`, local signing keys, and probe binaries are gitignored.

## Files

    Sources/DragShot.swift          selection, capture, composition, and cleanup
    Sources/EventTap.swift          gesture ownership and keyboard cancellation
    Sources/Multitouch.swift        three-finger recognition
    Sources/OverlayWindow.swift     transparent selection window
    Sources/OverlayRenderer.swift   border, crosshair, and readout in Cocoa points
    Sources/PanelWindow.swift       transient native glass input and target dock
    Sources/GlassSurfaceView.swift  shared NSVisualEffectView popover material
    Sources/GlassFillView.swift     appearance-aware fill for text readability
    Sources/SendButton.swift        quiet chip-sized send control
    Sources/TargetChipView.swift    DSH whale, target chip, and send dock appearance
    Sources/SessionPicker.swift     searchable session list and picker panel
    Sources/ScreenCapture.swift     bounded asynchronous region capture
    Sources/Storage.swift           PNG, note, and clipboard output
    Sources/DSHIntegration.swift    DSH socket client, launch, and status
    dsh-dragshot/                   Cordis host bridge (plugin, protocol, installer, tests)
    skills/install-dragshot/        DSH install skill and its wrapper script
    assets/dragshot-example.png     README illustration
    tests/SelfTest.swift            geometry, event, and visual checks
    tests/E2E.swift                 system-event and capture integration checks
    tests/UITests.swift             dismissal, focus, multiline input, and material previews
