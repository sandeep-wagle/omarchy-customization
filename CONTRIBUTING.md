# Contributing

Thanks for considering a contribution. This project is a developer-focused
layer over Omarchy/Hyprland, and it stays useful only if every documented
claim stays true. **Never document what isn't implemented; never implement
what isn't documented.**

## Ways to contribute

- **Report a bug** — open an issue; include your hardware (GPU, monitor(s),
  laptop/desktop), Omarchy/Hyprland versions, and what you expected vs. saw.
- **Test on your hardware** — multi-monitor (`Super+Shift+↑/↓`, monitor-scoped
  `Alt+Tab`) and Flatpak icon resolution are implemented but field-tested on
  only one machine so far. Report what works and what doesn't.
- **Suggest keybindings** — propose a *widely familiar* convention (Super layer
  for desktop, Ctrl layer left to apps). If a change removes or re-maps a
  binding, say which existing muscle memory it serves.
- **Screenshots** — add captures of the bar/taskbar on different setups to a
  new `screenshots/` directory (name them `bar-auto-hide`, `taskbar-brave`, …).
- **Docs & architecture** — improve the README, the keybinding reference, or
  the installer.

## Before you start

- Read the [README](README.md) so the feature and its status are clear.
- Check [Feature status](README.md#feature-status): a feature marked **Working**
  may rely on Hyprland behavior or untested hardware — don't claim it as +
  than it is.

## Development loop

Two copies of the configs exist: the live ones under `~/.config/...` and the
repo under `~/omarcy_customization` (or your clone).

1. Make sure you can install and revert safely first — run
   `./install.sh --apply` (backs everything up), then `./install.sh --revert`.
2. Edit the **repo** files. To test a change without touching the install:
   copy the file to its live path, then reload:
   - Hyprland config → `hyprctl reload` (or `omarchy menu keybindings --print`),
   - bar/Quickshell plugins → `omarchy-restart-shell`.
3. When a change is accepted, re-run `./install.sh` (dry run) to confirm the
   `PAIRS` list still covers every new file. If you added a file, add its
   `relative|$HOME-destination` pair to `install.sh` **in the same commit**.

## Where each change belongs

| Change | File(s) |
|---|---|
| Keybinding | `hypr/bindings.lua` + `docs/OMARCHY_KEYBINDINGS_REFERENCE.md` |
| Window rules / tiling behavior | `hypr/windows.lua`, `hypr/looknfeel.lua` |
| Snapping/maximize/resize logic | `bin/omarchy-window-snap` |
| Top-bar layout | `omarchy/shell.json` |
| Bar behavior (auto-hide, slots) | `omarchy/plugins/bar-auto-hide/` |
| Taskbar rendering / icon resolution | `omarchy/plugins/com.sandy.taskbar/TaskbarWidget.qml` |
| Snap preview | `omarchy/plugins/snap-preview/SnapPreview.qml` |
| Alt+Tab / Super+Tab behavior | `mogtab/config.toml` |
| Installer / backup / revert | `install.sh` |
| Docs | `README.md`, `docs/`, `CONTRIBUTING.md` |

## Commit conventions

- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`), one
  logical change per commit.
- If you touch `install.sh`'s `PAIRS`, say so in the commit message.
- Keep the working tree green after each commit (configs load without errors
  after `hyprctl reload` / `omarchy-restart-shell`).

## Pull requests

- Small, focused PRs are preferred.
- Prefer a config that is inert by default (disabled/harmless) over one that
  forces users to act.
- Don't fix unrelated formatting in the same PR as a behavior change.

Nothing here requires a CLA; by submitting a PR you agree your contribution is
licensed under this project's [MIT license](LICENSE).