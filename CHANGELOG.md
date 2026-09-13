# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/), versioned semantically.

The repository's history before the public release is consolidated; pre-release
development (the "phases" the configs still comment about) is summarized in the
`1.0.0` entry rather than preserved as a full commit-by-commit history.

## [Unreleased]

### Fixed

- **Consistent window gaps** (`hypr/looknfeel.lua`) — override Omarchy's
  defaults (in 5 / out 10) with `gaps_in = 4` / `gaps_out = 4`, and enable
  `dwindle.no_gaps_when_only` so a single tiled window fills its workspace
  edge-to-edge. Note: enabling the single-window-aspect-ratio toggle keeps a
  centered 1:1 video window and deliberately overrides the flush behavior.
- **Bar workspace reservation follows bar mode** (`omarchy/plugins/bar-auto-hide`)
  — the always-visible bar is now an exclusive top layer that reserves its strip
  (tiled windows start below it), while auto-hide/off releases the strip so
  windows use the full screen. Toggling the mode resizes existing windows
  immediately; nothing needs a relaunch.
- **Portable helper paths** (`hypr/bindings.lua`) — invoke `omarchy-window-snap`
  and `omarchy-toggle-bar-mode` by bare name (already on `PATH`) instead of
  hard-coding `/home/sandy`, so the keybinding layer survives installs to any
  user home.

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