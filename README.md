# ClipboardMgr

A lightweight macOS menu bar clipboard manager written in SwiftUI. No dependencies.

## Features

- Lives in the menu bar (clipboard icon) — no Dock icon
- Keeps the last 500 text snippets you copy, persisted across restarts
- Type-to-filter search; press **Return** to copy the top match
- Click any entry to copy it back to the clipboard
- Pin entries to keep them at the top (pinned items survive **Clear**)
- Hover a row for pin/delete buttons; right-click for a context menu
- Skips concealed/transient pasteboard content (e.g. password managers that
  mark entries with `org.nspasteboard.ConcealedType`)

## Build & run

```sh
./build-app.sh
open ClipboardMgr.app
```

## Start at login

System Settings → General → Login Items & Extensions → add `ClipboardMgr.app`.

## Notes

- History is stored as JSON at
  `~/Library/Application Support/ClipboardMgr/history.json`. Delete that file
  to wipe history completely.
- macOS has no pasteboard-change notification, so the app polls
  `NSPasteboard.changeCount` twice a second — this is the standard approach
  and uses negligible CPU.
- Text only for now (images/files are ignored).
