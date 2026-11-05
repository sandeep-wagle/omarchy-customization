# Omarchy Hyprland Config

Personal Hyprland customizations for [Omarchy](https://omarchy.org/) (Arch + Hyprland).
These files live in `~/.config/hypr/` and load **after** Omarchy's defaults, so an
`omarchy update` never touches them — only `omarchy refresh hyprland` resets this
directory (this repo is the undo button for that).

## What's inside

| File | Customization |
|------|---------------|
| `bindings.lua` | Full keybinding scheme: Super+Arrow spatial snap, Super+Ctrl+Arrow focus, Super+Shift+Arrow move to workspace/monitor, Alt+Tab app switcher, Super+B browser, Super+E files, Ctrl+Alt+T terminal, Super+L lock |
| `windows.lua` | Dwindle-native tiling rules, omarchy-switch picker styling, Android emulator tiling |
| `autostart.lua` | `mogtab`, `omarchy-switch daemon`, `omarchy-fullscreen-watch`, `omarchy-emulator-snap` |
| `looknfeel.lua` | Zero gaps/borders, dim-inactive focus indicator, drag-to-snap |
| `input.lua` | Reversed (non-natural) touchpad scroll + workspace swipe |
| `monitors.lua` | Forced 16:9 `1920x1080`, eDP-1 at 144Hz |
| `envs.lua` | `LIBVA_DRIVER_NAME=iHD` |

## Restore on a fresh machine

```bash
git clone <this-repo> ~/.config/hypr
hyprctl reload && hyprctl configerrors
```

## After changing anything

```bash
hyprctl reload && hyprctl configerrors
git commit -am "describe the change" && git push
```
