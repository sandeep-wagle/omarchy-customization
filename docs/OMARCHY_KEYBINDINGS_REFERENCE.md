# Omarchy Standardized Keybindings Reference

Reference for the standards-oriented keybinding layer in `hypr/bindings.lua`
— conventional, widely familiar bindings rather than bespoke ones. Terminal,
tmux, Vim, and application-level `Ctrl` conventions are left to the
applications.

---

## GLOBAL (Window Manager Level — Super/Meta key)

| Key | Action | Notes |
|-----|--------|-------|
| **Super** | (held) Modifier for WM commands | |
| **Super + Space** | Application launcher / Omarchy menu | Standard launcher |
| **Super + Return** | Terminal | Kept from Omarchy defaults |
| **Super + E** | File manager (Nautilus) | **Standard: Super+E** |
| **Super + B** | Browser | **Standard: Super+B** |
| **Super + Shift + B** | Browser (private) | |
| **Super + Shift + E** | Editor | |
| **Super + Shift + F** | File manager (alternative) | Legacy Omarchy binding |
| **Super + L** | **Lock screen** | **Standard: Super+L** (was workspace layout) |
| **Super + F** | Fullscreen toggle | Standard |
| **Super + Alt + F** | Maximize (full width) | Standard |
| **Super + W** | Close window | Tiling WM convention |
| **Alt + F4** | Close window | **Standard: Alt+F4** |
| **Super + T** | Toggle floating/tiling | Standard tiling WM |
| **Super + J** | Toggle split | |
| **Super + O** | Pop window (float & pin) | |
| **Super + P** | Pseudo window | |
| **Super + S** | Toggle scratchpad | |
| **Super + G** | Toggle window grouping | |
| **Super + Esc** | System menu | |
| **Super + K** | Show keybindings help | |

---

## WINDOW MANAGEMENT (Super + Arrows)

| Key | Action | Notes |
|-----|--------|-------|
| **Super + Left** | **Move/swap window left** (dwindle) | Edge = no-op |
| **Super + Right** | **Move/swap window right** (dwindle) | Edge = no-op |
| **Super + Up** | **Maximize within layout (toggle)** | Standard Win+Up behavior |
| **Super + Down** | **Move window down / restore** | Restores if maximized |
| **Super + Ctrl + Left** | Focus window left | Alternative navigation |
| **Super + Ctrl + Right** | Focus window right | Alternative navigation |
| **Super + Ctrl + Up** | Focus window up | Alternative navigation |
| **Super + Ctrl + Down** | Focus window down | Alternative navigation |
| **Super + Shift + Left** | Move window to previous workspace | |
| **Super + Shift + Right** | Move window to next workspace | |
| **Super + Shift + Up** | Move window to monitor up | Multi-monitor |
| **Super + Shift + Down** | Move window to monitor down | Multi-monitor |
| **Super + Mouse Left** | Move window (drag) | Standard |
| **Super + Mouse Right** | Resize window (drag) | Standard |

---

## WORKSPACE NAVIGATION (Super + Numbers)

| Key | Action |
|-----|--------|
| **Super + 1..9** | Switch to workspace 1..9 |
| **Super + 0** | Switch to workspace 10 |
| **Super + Shift + 1..9** | Move window to workspace 1..9 |
| **Super + Shift + 0** | Move window to workspace 10 |
| **Super + Tab** | Next workspace (visual switcher via mogtabctl) |
| **Super + Shift + Tab** | Previous workspace |
| **Super + Ctrl + Tab** | Former workspace (last used) |

---

## APPLICATION SWITCHING (Alt + Tab)

`Alt+Tab` / `Alt+Shift+Tab` open `omarchy-switch`: a borderless, floating GTK
picker listing the current monitor's windows with their app icons above a
snapshot of the current workspace. It stays up until Enter/click switches, Esc
cancels; pressing the shortcut again (or swiping 4-finger) moves the selection.

| Key | Action |
|-----|--------|
| **Alt + Tab** | App picker → next window (`omarchy-switch open next`) |
| **Alt + Shift + Tab** | App picker → previous window (`omarchy-switch open prev`) |

---

## TERMINAL / SHELL (Application Level — Ctrl key)

*These are NOT intercepted globally — they pass through to the terminal application.*

| Key | Action | Convention |
|-----|--------|------------|
| **Ctrl + C** | Interrupt current command | Universal |
| **Ctrl + D** | EOF / Exit shell | Universal |
| **Ctrl + Z** | Suspend process | Universal |
| **Ctrl + L** | Clear terminal | Universal |
| **Ctrl + A** | Beginning of line | Readline/Emacs |
| **Ctrl + E** | End of line | Readline/Emacs |
| **Ctrl + U** | Delete to beginning of line | Readline/Emacs |
| **Ctrl + K** | Delete to end of line | Readline/Emacs |
| **Ctrl + W** | Delete previous word | Readline/Emacs |
| **Ctrl + R** | Reverse history search | Universal |
| **Ctrl + P** | Previous history | Readline/Emacs |
| **Ctrl + N** | Next history | Readline/Emacs |
| **Alt + B** | Backward word | Readline/Emacs |
| **Alt + F** | Forward word | Readline/Emacs |
| **Ctrl + Shift + C** | Copy (terminal) | Terminal standard |
| **Ctrl + Shift + V** | Paste (terminal) | Terminal standard |

---

## TMUX (Prefix: Ctrl+Space / Ctrl+B)

*tmux prefix is **Ctrl+Space** (primary) and **Ctrl+B** (secondary). No global Hyprland bindings interfere.*

| Key | Action |
|-----|--------|
| **Ctrl + Space** | tmux prefix (primary) |
| **Ctrl + B** | tmux prefix (secondary) |
| **Prefix + \|** | Split pane horizontally |
| **Prefix + -** | Split pane vertically |
| **Prefix + h/j/k/l** | Navigate panes (vim-style) |
| **Prefix + 1..9** | Switch to window 1..9 |
| **Prefix + c** | New window |
| **Prefix + x** | Kill pane |
| **Prefix + ,** | Rename window |
| **Prefix + r** | Reload config |

---

## APPLICATION SHORTCUTS (Universal — Ctrl key)

*These are handled by individual applications, NOT intercepted by Hyprland.*

| Key | Action | Works In |
|-----|--------|----------|
| **Ctrl + C** | Copy | All GUI apps |
| **Ctrl + V** | Paste | All GUI apps |
| **Ctrl + X** | Cut | All GUI apps |
| **Ctrl + Z** | Undo | Most apps |
| **Ctrl + Shift + Z** | Redo | Most apps |
| **Ctrl + A** | Select all | Most apps |
| **Ctrl + F** | Find | Most apps |
| **Ctrl + S** | Save | Most apps |
| **Ctrl + O** | Open | Most apps |
| **Ctrl + N** | New window/file | Most apps |
| **Ctrl + W** | Close tab/window | Browsers, editors, terminals |
| **Ctrl + Q** | Quit application | Most apps |
| **Ctrl + T** | New tab | Browsers, terminals |
| **Ctrl + Shift + T** | Reopen closed tab | Browsers, terminals |
| **Ctrl + Tab** | Next tab | Browsers, terminals |
| **Ctrl + Shift + Tab** | Previous tab | Browsers, terminals |

---

## SCREENSHOTS

| Key | Action |
|-----|--------|
| **Print Screen** | Screenshot (region/window selection) |
| **Alt + Print Screen** | Screen recording |
| **Super + Print Screen** | Fullscreen screenshot |

---

## HARDWARE / MEDIA KEYS

| Key | Action |
|-----|--------|
| **XF86AudioRaiseVolume** | Volume up |
| **XF86AudioLowerVolume** | Volume down |
| **XF86AudioMute** | Mute toggle |
| **XF86AudioMicMute** | Microphone mute toggle |
| **XF86MonBrightnessUp** | Brightness up |
| **XF86MonBrightnessDown** | Brightness down |
| **XF86AudioPlay/Pause** | Play/Pause |
| **XF86AudioNext** | Next track |
| **XF86AudioPrev** | Previous track |
| **XF86Calculator** | Calculator |
| **XF86PowerOff** | Power menu |

---

## UTILITY / OMARCHY-SPECIFIC (Super + Ctrl + ...)

| Key | Action |
|-----|--------|
| **Super + Ctrl + V** | Clipboard manager |
| **Super + Ctrl + E** | Emoji picker |
| **Super + Ctrl + Q** | Calculator (omacalc) |
| **Super + Ctrl + T** | Activity monitor (btop) |
| **Super + Ctrl + N** | Toggle nightlight |
| **Super + Ctrl + I** | Toggle idle lock |
| **Super + Ctrl + Z** | Zoom in |
| **Super + Ctrl + Alt + Z** | Reset zoom |
| **Super + Comma** | Dismiss notification |
| **Super + Shift + Comma** | Dismiss all notifications |
| **Super + Ctrl + Comma** | Toggle notification silence |
| **Super + Shift + Space** | Toggle top bar mode (always-visible ↔ auto-hide) |
| **Super + Ctrl + Space** | Background switcher |
| **Super + Shift + Ctrl + Space** | Theme menu |
| **Super + Backspace** | Toggle window transparency |
| **Super + Shift + Backspace** | Toggle window gaps |
| **Super + Ctrl + Backspace** | Toggle single-window square aspect |

---

## HIERARCHY SUMMARY

```
APPLICATION LEVEL          → Ctrl / Alt / App-specific keys
    (terminal, browser, editor, VS Code, etc.)

TERMINAL / TMUX LEVEL      → Ctrl+B / Ctrl+Space (tmux prefix)
    (terminal conventions preserved)

WINDOW MANAGER LEVEL       → Super/Meta
    (window management, workspace, launcher, lock)

WORKSPACE LEVEL            → Super + Number
    (direct workspace switching)

WINDOW MOVEMENT            → Super + Arrows / Super + Mouse
    (snap, maximize, restore, move, resize)

APPLICATION SWITCHING      → Alt + Tab
    (standard desktop convention)

WORKSPACE SWITCHING        → Super + Tab / Super + Number
    (visual switcher + direct)

SECURITY                   → Super + L
    (standard lock screen)

LAUNCHER                   → Super + Space
    (standard application launcher)
```

---

## CHANGES FROM OMARCHY DEFAULTS

### Removed / Changed (conflicted with standards):
| Old Binding | Was | Now | Reason |
|-------------|-----|-----|--------|
| Super + L | Toggle workspace layout | **Lock screen** | Standard Super+L |
| Super + Shift + Left/Right | Swap window | Move to prev/next workspace | Standard workspace move |
| Super + Shift + Up/Down | Swap window | Move to monitor up/down | Multi-monitor standard |
| Super + Left/Right/Up/Down | Focus window | **Spatial move/swap + maximize** | Familiar Win+Arrow spatial behavior |
| Super + C/V/X | Universal copy/paste/cut | **Removed** | Hijacked Super layer; apps use Ctrl+C/V/X |
| Super + Print | Color picker | **Fullscreen screenshot** | Standard PrintScreen behavior |
| Ctrl + Alt + Delete | Close all windows | **Removed** | Dangerous (system reboot) |
| Super + Shift + Return | Browser | Super + B | Standard Super+B |

### Added (missing standards):
| New Binding | Action | Standard |
|-------------|--------|----------|
| **Super + E** | File manager | Windows/Ubuntu/Linux |
| **Ctrl + Alt + T** | Terminal | Universal Linux |
| **Alt + F4** | Close window | Universal desktop |
| **Super + B** | Browser | Common convention |
| **Super + Shift + E** | Editor | Common convention |

### Preserved (already standard or useful custom):
- All workspace navigation (Super+1-9, Super+Tab)
- All hardware/media keys (XF86)
- Alt+Tab application switching (omarchy-switch app picker)
- Mouse window management (Super+drag)
- Scratchpad, grouping, tiling commands
- Omarchy utility menus (clipboard, emoji, calculator, etc.)
- tmux compatibility (prefix C-Space/C-b untouched)

---

## TOUCHPAD GESTURES

Directional gestures are reversed in `hypr/input.lua` (loaded via
`require("hypr.input")`): swipe up scrolls down, swipe left advances.

| Gesture | Reversed behavior | Config |
|---------|-------------------|--------|
| 2-finger scroll | Both axes flipped | `input:touchpad:natural_scroll = true` |
| 3-finger horizontal swipe | Swap workspace direction: swipe **left** opens the right (next) workspace | `gestures:workspace_swipe_invert = true` |
| 4-finger left swipe | App picker → next | `omarchy-switch open next` |
| 4-finger right swipe | App picker → previous | `omarchy-switch open prev` |

Non-directional touchpad input (tap, clickfinger, pinch zoom) is untouched.
Browser back/forward lives in the application, not the compositor: it follows
the flipped horizontal scroll axis in most browsers, but Hyprland can't bind
browser history directly.

---

## ROLLBACK

To restore original Omarchy bindings:

```bash
cp ~/.config/hypr/bindings.lua.backup ~/.config/hypr/bindings.lua
hyprctl reload
```

Backup location: `~/.config/hypr/bindings.lua.backup`