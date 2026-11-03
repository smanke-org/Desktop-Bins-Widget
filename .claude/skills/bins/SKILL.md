---
name: bins
description: Drive Desktop Bins Widget, the app that puts panels (bins) of files on this Mac's desktop, from the shell with the `bins` command: list the bins and what they hold, put files in a bin, take items out, reorder and open them, and create, rename, color, collapse, show, hide and delete bins. Use when the user asks about their desktop bins or the files in them, wants something added to or removed from a bin, or names Desktop Bins Widget.
---

# Desktop Bins Widget

`bins` runs commands in the Desktop Bins Widget app. The bins on the desktop change at once.
If the app is closed, the command opens it in the background. If `bins` isn't on PATH, use
`"/Applications/Desktop Bins Widget.app/Contents/MacOS/DesktopBinsWidget"` the same way.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and
  `error.message`, and do what the message says.
- A bin is named by its id (8 characters; any unique start works) or its name. Find them with
  `bins list`. Items: `bins items list [--bin B] [--search T]`, by id, or by name with `--bin`.
- `items remove`, `delete`, `panels gather`, `items remove-missing` and `files return` only
  report what they would do. Show the user that report and ask before you run it again with `--yes`.
- No command deletes a file. A file put in a bin straight from the Desktop moves into
  `~/Desktop Bins` (while that setting is on) and goes back to the Desktop when it leaves the bin.
- `items open` opens the file in its app on the user's screen: only when they asked.
- Paths may be relative in the shell; over MCP they must be absolute.
- To try something without real data, run a Debug build with `APP_STORE=/tmp/bins-test` in front:
  a test copy with its own bins, stand-in Desktop and settings, and no panels on screen.

## Main commands

| Command | Does |
| --- | --- |
| `bins status --json` | Version, bin and item counts, missing items, bins shown or hidden |
| `bins list --json` / `bins show <bin> --json` | The bins / one bin and its items in order |
| `bins items add <path> --bin <bin> [--index N] --json` | Put a file or folder in a bin |
| `bins items remove <item> [--bin <bin>] --yes --json` | Take an item out of its bin |
| `bins create --name N [--color 10B981] --json` | Make a new bin |
| `bins update <bin> [--name N] [--color HEX] [--collapsed true] [--show-count false] --json` | Change one |
| `bins panels hide --json` / `bins panels show --json` | Take every bin off the desktop / back |

Everything else: `bins help`, and `bins help <command>` for its options.
