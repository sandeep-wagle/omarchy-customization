# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/), versioned semantically.

The repository's history before the public release is consolidated; pre-release
development (the "phases" the configs still comment about) is summarized in the
`1.0.0` entry rather than preserved as a full commit-by-commit history.

## [Unreleased]

### Fixed

- **Alt+Tab now opens instantly** (`bin/omarchy-switch`) — the screen
  capture/preview decode moved into a background thread that runs while the
  picker is being created, so the picker presents in ~0.3 s (was ~0.6 s) with
  icon tiles and swaps in real previews as they render. No self-capture: the
  frame is still grabbed before the window appears.
- **Quick Alt+Tab tap is visible** (`bin/omarchy-switch`) — releasing Alt
  almost immediately used to close the picker inside one render frame, so it
  never seemed to work. Activation now waits a 140 ms dwell first, so the
  picker is seen and the selected window opens.
- **App icons actually render** (`bin/omarchy-switch`) — this GTK4 build's
  `IconTheme.lookup_icon` needs a different signature and threw every call, so
  every card icon silently failed. Replaced with a bounded, cached theme-file
  resolver that loads `hicolor/*/apps/*.png` etc. directly.
- **Only truly visible windows get previews** (`bin/omarchy-switch`) — windows
  covered by a fullscreen sibling are no longer shown with that same
  fullscreen snapshot repeated on every card (the "duplicate screens" look);
  they fall back to an icon tile like other-workspace windows.

- **Alt+Tab release activation** (`bin/omarchy-switch`) — releasing Alt
  (or Enter/click) now actually focuses the selected window and closes the
  picker. Root cause: `resolve_live()` had been clobbered to an empty body, so
  activation emitted `address:None` → Hyprland "window not found" and the
  picker never closed. Restored live-address re-resolution plus a proper
  `Switcher.cancel`.
- **Lost commands during fast Alt release** (`bin/omarchy-switch`) — a `close`/
  `move`/`cancel` sent before the GUI had bound its socket is no longer
  dropped: the CLI now polls for the socket (up to ~3 s) and retries.
- **Unresponsive picker cleanup** (`bin/omarchy-switch`) — a stuck/startup-hung
  instance is now killed by pid and respawned instead of leaving an ownerless
  ghost window that keeps grabbing focus.
- **Previews for off-view / hidden windows** (`bin/omarchy-switch`) — cards for
  windows that Hyprland cannot render (other workspace, minimized) now show an
  opaque tile with the app's icon instead of a near-invisible placeholder; no
  exceptions during tile generation.

- **Zero window gaps** (`hypr/looknfeel.lua`) — override Omarchy's defaults
  (in 5 / out 10) with `gaps_in = 0` / `gaps_out = 0` so tiled windows use
  every pixel of the usable workspace, at the screen edges and between each
  other.
- **Single-window flush via smart-gaps workspace rules** (`hypr/looknfeel.lua`)
  — a workspace holding exactly one visible tiled window (`w[tv1]`, or one
  floating window `f[1]`) draws it without a border or corner rounding, so the
  single window renders truly edge-to-edge. This is the official Hyprland-Lua
  replacement for the old mainline `dwindle.no_gaps_when_only`, which this
  build rejects as an unknown config key (that key is removed, so the config
  loads with zero errors).
- **Bar workspace reservation follows bar mode** (`omarchy/plugins/bar-auto-hide`)
  — the always-visible bar is now an exclusive top layer that reserves its strip
  (tiled windows start below it), while auto-hide/off releases the strip so
  windows use the full screen. Toggling the mode resizes existing windows
  immediately; nothing needs a relaunch.
- **Portable helper paths** (`hypr/bindings.lua`) — invoke `omarchy-window-snap`
  and `omarchy-toggle-bar-mode` by bare name (already on `PATH`) instead of
  hard-coding `/home/sandy`, so the keybinding layer survives installs to any
  user home.

### Added

- **Reversed touchpad gestures** (`hypr/input.lua`) — 2-finger scroll flips on
  both axes (`natural_scroll = true`, Omarchy default is `false`),
  `workspace_swipe_invert = true` makes a left 3-finger swipe open the right
  (next) workspace, and 4-finger horizontal swipes open `omarchy-switch`
  (left = forward, right = back). Non-directional touchpad settings
  (tap-to-click, clickfinger, palm rejection, scroll factor) are deliberately
  untouched.
- **Visual app picker** (`bin/omarchy-switch`) — a borderless, floating GTK4
  overlay showing the current monitor's windows as **preview cards** (live
  window thumbnail on top, real app logo + name below). Previews are captured
  at the monitor's physical resolution (logical × scale, HiDPI-safe) and
  container-fitted into 220×120 cards so they never squish; the capture runs
  on a worker thread so the grid opens instantly. It stays up until Enter,
  click or **releasing Alt** (switch), Esc (cancel); more `Alt+Tab` presses /
  4-finger swipes move the selection. Opening it over a fullscreen app works,
  and confirming a window that was fullscreen restores its fullscreen state.
  `Alt+Tab` / `Alt+Shift+Tab` open it (replacing the `mogtabctl` flash
  overlay); a socket control plane moves/confirms/cancels the selection and a
  pidfile guard prevents duplicate instances.
- **Smooth picker opening** (`hypr/windows.lua`) — the picker window is
  `float` + `pin` and animates in with a `popin` animation, so 4-finger
  swipes feel smooth instead of snapping in.
- **Interactive installer** (`install.sh`) — `./install.sh` now opens an ↑/↓
  feature picker (fzf, whiptail fallback) instead of a dry run, with each
  installable file grouped into a feature type. Adds `--list`, `--menu`, and
  `--apply <type>` for feature-scoped installs; plain `--apply` (everything)
  and `--revert` are unchanged.

### Planned
- **Screenshots** — a `screenshots/` directory ready for community captures of
  the bar/taskbar on different hardware.
- **Flatpak field-testing** — the taskbar's icon resolver already handles
  `.desktop` entries under flatpak export dirs; confirm end-to-end on a machine
  with flatpaks installed.
- **Multi-monitor hardware pass** — verify `Super+Shift+↑/↓` window moves and
  monitor-scoped `Alt+Tab`/`Super+Tab` on a real multi-monitor rig.

## [1.0.0] - 2026-09-13

Initial public release of the developer-first interaction layer over Omarchy.

### Added

- **Standards-oriented keybinding layer** (`hypr/bindings.lua`)
  - `Super+Left/Right/Up/Down` → spatial move/swap and maximize/restore
  - `Super+Ctrl+Arrows` → directional focus; `Super+Alt+Arrows` → resize
  - `Super+Shift+←/→` → move window between workspaces; `Super+Shift+↑/↓` →
    move window between monitors
  - Standard conveniences: `Super+L` lock, `Super+E` files, `Super+B` (private)
    browser, `Ctrl+Alt+T` terminal, `Alt+F4` close, `Super+PrtSc` fullscreen
    screenshot, `Ctrl+Shift+M` mic mute
  - Removed/rebound dangerous or hijacking defaults: `Ctrl+Alt+Delete`,
    `Super+C/V/X` universal clipboard, `Super+Shift+Return` → browser
- **Spatial window management** (`bin/omarchy-window-snap`) — thin dwindle
  dispatcher wrapper: swap with neighbor, toggle maximize within layout, resize
  the shared boundary; edge actions are no-ops; works on Lua-DSL and plain
  hyprlang builds
- **Top bar** (`omarchy/plugins/bar-auto-hide`) — auto-hide + always-visible
  modes, persistent mode flag, configurable hide/reveal delays and activation
  zone, top-edge reveal on hover
- **Taskbar widget** (`omarchy/plugins/com.sandy.taskbar`)
  - Live window model of the current workspace (event-driven, no polling)
  - Click to focus/raise the exact client; middle/right-click graceful close
  - Bounded width — focused item gets a truncated title (cap configurable via
    `maxWidth`), inactive windows are compact icon chips
  - Real app icons: `app_id` → `.desktop` `Icon=` (incl. flatpak exports) →
    icon theme → fresh-disk icon index → generic fallback
- **Snap preview** (`omarchy/plugins/snap-preview`) — highlights the target
  zone while dragging to an edge/corner
- **App/workspace switcher** (`mogtab/`) — visual `Alt+Tab` (apps) and
  `Super+Tab` (workspaces), current-monitor scope, configurable
- **Installer** (`install.sh`) — dry-run default, `--apply` with timestamped
  backups, `--revert`; reloads Hyprland and restarts the switcher
- **Docs** — README, keybinding reference, contributing guide, security policy,
  MIT license

### Fixed
- Taskbar renders every open window (not only the active one) and never steals
  the clock/tray space regardless of title length.
- App icons that live outside the icon theme (or installed after the shell
  started) now resolve via a disk index instead of showing the generic file
  icon.
- Startup focus state seeded from the live `hyprctl` output so the correct chip
  is expanded right after login.