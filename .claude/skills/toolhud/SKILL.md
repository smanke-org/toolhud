---
name: toolhud
description: Drive ToolHUD, the ring launcher on this Mac, from the shell with the `toolhud` command: list, add, change, duplicate and delete the HUD's buttons (usual ring, button pad, each app's ring), list the app features lens buttons can run, change the look, open or close the HUD, and run a button. Use when the user asks about their ToolHUD buttons or rings, wants one added or changed, or names ToolHUD.
---

# ToolHUD

`toolhud` runs commands in the ToolHUD app. Changes show in its Settings at once, are saved
and sync to the user's other Macs like edits made there. If the app is closed, the command
opens it in the background. If `toolhud` isn't on PATH, use
`/Applications/ToolHUD.app/Contents/MacOS/ToolHUD` the same way.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and
  `error.message`, and do what the message says.
- Find ids with `toolhud buttons list` (add `--ring all` for every app's ring). An id is
  8 characters; any unique start works.
- `buttons delete` only reports what it would delete. Show the user that report and ask
  before you run it again with `--yes`.
- `buttons run` and `hud repeat` do what the button does: press keys, type text, open apps,
  run a script. Only run one when the user asked for that button to run.
- Script buttons run shell commands or AppleScript when clicked; say so when you add one.
- Folders, Steps and app menu buttons are made in Settings (`toolhud settings open --pane buttons`).
- Paths may be relative in the shell; over MCP they must be absolute.
- To try something without real data, run a Debug build with `APP_STORE=/tmp/toolhud-test` in front.

## Main commands

| Command | Does |
| --- | --- |
| `toolhud status --json` | Version, HUD open or not, look, button counts, features on |
| `toolhud buttons list [--ring Safari\|all] [--place ring\|pad] [--search T] --json` | The buttons that show, with ids |
| `toolhud buttons add --kind lens --app TextLens --feature qr --json` | Add one (kinds: lens, keystroke, shortcut, open, text, menu-item, script) |
| `toolhud buttons update <id> [--name N] [--symbol S] [--color teal] [--keys "⇧⌘S"] --json` | Change one |
| `toolhud features list [--app A] --json` | What lens buttons can run, and which apps are installed |
| `toolhud look set orbit --json` | Change the HUD's look |

Everything else: `toolhud help`, and `toolhud help <command>` for its options.
