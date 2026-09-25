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

      -- 2-finger scroll speed multiplier. Omarchy default is 0.4, which
      -- feels sluggish (and it stacks multiplicatively with per-window
      -- scroll_touchpad rules, so ghostty's 0.2 default rule made the
      -- terminal crawl at 0.08). 1.0 = full-speed, matches other apps.
      scroll_factor = 1.0,

      -- EXAMPLES (commented out = Omarchy defaults stay in effect):
      -- tap_to_click = true,       -- tap the pad to click (default: false)
      -- tap_and_drag = true,       -- tap-hold-drag to drag (default: false)
      -- disable_while_typing = true, -- palm rejection while typing (default: true)
      -- clickfinger_behavior = true, -- 2 fingers = right-click (Omarchy default: true)
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
-- Pointer speed: mouse + touchpad cursor movement (NOT scroll speed --
-- scroll is scroll_factor in the touchpad block above).
-- =============================================================================
-- How speed works here (three layers, later wins):
--   1. Omarchy default: input.sensitivity = 0.0 for every pointer.
--   2. Global override: hl.config({ input = { sensitivity = X } }) -- affects
--      ALL mice + touchpads at once. Range -1.0 (slow) to 1.0 (fast).
--   3. Per-device override below: wins for that one device only.
--
-- Per-device syntax is hl.device({ name = "<from hyprctl devices>", ... })
-- (Hyprland wiki: Configuring -> Advanced -> Devices). Any input-category
-- option may go inside EXCEPT follow_mouse-style window-management ones.
--
-- Your devices (from `hyprctl devices`):
--   touchpad = "pnp0c50:00-06cb:7e7e-touchpad"
--   mouse    = "pnp0c50:00-06cb:7e7e-mouse"
--   (a "ps/2-synaptics-touchpad" also shows up -- that is a phantom fallback
--   entry, leave it alone; the pnp0c50 touchpad above is the real one.)
--
-- Current values below equal the defaults (0.0), so feel is UNCHANGED --
-- they just make every knob visible. To tune: change a number, save, run
-- `hyprctl reload && hyprctl configerrors`. Typical starting points:
-- touchpad 0.2 to 0.4 (faster glide), mouse 0.0 to 0.3.
--
-- Acceleration (applies globally): accel_profile = "adaptive" (Omarchy
-- default: speeds up fast flicks) or "flat" (1:1, gamers/fine work).
-- Uncomment to change:
--   hl.config({ input = { accel_profile = "flat" } })

-- Touchpad pointer speed (finger glide -> cursor movement).
hl.device({
  name = "pnp0c50:00-06cb:7e7e-touchpad",
  sensitivity = 0.75,
})

-- External/USB mouse pointer speed.
hl.device({
  name = "pnp0c50:00-06cb:7e7e-mouse",
  sensitivity = 0.0,
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
