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
-- inconsistent outer vs inner spacing) with one small, deliberate gap. With
-- no_gaps_when_only set, a single tiled window fills the entire usable
-- workspace with zero gap; gaps only appear between multiple windows.
-- (The optional "single-window aspect-ratio" toggle overrides the flush
-- behavior by design: it keeps one window as a centered 1:1 region instead.)
hl.config({
  general = {
    snap = {
      enabled = true,
    },

    gaps_in = 4,
    gaps_out = 4,
  },

  dwindle = {
    no_gaps_when_only = true,
  },
})
