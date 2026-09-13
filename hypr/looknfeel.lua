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
    border_size = 0,
  },

  decoration = {
    dim_inactive = true,
    dim_strength = 0.12,
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
