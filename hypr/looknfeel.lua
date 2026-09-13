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
-- Window gaps: override Omarchy's defaults (gaps_in = 5, gaps_out = 10 —
-- inconsistent outer vs inner spacing) with one small, deliberate gap; gaps
-- only recede when a single window fills its workspace (see smart gaps below).
hl.config({
  general = {
    snap = {
      enabled = true,
    },

    gaps_in = 4,
    gaps_out = 4,
  },
})

-- "Smart gaps" / single-window flush: a workspace holding exactly one
-- visible tiled window (w[tv1]) — or one floating window (f[1]) — drops all
-- gaps, borders and rounding so the single window fills the usable area
-- edge-to-edge; gaps reappear as soon as a second window joins. This is the
-- official Hyprland-Lua replacement for the old mainline `dwindle:
-- no_gaps_when_only` option, which this build does not expose (it is
-- rejected as an unknown config key).
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/#smart-gaps
-- (The optional "single-window aspect-ratio" toggle overrides the flush by
-- design: it keeps one window as a centered 1:1 region instead.)
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
hl.window_rule({
  name        = "no-gaps-wtv1",
  match       = { float = false, workspace = "w[tv1]" },

  border_size = 0,
  rounding    = 0,
})
hl.window_rule({
  name        = "no-gaps-f1",
  match       = { float = false, workspace = "f[1]" },

  border_size = 0,
  rounding    = 0,
})
