-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Phase 2: native drag-to-snap. Dragging a floating window to a monitor
-- edge/corner snaps it to half/quarter of the usable workspace, like
-- Windows/Ubuntu. Threshold gap is snap:window_gap.
--
-- Gaps & frames: Omarchy's defaults (gaps_in = 5, gaps_out = 10, border_size
-- = 2) leave dead space at the screen edges, between windows, and draw a
-- 2px border line on every tiled window. Zero it all: windows use every
-- pixel of the usable workspace, and since borders are gone, the focus
-- indicator switches to dimming — the active window stays full-bright while
-- inactive windows are slightly dimmed (see decoration below).
hl.config({
  general = {
    snap = {
      enabled = true,
    },

    gaps_in = 0,
    gaps_out = 0,
    -- 1px border (not 0): the resize drag only starts on presses OUTSIDE the
    -- window content rect (Hyprland 0.56.2 InputManager), and border pixels
    -- live outside that rect -- so this 1px line is what makes screen-edge
    -- and seam grabs reachable. Near-invisible; dimming stays the focus cue.
    border_size = 1,

    -- Windows-style pointer resizing (overrides Omarchy default
    -- resize_on_border = false in /usr/share/omarchy/default/hypr).
    -- Hover any window edge/corner -> directional resize cursor appears;
    -- press + drag resizes; tiled neighbors adapt via dwindle; works on
    -- floating, XWayland (incl. emulator, min 200x200 respected) and Wayland.
    -- Kept at the 15px default grab zone on purpose: our gaps/borders are 0
    -- so this is the ONLY grab area, and a wider zone would steal
    -- press-and-drag interactions (e.g. text selection) near window edges.
    -- resize_corner intentionally left at default 0: it only forces which
    -- corner FLOATING windows resize from, not pointer corner-dragging
    -- (corners work through the grab-area geometry above).
    resize_on_border = true,
    hover_icon_on_border = true,
    extend_border_grab_area = 15,
  },

  decoration = {
    dim_inactive = true,
    dim_strength = 0.12,
  },
})

-- Dwindle split pin: manual resizes (Super+RightClick drag, Super+Alt+Arrow)
-- survive window switches instead of snapping back to 50/50. Already true in
-- Omarchy's defaults; pinned here so a future default flip can't silently
-- reset the emulator/IDE split. Verified live via
-- `hyprctl getoption dwindle:preserve_split`.
hl.config({
  dwindle = {
    preserve_split = true,
  },
})

-- Lone-window flush guard: a workspace holding exactly one visible tiled
-- window (w[tv1]) — or one floating window (f[1]) — stays flush even if gaps
-- or frames are raised in the base general block above later. With the current
-- zeros these rules are already satisfied; they exist so the guarantee holds
-- under future config changes. Selector semantics: "w[(flags)X]" matches a
-- workspace whose *visible tiled* window count is exactly 1.
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/#smart-gaps
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
hl.window_rule({
  name        = "no-frame-wtv1",
  match       = { float = false, workspace = "w[tv1]" },

  border_size = 0,
  rounding    = 0,
})
hl.window_rule({
  name        = "no-frame-f1",
  match       = { float = false, workspace = "f[1]" },

  border_size = 0,
  rounding    = 0,
})

-- External HDMI-A-1 sits at 60Hz (native panel ceiling) while eDP-1 runs
-- 144Hz, so fullscreen content on the secondary can otherwise add an extra
-- compositor frame hop to its present timeline. `direct_scanout` lets a
-- fullscreen window on ANY output flip straight to the display (bypassing the
-- composited swapchain) — shaves that hop for games / fullscreen video on the
-- external, and is inert while windows are tiled.
hl.config({
  render = {
    direct_scanout = 1,
  },
})
