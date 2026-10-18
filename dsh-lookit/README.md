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

The installer copies the complete dependency-free host and client payload to
`~/Library/Application Support/Lookit/Integrations/dsh-lookit` and links that
stable location into `~/.dsh/profiles/node_modules/dsh-lookit`. Moving or deleting
the checkout cannot break the installed integration. Existing configuration is
preserved, legacy rows are migrated, and incomplete payloads are rejected.

For a complete app installation, use the repository root installer. The signed
app bundles this same bridge installer; Settings → Harnesses → Set Up / Repair
Bridge works without a checkout. A DSH profile must first have been initialized
by opening DSH. The installer does not initialize profiles or change the selected
harness. Restart DSH after its active work finishes if a new client has not loaded.

Check readiness with `skills/install-lookit/scripts/diagnose.sh` from the root.
It checks a live handshake and client heartbeat, not just socket-file existence.

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
node --test test/*.test.mjs
```

## Diagnosis

The plugin appends metadata-only lines (method, session id, image byte count) to:

```
~/Library/Logs/LookitDshBridge.log
```

It never logs note text or image bytes. The bridge's own log file is separate
from Lookit's log at `~/Library/Logs/Lookit.log`.

## Limitations

- With Open after sending enabled, the client companion refreshes the session
  list and selects the accepted chat. The bridge reports `opened: true` only
  after the UI acknowledges that selection. Delivery remains successful if
  navigation times out; Lookit does not resend the prompt.
- New sessions use the matching DSH workspace when its path matches the chosen
  directory; otherwise they appear under Ungrouped.
- The bridge is local-only and trusts processes running as the same user. That is
  the same trust boundary as the agent's own shell.
- The app reads the session list when its picker opens; the list does not live-update
  while the picker is visible.
- The DSH plugin uses the host `sessionController`; a future DSH version that
  changes those method shapes must update `lib/bridge.js`.

## Live validation (opt-in)

From the repository root, run:

```sh
LOOKIT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk bash tests/live/run-dsh.sh --send-test
```

This creates one real chat using the production Swift sender and an image
containing `LOOKIT DSH 7F3A` and a green square. It fails unless the host creates
and the client selects the chat. Check the visible attachment and the response
reading the marker and square color to validate model receipt too. This is not
part of the default unit suite and does not test the physical trackpad gesture.

The default tests cover socket protocol, workspace association, successful and
failed navigation, stale acknowledgements, client selection verification, and
self-contained fresh installs, upgrades, legacy migration, and incomplete payloads.
