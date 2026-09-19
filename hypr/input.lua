-- =============================================================================
-- Touchpad + gestures: the "reversed" direction scheme.
-- =============================================================================
-- What this file does (and nothing else):
--   1. Flips 2-finger scroll direction (swipe up -> content moves down).
--   2. Flips workspace-swipe direction (swipe left -> go to workspace on right).
--   3. Registers 3-finger swipe (workspaces) and 4-finger swipe (app switcher).
--
-- Everything NOT mentioned here keeps Omarchy's defaults (tap-to-click,
-- clickfinger behavior, palm rejection, scroll speed, keyboard layout, ...).
-- Omarchy's defaults live in /usr/share/omarchy/default/hypr/input.lua
-- (read-only reference -- never edit that file).
--
-- How to change things manually:
--   * Edit a value below, save, then run:
--       hyprctl reload && hyprctl configerrors
--     An empty configerrors output means your change is valid.
--   * To go back to Omarchy's default for any single setting, either delete
--     its line or set it to the default noted next to it.
--   * Full variable reference:
--       https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- DO NOT invent new option tables here (no hl.input / hl.gestures / hl.state
-- style APIs -- those do not exist). The only two calls used in this file are
-- hl.config({...}) for variables and hl.gesture({...}) for finger swipes.
-- =============================================================================

hl.config({
  input = {
    touchpad = {
      -- 2-finger scroll direction.
      --   true  = "natural"/reversed (this file's scheme; swipe up scrolls down)
      --   false = Omarchy default (swipe up scrolls up)
      natural_scroll = true,

      -- EXAMPLES (commented out = Omarchy defaults stay in effect):
      -- tap_to_click = true,       -- tap the pad to click (default: false)
      -- tap_and_drag = true,       -- tap-hold-drag to drag (default: false)
      -- disable_while_typing = true, -- palm rejection while typing (default: true)
      -- scroll_factor = 1.0,       -- 2-finger scroll speed multiplier (default: 1.0;
                                     -- Omarchy default is 0.4, so 1.0 = much faster)
      -- clickfinger_behavior = true, -- 2 fingers = right-click (Omarchy default: true)
    },
  },
  gestures = {
    -- Workspace-swipe direction.
    --   true  = swipe LEFT moves to the workspace on the RIGHT (this scheme)
    --   false = Hyprland/Omarchy default (swipe left moves left)
    workspace_swipe_invert = true,
  },
})

-- =============================================================================
-- Finger gestures.
-- =============================================================================
-- hl.gesture takes: fingers (number), direction ("horizontal", "left",
-- "right", "up", "down") and action (a Hyprland action name like "workspace",
-- or a Lua function -- usually hl.exec_cmd("some-command")).
--
-- To add your own: copy one of the 4-finger blocks below, change fingers /
-- direction / command, reload, and check configerrors.
-- To disable one: delete or comment out its block.

-- 3-finger horizontal swipe: move between workspaces.
-- (Direction is flipped by workspace_swipe_invert above: swipe left -> next.)
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- 4-finger swipe left/right: open the omarchy-switch app picker and move the
-- selection (left/backward-safe: "next", right: "prev"). The picker stays open
-- until you press Enter/click (confirm) or Esc (cancel); swiping again moves
-- the selection further. Releasing behaviour is handled by the picker itself.
hl.gesture({
  fingers = 4,
  direction = "left",
  action = function()
    hl.exec_cmd("omarchy-switch open next")
  end,
})
hl.gesture({
  fingers = 4,
  direction = "right",
  action = function()
    hl.exec_cmd("omarchy-switch open prev")
  end,
})
