# dsh-lookit

A local Cordis plugin for the DSH desktop host. It gives the
[Lookit](../) menu bar capture app a way to send a screenshot and
note into DSH without opening a second agent process.

The plugin is deliberately small:

- target a chosen session, the most recently used session, or a new session;
- send one PNG and note through the DSH session controller;
- no model-facing tool is registered; this is only an integration surface.

## Why a plugin

The DSH desktop app owns its live sessions. ACP and the SDK are separate agent
processes; they can list and resume persisted sessions, but they cannot attach to
a session the desktop app currently holds. A host plugin runs in the same process
as the UI and can call `ctx.sessionController` directly.

## Install

```sh
./install.sh /path/to/default/workspace
```

The script:

- links this package into `~/.dsh/profiles/node_modules/dsh-lookit`;
- appends one `insert` row for `dsh-lookit` to the profile's
  `cordis.patch.yml`;
- leaves the DSH app bundle untouched.

The desktop profile has HMR enabled, so a running DSH usually loads the new row
when the patch file changes. If that does not happen, restart DSH once:

```sh
osascript -e 'quit app "DeepSeek Harness"'
sleep 2
open -a "DeepSeek Harness"
```

During development the profile can also carry an HMR root watch so edits to
`lib/bridge.js` reload the bridge without restarting DSH:

```yaml
- id: hmr
  config:
    root: ["/path/to/lookit/dsh-lookit"]
```

The install script does not add this row; it is a development convenience, not
part of the integration.

Then enable **Send captures to DSH** in Lookit's menu bar menu.

Check that the bridge is up:

```sh
ls -l "$HOME/Library/Application Support/Lookit/dsh-bridge.json"
ls -l "$HOME/Library/Application Support/Lookit/dsh.sock"
```

## Protocol

Newline-delimited JSON over a Unix domain socket. One request per line; one
response per line. The socket directory and file are owner-only.

```json
{"id":"...","method":"hello","params":{}}
{"id":"...","method":"list","params":{}}
{"id":"...","method":"send","params":{
  "target":"recent",
  "text":"Look at this",
  "imageBase64":"...",
  "imageMediaType":"image/png",
  "imageName":"lookit.png",
  "mode":"queue"
}}
```

`target` is `recent` or `new`. An explicit `sessionId` selects a specific session and
overrides `target`. `send` returns:

```json
{"sessionId":"...","title":"...","created":false,"target":"recent"}
```

`list` returns the sessions the desktop UI can target:

```json
{"items":[{"sessionId":"...","title":"...","cwd":"/path/to/workspace",
           "updatedAt":0,"lastPromptAt":0,"running":false,"blank":false}]}
```

A new session starts in the most recent session's cwd when one exists, then in
the profile's `defaultCwd`. The Lookit app may also supply a `cwd` from the
frontmost document.

## Files

- `lib/bridge.js` — socket server, discovery file, request handling, prompt payload.
- `lib/index.js` — Cordis plugin wiring and config defaults.
- `test/bridge.test.mjs` — protocol tests with a fake session controller.

Run the tests with:

```sh
node --test test/bridge.test.mjs
```

## Diagnosis

The plugin appends metadata-only lines (method, session id, image byte count) to:

```
~/Library/Logs/LookitDshBridge.log
```

It never logs note text or image bytes. The bridge's own log file is separate
from Lookit's log at `~/Library/Logs/Lookit.log`.

## Limitations

- A newly created session is not auto-selected in the DSH window. The app is
  activated after sending; the session is visible in the sidebar. Selecting the
  new session automatically needs a client-side focus event or a DSH session
  deep link, which is the next step.
- The bridge is local-only and trusts processes running as the same user. That is
  the same trust boundary as the agent's own shell.
- The app reads the session list when its picker opens; the list does not live-update
  while the picker is visible.
- The DSH plugin uses the host `sessionController`; a future DSH version that
  changes those method shapes must update `lib/bridge.js`.
