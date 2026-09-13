# Developer-first Omarchy

> A polished, standards-oriented desktop workflow for developers who live
> between terminals, tmux, IDEs, browsers, VMs, SSH sessions, remote servers,
> and multiple operating systems.

**Keep Omarchy's power. Keep Hyprland's speed. Keep your developer muscle memory.**

This project is an opinionated interaction layer on top of
[Omarchy](https://omarchy.org): it keeps the compositor, the bar, and the
window-management engine Omarchy provides, and replaces the interaction model
with one that is *widely familiar* to developers coming from Windows, macOS,
GNOME/KDE, tmux, and Vim-style workflows — so the keyboard behaves predictably
no matter which machine you happen to be sitting at.

It is **not** an attempt to turn Omarchy into Windows, and it is not a fork of
anything. It is a set of Hyprland override configs, Quickshell bar plugins, and
small helper scripts that ship, install, and revert through one script.

---

## Why this project exists

Modern development crosses environments constantly. The same day can look like:

```
local desktop
  └─ terminal
      └─ tmux
          └─ SSH
              └─ remote Linux server
                  ├─ VM
                  ├─ container
                  └─ cloud machine
                        └─ IDE / browser
```

The least productive thing an operating system can do is make a developer
**relearn shortcuts** when the host changes. Wherever a desktop shortcut can be
chosen to match an industry-common convention instead of a bespoke one, this
project chooses the familiar one — while leaving application-level conventions
(tmux prefixes, Vim keybindings, IDE edit keys) untouched inside their
applications.

The explicit goal: **reduce unnecessary relearning** for developers working
across local desktops, remote machines, VMs, and containers.

---

## Design principles

### The modifier layer separation

Desktop operations and application operations are intentionally split, following
widespread conventions in Windows/Linux/macOS:

| Modifier layer | Owns |
|---|---|
| **Super / Meta** | desktop + window-management: snapping, moving, workspaces, launcher, lock |
| **Ctrl** | application / terminal / editor conventions — **left available to apps** |
| **Alt** | common window/application actions: `Alt+Tab`, `Alt+F4` |
| **tmux / Vim / terminal** | preserved, untouched, inside the terminal |

No rule here claims a single "universal standard" exists — it doesn't. The goal
is to be **standards-oriented**: pick the convention that is *widely familiar*
in each layer, keep the modifier hierarchy consistent, and avoid muscle-memory
conflicts across environments.

### The core rule

> The desktop manages the desktop.
> Applications manage their own editing commands.
> Terminals keep terminal conventions. tmux keeps tmux conventions.
> Vim/Neovim keeps Vim conventions. IDEs keep IDE conventions.

That's why the global clipboard hack (`Super+C/V/X` taking over the Ctrl
clipboard) is **removed** — apps and terminals keep their native Ctrl+* keys.

---

## What's included

| Component | Where | What it does |
|---|---|---|
| Spatial window manager binding layer | `hypr/*.lua`, `bin/omarchy-window-snap` | Super+Arrow move/maximize, Super+Ctrl+Arrow focus, Super+Alt+Arrow resize, Super+Shift+Arrow move between workspaces/monitors — built on Hyprland's native dwindle (BSP) layout |
| Taskbar widget | `omarchy/plugins/com.sandy.taskbar` | Windows/Ubuntu-style taskbar in the top bar: every open window on the current workspace with its **real app icon**, click to focus, middle/right to close, bounded width |
| Top bar with auto-hide | `omarchy/plugins/bar-auto-hide` | Omarchy status bar that shows system widgets + the taskbar; auto-hides when idle, toggled with `Super+Shift+Space`, mode persists across login |
| Snap preview | `omarchy/plugins/snap-preview` | Highlights the destination zone while dragging a floating window to an edge/corner |
| App & workspace switcher | `mogtab/`, `bin/mogtab`, `bin/mogtabctl` | Visual `Alt+Tab` (applications) and `Super+Tab` (workspaces), per current monitor |
| Native drag-to-snap | `hypr/looknfeel.lua` | Drag a floating window to a monitor edge/corner to snap half/quarter |
| Standards-oriented keybindings | `hypr/bindings.lua` | Super+L lock, Super+E files, Super+B browser, Ctrl+Alt+T terminal, Alt+F4 close, Print fullscreen screenshot, and more (see reference) |
| Installer with safe backups | `install.sh` | Backs up every changed file, then installs; one-command revert |

---

## Keybinding reference

Full detail lives in [`docs/OMARCHY_KEYBINDINGS_REFERENCE.md`](docs/OMARCHY_KEYBINDINGS_REFERENCE.md).
Tables below are generated from the actual configuration. "**this project**"
means the binding is defined by this repository; "**Omarchy**" means it is a
stock Omarchy default that this project keeps or relies on.

### Desktop & window management (Super)

| Action | Shortcut | Source |
|---|---|---|
| Move/swap window left | `Super + Left` | this project |
| Move/swap window right | `Super + Right` | this project |
| Maximize within layout (toggle) | `Super + Up` | this project |
| Move window down / restore | `Super + Down` | this project |
| Focus window left/right/up/down | `Super + Ctrl + ←/→/↑/↓` | this project |
| Resize shared boundary (4 dirs) | `Super + Alt + ←/→/↑/↓` | this project |
| Move window to prev/next workspace | `Super + Shift + ←/→` | this project |
| Move window to monitor up/down | `Super + Shift + ↑/↓` | this project |
| Close window | `Alt + F4` · `Super + W` | this project · Omarchy |
| Fullscreen | `Super + F` | Omarchy |
| Maximize (full width) | `Super + Alt + F` | Omarchy |
| Toggle floating / split / pop | `Super + T` · `Super + J` · `Super + O` | Omarchy |
| Toggle window grouping | `Super + G` | Omarchy |
| Move window (drag) / resize (drag) | `Super + mouse:left` / `mouse:right` | Omarchy |

### Application launching (Super / Ctrl)

| Action | Shortcut | Source |
|---|---|---|
| Launcher / menu | `Super + Space` | Omarchy |
| Terminal | `Super + Return` · `Ctrl + Alt + T` | Omarchy · this project |
| File manager (Nautilus) | `Super + E` | this project |
| File manager (alt) | `Super + Shift + F` | Omarchy |
| Browser / private browser | `Super + B` · `Super + Shift + B` | this project |
| Editor | `Super + Shift + E` | this project |

### Workspaces (Super + number)

| Action | Shortcut | Source |
|---|---|---|
| Switch to workspace 1–9 / 10 | `Super + 1…9` · `Super + 0` | Omarchy |
| Move window to workspace | `Super + Shift + 1…9` / `0` | Omarchy |
| Next/prev workspace (visual) | `Super + Tab` · `Super + Shift + Tab` | Omarchy + mogtab |
| Former workspace | `Super + Ctrl + Tab` | Omarchy |

### Application & monitor switching (Alt)

| Action | Shortcut | Source |
|---|---|---|
| Next/prev window (visual switcher) | `Alt + Tab` · `Alt + Shift + Tab` | mogtab (current monitor) |
| Next/prev monitor | `Ctrl + Alt + Tab` · `Ctrl + Alt + Shift + Tab` | Omarchy |

### System & security

| Action | Shortcut | Source |
|---|---|---|
| Lock screen | `Super + L` | this project |
| Region screenshot / screen recording | `PrintScreen` · `Alt + PrintScreen` | Omarchy |
| Fullscreen screenshot | `Super + PrintScreen` | this project |
| Toggle top bar mode (always-visible ↔ auto-hide) | `Super + Shift + Space` | this project |
| Toggle microphone mute | `Ctrl + Shift + M` | this project |
| Volume / brightness / playback | `XF86*` media keys | Omarchy |

### Terminal, tmux & application conventions (Ctrl — *not bound*)

The following are deliberately **not** grabbed by the window manager. They
belong to the focused application, exactly as in every other desktop:

`Ctrl+C`, `Ctrl+V`, `Ctrl+X`, `Ctrl+Z`, `Ctrl+A`, `Ctrl+E`, `Ctrl+R`,
`Ctrl+S`, `Ctrl+O`, `Ctrl+T`, `Ctrl+W`, `Ctrl+Q`, `Ctrl+Tab`, and the terminal
clipboard pair `Ctrl+Shift+C` / `Ctrl+Shift+V`. The tmux prefix
(`Ctrl+B` / `Ctrl+Space` per your tmux config) is likewise untouched.

See the [reference](docs/OMARCHY_KEYBINDINGS_REFERENCE.md) for the full
per-application table.

---

## Terminal & tmux friendly

The default philosophy is to **leave application-level `Ctrl` bindings
available to the application/terminal layer**. Desktop-level work lives on the
`Super` layer, so nothing in this project steals `Ctrl+C`, `Ctrl+R`, `Ctrl+Z`,
or the readline/terminal editing keys. Two concrete choices make this explicit:

- The Omarchy universal-clipboard bindings (`Super+C/V/X`) are **unbound** so
  terminals and apps keep their native clipboard keys.
- No `Ctrl+B` / `Ctrl+Space` (common tmux prefixes) or Vim/Neovim keys are bound
  at the desktop level — tmux sessions over SSH, persistent sessions, server
  administration, and long-running processes work unchanged.

Nothing here can guarantee that every possible terminal, shell, tmux setup, and
Vim configuration coexists conflict-free — that depends on the tools you run.
What this project guarantees is that the **desktop itself** stays out of the
way.

---

## Built for developers who work remotely

Switching between a local desktop, an SSH session, a remote server, a VM, a
container, or a cloud machine should not force you to relearn application
shortcuts. Because this project keeps `Alt`/`Ctrl` conventions inside their
applications and limits desktop actions to `Super`, the muscle memory transfers
unchanged when the host environment changes. That is a core project philosophy,
not an afterthought.

## Designed for multi-environment development

VMs, dual-boot systems, remote Linux servers, containers, development
workstations, multiple monitors and heterogeneous hardware are first-class
targets. The goal is not to make every operating system identical — each app
keeps its native keyboard conventions. The goal is to provide a **familiar
desktop interaction layer** on top of Omarchy so the surface you touch most
(the window manager) behaves predictably everywhere.

Multi-monitor is handled with direction-aware, industry-common actions:
`Super+Shift+↑/↓` moves the focused window to the monitor above/below, and
`Alt+Tab` / `Super+Tab` cycle within the current monitor by default (configurable
in `mogtab/config.toml`).

---

## Spatial multitasking

Window management follows a single, predictable modifier hierarchy:

| Modifier combo | Meaning |
|---|---|
| `Super + Arrow` | **position/movement** — move/swap the focused window in that direction |
| `Super + Ctrl + Arrow` | **focus only** — move focus without moving the window |
| `Super + Shift + Arrow` | **move across** — workspace (←/→) or monitor (↑/↓) |
| `Super + Alt + Arrow` | **resize** — grow/shrink the shared boundary with the neighbor |

One hierarchy, directional semantics, no accidental destructive actions (an
arrow at the workspace edge is a no-op, not a loss). This is implemented on
top of Hyprland's native **dwindle** layout — a binary-space-partition tree —
via the thin `omarchy-window-snap` dispatcher wrapper, so there is no custom
geometry math to maintain.

Layout arrangement (2 windows split, 3 adaptive, 4 windows 2×2 grid) is
produced by Hyprland's dwindle engine itself as windows open and close — this
project enables and respects it, it does not reimplement it.

---

## Application & window lifecycle

- **Switching workspaces ≠ closing applications.** Moving a window to another
  workspace (`Super+Shift+←/→`) leaves the process running; it just lives on
  another workspace.
- The **taskbar represents real windows**, not launcher entries. Each chip is an
  exact Hyprland client identified by its address.
- **Click an app in the taskbar** → focuses that *existing* window (address-
  precise `hyprctl` dispatch), raises it above floating peers, restores it if
  minimized, and never spawns a duplicate instance — repeated clicks are no-ops.
- **Middle / right-click** → graceful close request; the window stays alive
  until the application agrees.

For accuracy: the taskbar lists the windows of the **current workspace** (the
compositor's `focusedWorkspace` model). A window elsewhere on the desktop still
exists — it just isn't offered as a chip on this workspace. Closing/minimizing/
focusing is the application's and the compositor's business, not the taskbar's.

---

## Interface: a single top activity bar

The screen has **one bar**, at the top:

- **Left** — launcher menu + the **taskbar** (running apps on the current
  workspace). This is where activity lives.
- **Center** — Omarchy's system widgets (indicators, clock, keyboard layout,
  weather, system updates).
- **Right** — system tray + agents, Bluetooth, network, audio, monitor, power.

There is **no separate bottom dock**. The taskbar — the "application + running
windows + activity" area — lives inside the top bar on the left. Top bar and
taskbar are one Quickshell surface.

**Bar modes** (toggle with `Super+Shift+Space` or `omarchy-toggle-bar-mode`):

- **Always-visible** — the bar stays on screen and its layer is exclusive: the
  top strip of the workspace is reserved, so tiled windows start below the bar
  and never slide underneath it.
- **Auto-hide** — the bar retracts off-screen when idle and no pointer is over
  it, and reveals when the pointer nears the top edge (activation zone ~6px,
  reveal delay 60ms, hide delay 600ms — all tunable from the bar config). The
  reserved strip is released in this mode, so windows use the full screen height
  and the bar only overlays while revealed.

Switching modes resizes the tiled windows immediately (no relaunch needed).

The mode persists across login via a state flag under
`~/.local/state/omarchy/toggles`; the bar reads it on startup.

---

## Installation & recovery

### Prerequisites
- An Omarchy-flavored Hyprland install (Lua config build; config lives at
  `~/.config/hypr`, shell at `~/.config/omarchy`).
- `hyprctl`, `jq`, `omarchy` shell commands on `PATH`.

### Install
```sh
git clone https://github.com/sandeep-wagle/omarchy-customization.git
cd omarchy-customization

./install.sh        # dry run: prints exactly what would change
./install.sh --apply
omarchy-restart-shell   # reload the Quickshell bar plugins
```

`--apply` copies every file from the repo to its real destination, taking a
fresh timestamped backup of anything it overwrites first:

- `hypr/*.lua`, `hypr/hyprland.conf` → `~/.config/hypr/`
- `omarchy/shell.json`, `omarchy/shell.toml`, `omarchy/plugins/*` → `~/.config/omarchy/`
- `bin/*` → `~/.local/bin/` (made executable)
- `mogtab/config.toml` → `~/.config/mogtab/`
- `toggles/*` → `~/.local/state/omarchy/toggles/`
- then `hyprctl reload` and a `mogtab` restart (if running).

### Verify
- The top bar shows the taskbar in its left section.
- `Super+Up` maximizes the focused window; `Super+Left` swaps it.
- `Alt+Tab` cycles applications; `Super+PrtSc` captures the screen.

### Revert
```sh
./install.sh --revert   # restores the most recent backup
```
Backups live in `~/backups/omarchy-customization/<timestamp>/`. Nothing is ever
deleted during install.

---

## Feature status

| Feature | Status |
|---|---|
| Standards-oriented keybindings (Super/Ctrl/Alt separation) | Stable |
| Terminal/tmux-friendly bindings (Ctrl layer left to apps) | Stable |
| Spatial window management (move / focus / resize / workspace) | Stable |
| Taskbar over the live window model (click-to-focus, close, bounded width) | Stable |
| Real app-icon resolution (.desktop → theme → disk index) | Stable |
| Auto-hide top bar + persistent mode toggle | Stable |
| Snap preview while dragging to an edge/corner | Stable |
| Native drag-to-snap (Hyprland `general:snap`) | Stable |
| Visual `Alt+Tab` / `Super+Tab` (mogtab, current-monitor scope) | Stable |
| Dynamic dwindle tiling (2/3/4-window arrangements) | Working — provided by Hyprland's dwindle engine |
| Multi-monitor move (`Super+Shift+↑/↓`) and monitor-scoped switching | Working — implemented; needs real multi-monitor hardware to field-test |
| Single-window aspect-ratio toggle | Working — enabled via `toggles/` state file |
| Flatpak app icons (`.desktop` under flatpak export dirs) | Working — implemented in the resolver; not yet field-tested on a machine with flatpaks |
| Bottom dock | Not included — the taskbar lives in the top bar |

Anything marked **Working** is implemented and wired up, but either relies on
hyprland behavior rather than custom code, or awaits hardware (multi-monitor,
flatpak runtimes) this box could not provide. See [Contributing](CONTRIBUTING.md)
for how to help close those gaps.

---

## Open source & contributions

This project is intentionally open. Help is welcome for any of:

- reporting issues and suggesting keybinding improvements
- Hyprland config improvements and hardware compatibility reports
- Quickshell/bar component improvements (taskbar, auto-hide, snap preview)
- documentation, themes, and helper scripts
- developer-workflow ideas and bug fixes

Because Linux desktop behavior varies by GPU, laptop firmware, monitor,
keyboard, touchpad, docking station and multi-monitor setup, **community
hardware testing is uniquely valuable**: *install it, and report what works and
what doesn't.* Screenshots of the bar/taskbar on different setups are also
welcome — the `screenshots/` directory doesn't exist yet, and your captures
could seed it.

### Structure for contributors

```
Hyprland (hyprland.lua bootstrap)
├── bindings.lua   → keybinding layer (Super/Ctrl/Alt hierarchy)
├── looknfeel.lua  → look & feel, native drag-to-snap
├── windows.lua    → window rules / dwindle behavior
├── monitors.lua   → output/mode configuration
├── autostart.lua  → launches mogtab on login
│
└── Quickshell (shell.json → bar.auto-hide)
    ├── Bar.qml / BarModel.js            → the top bar + widget slots
    ├── plugins/com.sandy.taskbar/       → the taskbar widget
    └── plugins/snap-preview/            → drag-to-snap highlight
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the dev loop and where each change
belongs.

---

## What this project is not

- Not a fork or reimplementation of Omarchy/Hyprland — it is an opinionated
  interaction layer on top of them.
- Not a "Windows clone" — Vim, tmux, terminals, and tiling-WM conventions are
  preserved wherever they're already good.
- Not a claim that one keyboard layout is objectively best — it's a
  *consistently familiar* one, weighted toward conventions developers meet in
  more than one environment.

---

## License

[MIT](LICENSE). Docs keybinding reference:
[`docs/OMARCHY_KEYBINDINGS_REFERENCE.md`](docs/OMARCHY_KEYBINDINGS_REFERENCE.md).
Changes are tracked in [CHANGELOG.md](CHANGELOG.md); security notes in
[SECURITY.md](SECURITY.md).