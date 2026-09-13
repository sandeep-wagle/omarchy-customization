# Omarchy Customization

A Windows / Ubuntu-style **Hyprland + Omarchy** setup that turns a stock Omarchy
install into a familiar "Windows 11-like" desktop: a top bar with an auto-hiding
**taskbar** that lists every open window with its real app icon, Windows-style
window snapping (with a live snap preview), and Alt+Tab / Super+Tab window and
workspace switching.

Everything needed to reproduce this setup on a fresh Omarchy machine lives in
this repository. The config is an **override layer on top of Omarchy** — it
`dofile`s the Omarchy bootstrap, so there is no "base config" to maintain.

---

## Features

### Top bar with auto-hiding taskbar
- **Windows-style taskbar** (`com.sandy.taskbar`) shows the windows open on the
  current workspace, each with its **real application icon** (more below).
  - **Left-click** focuses that exact window (raising it over floating peers).
    Focus works across workspaces and restores minimized windows — it never
    launches a duplicate instance.
  - **Middle / right-click** sends a graceful close request.
  - Only the **focused** window shows a title label (truncated with an ellipsis);
    every other window is a compact icon chip. Total bar width stays **bounded**
    no matter how long a window title is, so the taskbar can never overlap the
    clock or system tray.
  - Minimized windows stay in the taskbar, dimmed, and are restored on click.
- **Auto-hide bar** (`bar.auto-hide`): slides off-screen when idle, reappears on
  hover. Toggle anytime with `omarchy-toggle-bar-mode`. The mode persists across
  login.
- **Snap preview** (`me.sandy.snap-preview`): while dragging a window toward an
  edge or corner, the target zone is highlighted live.

### Windows-style window management
- **Apps open maximized**, filling the usable workspace (no auto-split).
- **`Super` + arrows** = Windows-style snapping:
  - `Super+Left` / `Super+Right` — snap to half-screen (press again to return to
    tiling)
  - `Super+Up` — maximize · `Super+Down` — restore
  - `Super+Ctrl+Shift+Left/Right/Up/Down` — snap to the four quarters
- **Native drag-to-snap**: drag a floating window to a screen edge/corner.
- `Super+Print` fullscreen screenshot · `Super+L` locks the screen.

### App & workspace switching
- **Alt+Tab** — application switcher
- **Super+Tab** — workspace switcher
- Powered by the bundled `mogtab` / `mogtabctl` (see notes on binaries below).

---

## Requirements

- An **Omarchy** install (the top bar shell + Hyprland with the Lua config
  build, usually at `/usr/share/omarchy` and `~/.config/omarchy`).
- Hyprland, `hyprctl` on `PATH`.
- The `mogtab` binaries are **prebuilt for the original environment** — on a
  different machine/architecture, rebuild or replace them with a package build.

---

## Install

```sh
# 1. copy this folder to the target machine, then from inside it:
./install.sh             # dry run — shows exactly what would change
./install.sh --apply     # back up existing files, then install ours
```

What `--apply` does:

1. Every destination file that differs is first copied to
   `~/backups/omarchy-customization/<timestamp>/` (never deleted).
2. Files are installed into their real locations (`~/.config/hypr/...`,
   `~/.config/omarchy/plugins/...`, `~/.local/bin/...`, `~/.config/mogtab/...`).
3. Helper binaries are made executable.
4. `hyprctl reload` runs, and the `mogtab` switcher is restarted if running.
5. Restart the shell so the new bar widgets load:

   ```sh
   omarchy-restart-shell
   ```

Revert to the previous state (restores the most recent backup):

```sh
./install.sh --revert
```

---

## Configuration

### Taskbar title-length cap
The focused window's label is capped so the bar stays bounded. Default cap is
`160px`; tune it per bar entry in `omarchy/shell.json`:

```json
{
  "id": "com.sandy.taskbar",
  "maxWidth": 200
}
```

Key refers to the live layout under `bar.layout.left`.

### Bar auto-hide mode
Toggle between always-visible and auto-hide:

```sh
omarchy-toggle-bar-mode      # flip the current mode, persists across login
```

The mode is a single state flag under
`~/.local/state/omarchy/toggles/bar-auto-hide` (present = auto-hide).

### How app icons are resolved (apps / theme developers)
The taskbar looks a window's icon up the same way a launcher does:

1. The window's **app_id / wm_class** (Hyprland `class`) is matched to its
   `.desktop` entry (`<app_id>.desktop` under the XDG application dirs,
   **including Flatpak exports**), and the entry's `Icon=` value is used —
   this bridges apps whose wm_class differs from their icon name (e.g. Brave:
   class `brave-browser`, icon `brave-desktop`).
2. That icon name is resolved through the **freedesktop icon theme**.
3. If the theme misses it, a **fresh disk index** of `apps/` / `devices/` icon
   files (plus `/usr/share/pixmaps`) is consulted — this catches icons installed
   after the shell started, or living outside a theme.
4. Only the last step falls back to the generic application icon.

So a missing icon is usually a missing `.desktop` `Icon=` (or a theme that
doesn't ship the icon); install one and re-run `./install.sh --apply` or restart
the shell.

### Monitor / layout defaults
- `hypr/monitors.lua` forces `1920x1080@60` — edit for the target monitor.
- `toggles/single-window-aspect-ratio.lua` keeps single tiled windows square-ish
  on wide screens. Remove/move that file (or the whole `toggles/` dir) to
  disable.

---

## Folder layout

```
omarcy_customization/
├── install.sh                        # backup + install / revert helper
├── README.md
├── LICENSE
├── hypr/                             # Hyprland override layer (Lua build)
│   ├── hyprland.lua                  # main config (requires the pieces below)
│   ├── hyprland.conf                 # VM/config glue (spice-vdagent)
│   ├── bindings.lua                  # keybindings (snapping, screenshots, locks)
│   ├── bindings.lua.backup           # working copy of the original bindings
│   ├── looknfeel.lua                 # look & feel + native drag-to-snap
│   ├── windows.lua                   # maximize-on-open window rule
│   ├── monitors.lua                  # forced 1920x1080@60 monitor mode
│   └── autostart.lua                 # starts mogtab/switcher on login
├── mogtab/
│   └── config.toml                   # Alt+Tab (apps) / Super+Tab (workspaces)
├── bin/
│   ├── mogtab                        # app/workspace switcher daemon (prebuilt)
│   ├── mogtabctl                     # control client for mogtab
│   ├── omarchy-window-snap           # snap/maximize/restore geometry helper
│   └── omarchy-toggle-bar-mode       # flip auto-hide / always-visible
├── omarchy/
│   ├── shell.json                    # top-bar layout (see “Configuration”)
│   ├── shell.toml                    # bar font size
│   └── plugins/
│       ├── bar-auto-hide/            # status bar with auto-hide + hover
│       │   ├── manifest.json
│       │   ├── Bar.qml
│       │   └── BarModel.js
│       ├── com.sandy.taskbar/        # the Windows-style taskbar widget
│       │   ├── manifest.json
│       │   └── TaskbarWidget.qml
│       └── snap-preview/             # drag-to-snap destination highlight
│           ├── manifest.json
│           └── SnapPreview.qml
├── toggles/
│   └── single-window-aspect-ratio.lua
└── docs/
    └── OMARCHY_KEYBINDINGS_REFERENCE.md  # full keybinding reference
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bar / taskbar missing after install | Confirm the plugin folders exist under `~/.config/omarchy/plugins/`, then `omarchy-restart-shell`. Check the shell log for QML errors (`journalctl --user --no-pager | grep -i -E "quickshell\|omarchy-shell"`). |
| A window shows the generic app icon | Its `.desktop` `Icon=` is missing/mismatched, or the icon isn't in any theme/pixmaps (see “How app icons are resolved”). |
| Windows no longer maximize on open | `hypr/windows.lua` handles that rule — make sure the file is installed and not edited away. |
| Snap arrows don't do anything | `omarchy-window-snap` must be on `PATH` (`~/.local/bin` is added by `install.sh`). |

---

## Contributing

Small, focused config tweaks welcome. Keep a change self-contained, update
`install.sh`'s `PAIRS` list if you add files, and add a line to the README when
behavior changes. Conventional-commit message style is used in this repo.

## License

[MIT](LICENSE) — use it, fork it, adjust it to your own taste.