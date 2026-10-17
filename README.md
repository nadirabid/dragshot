# DragShot

Three-finger drag screen capture for macOS.

Drag three fingers across a region. Release to capture it, add a note in the glass composer, and press Return. DragShot saves the image and note to `~/Pictures/DragShot/`, copies the image to the clipboard, and can send both into DeepSeek Harness.

![DragShot composer over macOS 27's Golden Gate wallpaper](assets/dragshot-example.png)

## Use it

1. Three-finger drag across a region.
2. Type a note. Return submits; Shift-Return adds a line; Escape cancels.
3. The PNG and note land in `~/Pictures/DragShot/`; the image is on the clipboard.
4. To target DSH, use the chip at the bottom of the composer. It defaults to the most recent session; click it to search and pin a session or choose New chat. `⌘/` toggles the picker, and a leading `/` opens it in an empty message.

Click outside or switch apps to dismiss the composer; drag its background to move it.

## Install

Requires Apple silicon and macOS 26 or later.

```sh
./build.sh
open build/DragShot.app
```

`./install.sh` installs a copy in Applications.

Enable three-finger drag in **System Settings → Accessibility → Pointer Control → Trackpad Options**:

- Use trackpad for dragging: on
- Dragging style: Three Finger Drag

Grant **Screen Recording** and **Accessibility** when prompted. On macOS 27, Accessibility is labelled **Device Control and Data Access**. See [DEVELOPMENT.md](DEVELOPMENT.md#permissions-and-signing) for permission and signing details.

## DeepSeek Harness

DSH sending uses the Cordis plugin included in [`dsh-dragshot/`](dsh-dragshot/). It runs inside the DSH desktop host and exposes a local, owner-only socket. Install it once:

```sh
cd dsh-dragshot
./install.sh /path/to/default/workspace
```

Then enable **Send captures to DSH** in DragShot's menu bar menu. The composer's target chip remembers a pinned session. The local save and clipboard copy always happen first; DSH delivery is additive.

See [DEVELOPMENT.md](DEVELOPMENT.md#dsh-integration) for the bridge protocol and limits, and [dsh-dragshot/README.md](dsh-dragshot/README.md) for the plugin itself.

## More

Internals, build modes, signing, and the test suite are in [DEVELOPMENT.md](DEVELOPMENT.md).
