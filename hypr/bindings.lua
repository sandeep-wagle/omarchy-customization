-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.
--
-- See current bindings and descriptions:
--   omarchy menu keybindings --print
--
-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false
--
-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- ============================================================
-- UNBIND PROBLEMATIC DEFAULTS
-- ============================================================

-- Super+L was "Toggle workspace layout" -> should be Lock screen
hl.unbind("SUPER + L")

-- Super+Shift+Left/Right/Up/Down was "Swap window" -> should be move to workspace/monitor
hl.unbind("SUPER + SHIFT + LEFT")
hl.unbind("SUPER + SHIFT + RIGHT")
hl.unbind("SUPER + SHIFT + UP")
hl.unbind("SUPER + SHIFT + DOWN")

-- Super+Print was "Color picker" -> should be fullscreen screenshot
hl.unbind("SUPER + PRINT")

-- Ctrl+Alt+Delete was "Close all windows" -> DANGEROUS, remove
hl.unbind("CTRL + ALT + DELETE")

-- Super+C/V/X universal clipboard -> hijacks Super layer, apps use Ctrl+C/V/X
hl.unbind("SUPER + C")
hl.unbind("SUPER + V")
hl.unbind("SUPER + X")

-- Super+Shift+Return for browser -> non-standard
hl.unbind("SUPER + SHIFT + RETURN")

-- Super+Left/Right/Up/Down focus navigation -> replace with Super+Ctrl+Arrow
hl.unbind("SUPER + LEFT")
hl.unbind("SUPER + RIGHT")
hl.unbind("SUPER + UP")
hl.unbind("SUPER + DOWN")

-- Super+Shift+B for browser -> will replace with Super+B and Super+Shift+B for private
hl.unbind("SUPER + SHIFT + B")

-- Super+Ctrl+Left/Right for group focus -> replace with focus navigation
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")

-- ============================================================
-- STANDARD WINDOW MANAGEMENT (Super-based hierarchy)
-- ============================================================

-- Spatial window management (BSP / dwindle):
--   Super+Arrow       = move/swap window spatially within the layout tree
--   Super+Alt+Arrow   = resize shared boundary between window and neighbor
--   Super+Shift+Arrow = move to workspace/monitor
--   Super+Ctrl+Arrow  = focus navigation
--
-- Implemented on top of Hyprland's native dwindle layout, which manages the
-- binary-space-partition tree. ~/.local/bin/omarchy-window-snap is a thin
-- wrapper issuing the dwindle dispatchers (swapwindow / maximize resize) —
-- no custom geometry math.
--
--   Super+Up   = toggle maximize-within-layout for the focused window
--   Super+Down = move the focused window down (swap with the region below);
--                at the bottom edge, restores from maximized instead

-- Super+Arrow = spatial move/snap
o.bind("SUPER + LEFT", "Swap window left", "/home/sandy/.local/bin/omarchy-window-snap left")
o.bind("SUPER + RIGHT", "Swap window right", "/home/sandy/.local/bin/omarchy-window-snap right")
o.bind("SUPER + UP", "Toggle maximize in layout", "/home/sandy/.local/bin/omarchy-window-snap up")
o.bind("SUPER + DOWN", "Move window down / restore", "/home/sandy/.local/bin/omarchy-window-snap down")

-- Super+Alt+Arrow = resize shared boundary between window and neighbor
--   Alt+Left  → grow left region   Alt+Right → grow right region
--   Alt+Up    → grow above         Alt+Down  → grow below
o.bind("SUPER + ALT + LEFT", "Resize window (narrower)", "/home/sandy/.local/bin/omarchy-window-snap resize-left")
o.bind("SUPER + ALT + RIGHT", "Resize window (wider)", "/home/sandy/.local/bin/omarchy-window-snap resize-right")
o.bind("SUPER + ALT + UP", "Resize window (shorter)", "/home/sandy/.local/bin/omarchy-window-snap resize-up")
o.bind("SUPER + ALT + DOWN", "Resize window (taller)", "/home/sandy/.local/bin/omarchy-window-snap resize-down")

-- Super+Ctrl+Arrow = focus navigation
o.bind("SUPER + CTRL + LEFT", "Focus left", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + CTRL + RIGHT", "Focus right", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + CTRL + UP", "Focus up", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + CTRL + DOWN", "Focus down", hl.dsp.focus({ direction = "d" }))

-- Super+Shift+Left/Right = move window to prev/next workspace
o.bind("SUPER + SHIFT + LEFT", "Move window to previous workspace", hl.dsp.window.move({ workspace = "e-1" }))
o.bind("SUPER + SHIFT + RIGHT", "Move window to next workspace", hl.dsp.window.move({ workspace = "e+1" }))

-- Super+Shift+Up/Down = move window to up/down monitor (multi-monitor)
o.bind("SUPER + SHIFT + UP", "Move window to monitor up", hl.dsp.window.move({ monitor = "u" }))
o.bind("SUPER + SHIFT + DOWN", "Move window to monitor down", hl.dsp.window.move({ monitor = "d" }))

-- ============================================================
-- WORKSPACE NAVIGATION (Super+Number)
-- ============================================================
-- Already handled by defaults (Super+1..9, Super+Shift+1..9)
-- Super+Tab = workspace switcher (already in defaults, overridden in user config)

-- ============================================================
-- APPLICATION SWITCHING (Alt+Tab)
-- ============================================================
-- Already handled: Alt+Tab, Alt+Shift+Tab (user config uses mogtabctl)

-- ============================================================
-- SECURITY
-- ============================================================
-- Super+L = Lock screen (standard)
o.bind("SUPER + L", "Lock screen", "omarchy-system-lock")

-- ============================================================
-- LAUNCHER
-- ============================================================
-- Super+Space = Launcher (already in defaults)

-- ============================================================
-- FILE MANAGER
-- ============================================================
-- Super+E = File manager (standard)
o.bind("SUPER + E", "File manager", { omarchy = "nautilus" })

-- ============================================================
-- TERMINAL
-- ============================================================
-- Ctrl+Alt+T = Terminal (standard Linux)
o.bind("CTRL + ALT + T", "Terminal", { omarchy = "terminal" })

-- ============================================================
-- WINDOW CLOSE
-- ============================================================
-- Alt+F4 = Close window (standard)
o.bind("ALT + F4", "Close window", hl.dsp.window.close())

-- Keep Super+W as alternative close (tiling WM convention)

-- ============================================================
-- SCREENSHOTS
-- ============================================================
-- PrintScreen = Screenshot (already in defaults)
-- Alt+PrintScreen = Screen recording (already in defaults)
-- Super+PrintScreen = Fullscreen screenshot
o.bind("SUPER + PRINT", "Fullscreen screenshot", "omarchy-capture-screenshot --fullscreen")

-- ============================================================
-- MEDIA/HARDWARE KEYS
-- ============================================================
-- Already handled by defaults (XF86 keys) - keep as-is

-- Ctrl+Shift+M = Toggle microphone mute (3-key combo)
o.bind("CTRL + SHIFT + M", "Toggle microphone mute", "omarchy-audio-input-mute", { locked = true })

-- ============================================================
-- UNBIND DEFAULT BAR TOGGLE (replaced with mode toggle)
-- ============================================================
hl.unbind("SUPER + SHIFT + SPACE")

-- Super+Shift+Space = Toggle top bar mode (always-visible <-> auto-hide)
o.bind("SUPER + SHIFT + SPACE", "Toggle top bar mode", "/home/sandy/.local/bin/omarchy-toggle-bar-mode")

-- ============================================================
-- UTILITY BINDINGS (keep useful custom ones)
-- ============================================================

-- Super+K = Keybindings help
-- Super+Ctrl+V = Clipboard manager
-- Super+Ctrl+E = Emojis
-- Super+Comma = Dismiss notification
-- Super+Shift+Comma = Dismiss all notifications
-- Super+Ctrl+N = Toggle nightlight
-- Super+Ctrl+I = Toggle idle lock
-- Super+Ctrl+Z = Zoom in
-- Super+Ctrl+Alt+Z = Reset zoom
-- Super+Ctrl+Q = Calculator
-- Super+Ctrl+T = Activity (btop)
-- Super+G = Toggle window grouping
-- Super+mouse:left = Move window
-- Super+mouse:right = Resize window

-- ============================================================
-- ADDITIONAL STANDARD SHORTCUTS
-- ============================================================

-- Super+F = Fullscreen (already in defaults)
-- Super+Alt+F = Maximize (already in defaults)
-- Super+T = Toggle floating (already in defaults)
-- Super+J = Toggle split (already in defaults)
-- Super+O = Pop window (already in defaults)
-- Super+S = Scratchpad (already in defaults)

-- Workspace navigation (already in defaults)
-- Super+Tab = Next workspace
-- Super+Shift+Tab = Prev workspace
-- Super+Ctrl+Tab = Former workspace

-- Monitor focus (already in defaults)
-- Ctrl+Alt+Tab = Next monitor
-- Ctrl+Alt+Shift+Tab = Prev monitor

-- ============================================================
-- APPLICATION LAUNCHERS (keep useful ones, standardize others)
-- ============================================================

-- Browser: Super+B (standard) instead of Super+Shift+Return
o.bind("SUPER + B", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + B", "Browser (private)", { omarchy = "browser --private" })

-- Editor: Super+Shift+E (standard-ish)
o.bind("SUPER + SHIFT + E", "Editor", { omarchy = "editor" })

-- Keep Super+Shift+F for file manager (already have Super+E now)
-- Keep other app bindings that don't conflict

-- ============================================================
-- RESIZE BINDINGS (keep existing sophisticated ones)
-- ============================================================
-- Already in defaults: Super+[+/-] for resize, Super+Ctrl+[+/-] for big resize
-- Super+Shift+[+/-] for vertical resize
-- Super+Alt+[+/-] for small resize