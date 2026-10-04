# Desktop Bins Widget

**Tidy desktop panels that hold your files and folders, so your Mac's desktop stops being a pile.**

The macOS desktop turns into clutter fast. Downloads, screenshots, project folders and
shortcuts pile up until you can't find anything, and macOS's own Stacks only sort by kind or
date. Desktop Bins Widget puts titled, resizable panels on your desktop. Drag files and folders
into a panel, arrange them however you like, and open them with a double-click. Each set of
monitors keeps its own arrangement, so the panels stay put when you dock, undock or wake
from sleep.

---

## ⬇️ Download

<p align="center">
  <a href="https://github.com/smanke-org/Desktop-Bins-Widget/releases/latest/download/DesktopBinsWidget.dmg">
    <img src="https://img.shields.io/badge/Download-DesktopBinsWidget.dmg-2ea44f?style=for-the-badge&logo=apple&logoColor=white" alt="Download DesktopBinsWidget.dmg" height="48">
  </a>
</p>

1. **[Download DesktopBinsWidget.dmg](https://github.com/smanke-org/Desktop-Bins-Widget/releases/latest/download/DesktopBinsWidget.dmg)**
2. Open it and drag **Desktop Bins Widget** to **Applications**.
3. Open it from Applications, choose **New Bin** from the menu bar icon, and drag files into the bin.

No permissions to grant. Requires macOS 13 or later. Signed with Developer ID and notarized by Apple.

---

## Features

- Panels holding files and folders, dragged in from anywhere
- Drag to reorder within a panel; drop indicator shows where an item will land
- Double-click an item to open it; right-click to reveal in Finder or remove
- Drag by the title bar, resize from the corner, double-click the title to collapse
- Rename, recolor and delete panels
- Icon size, panel opacity and labels are configurable
- Panels remember which physical monitor they belong to, and appear on the
  main display rather than vanishing when that monitor is absent
- "Bring All Bins to Main Display" rescues panels stranded on a monitor that
  is no longer attached
- Files dragged in from the Desktop move to `~/Desktop Bins`, so the same file
  isn't shown twice and bins stay local to each Mac, even with a synced Desktop
- Each set of monitors remembers its own arrangement
- Item count in the title bar can be turned off per bin
- Optional Command-drag to move, so bins can't be nudged by accident
- Updates itself from the menu bar, verifying the download before installing
- Checks for a newer release at launch, silently unless there is one
- Optional launch at login
- Choose where the app appears: Dock, menu bar, both or neither (Settings › General). The Dock icon's right-click menu opens Settings; with both off, open the app again from Applications to reach Settings

A companion to, and a different product from, the discontinued Desktop Bins. That app
arranged Finder's real desktop icons; this one owns its contents.

## Why not a WidgetKit widget

A literal WidgetKit desktop widget cannot do this. Widgets run in a
sandboxed extension: they cannot send Apple Events, cannot be a drag-and-drop
destination, come only in fixed system sizes placed from the widget gallery,
and are limited to buttons and toggles for interaction. A widget could
*display* a bin's contents, but never hold, accept or arrange them.

These panels are therefore ordinary app windows pinned to the desktop
layer — widget-like in feel, fully interactive in practice.

## Updates

Desktop Bins Widget checks GitHub for a new release a few seconds after launch, and stays
silent unless there is one. You can also choose **Check for Updates…** from the menu bar at
any time. Nothing installs until you confirm it, and "Skip This Version" stops the launch check
offering that version again. Before installing, the download must be signed by the same
developer and notarized by Apple. See [Updating](#updating) below for how the update is
installed.

## Building

```bash
./build_app.sh
cp -R ".build/app/Desktop Bins Widget.app" /Applications/
open "/Applications/Desktop Bins Widget.app"
```

Requires macOS 13+. Signs with a Developer ID identity when one is present
(see `build_app.sh`), which keeps the app's identity stable across rebuilds.
`./notarize.sh` submits and staples a build for sharing to other Macs, and
`./make_dmg.sh` packages the stapled app into a signed, notarized `.dmg`
with the usual drag-to-Applications layout.

The image opens as a 600x400 window with 128px icons, the app on the left and Applications
on the right. That layout ships as a captured `.DS_Store` (`Resources/dmg/DS_Store`) which
`make_dmg.sh` copies into the staging folder, rather than being applied by driving Finder
during a release; recapture it with `Tools/capture_dmg_layout.sh` if the window changes.
There is no background picture: on macOS 27 Finder shows one only while it is dropped into
the View Options picture well by hand and discards it when the window closes.

## Icon

`Tools/generate_icon.swift` draws the periodic-tile icon — red with black lettering, the atomic number tipped 45° — and writes two
variants: the full tile, and a nameless one with a larger symbol for the 16
to 64pt sizes where the name would just be a smudge. Rebuild with:

```bash
swift Tools/generate_icon.swift
```

then regenerate `Resources/AppIcon.icns` from `Resources/AppIcon.iconset`
with `iconutil -c icns`.

## Implementation notes

### No Finder dependency

This is the significant departure from Desktop Bins. Because a panel owns
its items, the app never sends an Apple Event, so there is no Automation
permission, no TCC prompt, and none of the silent-failure modes that come
with driving Finder. It also means each panel is a single ordinary window
rather than the three-window arrangement Desktop Bins needs to stay both
visible behind desktop icons and clickable.

Panels sit at `desktopIconWindow + 1`: above the desktop so they receive
clicks, below every ordinary window so they never cover real work.

### Item references

Items store a bookmark alongside the path, so a shortcut keeps working when
its file is moved or renamed. The path is the fallback when a bookmark can't
be resolved. Items whose file no longer exists are drawn dimmed, and
"Tools › Remove Missing Items" in the menu clears them.

Layout follows list order, so panels are inherently gap-free — there is no
grid snapping to configure, unlike Desktop Bins.

### Moving Desktop files into bins

An item dropped in from the Desktop would otherwise appear twice — once in
the bin and once loose on the desktop — so the file is moved into
`~/Desktop Bins`, a folder in the home folder that nothing syncs. Removing the
item from its bin, or deleting the bin, moves it back to the Desktop under its
original name (numbered if that name has since been taken — nothing is ever
overwritten). "Tools › Return All Files to Desktop…" in the menu is the catch-all, and
"Show Desktop Bins Folder" opens the folder.

Bins are local to each Mac. The layout lives in Application Support, and a
Desktop synced by OneDrive or iCloud would otherwise carry whatever the app did
to a file to every other computer. Versions before 1.1.8 marked files hidden
instead, and the hidden flag synced: other computers ended up with invisible
files and no bins to show them in. Moving the file out means other computers
just see it leave their Desktop. The first launch of 1.1.8 moves any file an
earlier version hid and clears the flag.

Moves are coordinated with the file's provider, so a cloud-only placeholder is
downloaded as it leaves rather than carried off empty.

Only files sitting directly on the Desktop are moved. Items dragged in from
anywhere else are referenced where they are — moving something out of a
folder the user is actively browsing is not what dropping it on a bin asks for.

### Updating

"Check for Updates…" reads the latest GitHub release, downloads its disk
image, and replaces the running app.

Since that installs code fetched from the network, nothing is trusted on the
strength of where it came from. Before anything is copied over the installed
app, the downloaded bundle must pass `codesign --verify --deep --strict`,
carry the **same Team ID as the app that is running** (so a valid signature
belonging to someone else is refused), and pass Gatekeeper assessment, which
only succeeds if Apple notarized it. Any failure aborts and leaves the
installed app untouched.

The same check runs a few seconds after launch when "Check for Updates at
Launch" is on, deliberately silent unless there is something to offer —
reporting "up to date", or a failed network call, on every single launch
would be noise rather than information. Declining an update offers "Skip This
Version", which stops the launch check raising that version again; checking
manually still offers it.

The swap itself is handed to a detached shell script, because an app cannot
replace and relaunch its own bundle while it is the one running: the script
waits for the process to exit, replaces the bundle, and reopens it. The old
bundle is moved aside rather than deleted, so a failed copy restores it
instead of leaving no app installed at all.

### Aliases

Keeping aliases to folders on the Desktop is common, and asking macOS for an
alias file's icon returns the generic alias document rather than the target's
icon — so a folder alias looked like a blank page. Items therefore resolve
through an alias before their icon is fetched, and opening or revealing an
item lands on the real file rather than the alias.

### Multiple displays

Each panel stores the stable UUID of its display
(`CGDisplayCreateUUIDFromDisplayID`) plus its offset within that display,
never a raw `CGDirectDisplayID` — those are assigned per session, so the
same monitor can return with a different id. Storing an offset rather than
an absolute point keeps panels in place when displays are rearranged and the
global coordinate space shifts. A panel whose display is not attached is shown on the main display instead of
being hidden — plugging a laptop into a different set of monitors should not
look like the panels were lost. Its stored pin is left untouched so it
returns home when its own monitor comes back; it is only re-pinned if the
user actually moves it. Offsets from a larger monitor are clamped into the
fallback screen so a panel can't land off-screen. "Tools › Bring All Bins to
Main Display…" in the menu tiles everything onto the main display as an emergency
recovery.

Each panel also remembers a separate arrangement per monitor setup, keyed by
a signature of the attached displays. Moving between a desk, a second desk
and the bare laptop restores whatever layout was last used with each, rather
than keeping a single position that the previous setup overwrites.

A layout is saved only when the user moves, resizes, collapses or gathers a
panel — never because the displays changed. Waking from sleep reconnects
monitors one at a time, and before 1.1.15 the app saved a layout for each
partial set it passed through, using wherever the panel happened to be at
that instant. Those showed up as panels shifting around their own screen
after sleep. Placement now works in this order: the layout saved for exactly
this set of monitors; otherwise wherever the user last put the panel on its
own display, which keeps it still while other monitors come and go; otherwise
the main display, shown but not saved. The rules live in
`BinPlacementResolver`, separate from the windows, so they can be tested
against any arrangement. 1.1.15 also removes, once, the layouts that wakes
had saved.

That alone did not stop the shifting, because macOS moves windows too: while
displays reconnect, and again afterwards when it restores window positions it
remembers, sometimes after the app's last display notification. Since 1.1.16
the app watches each panel's window, and a move or resize the user didn't make
puts the panel back where it was saved (logged, never saved). It also places
panels again on wake and 1.5, 5 and 15 seconds after a display change. A click
on a panel that isn't a drag no longer saves its position, which used to make
a displaced panel's spot permanent.
