-- Reversed touchpad gestures.
--
-- Loaded after Omarchy's defaults via require("hypr.input") in hyprland.lua,
-- so only direction-affecting settings are overridden here. "Reversed" means
-- flipped direction: swipe up -> scroll down, swipe left -> next/forward.
--
-- Non-directional touchpad preferences are intentionally untouched:
-- tap-to-click, clickfinger/middle-click behavior, palm rejection, scroll
-- factor, disable-while-typing and pinch zoom all keep their defaults.

hl.config({
  input = {
    touchpad = {
      -- Flip 2-finger scrolling on both axes (Omarchy default: natural_scroll = false).
      natural_scroll = true,
    },
  },
  gestures = {
    -- Flip the workspace swipe direction so dragging LEFT opens the workspace
    -- to the RIGHT (Hyprland default: invert = true).
    workspace_swipe_invert = true,
  },
})

-- 3-finger horizontal swipe switches workspaces (flipped by "reversed" meaning:
-- swipe left -> next/right workspace).
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- 4-finger horizontal swipe opens the omarchy-switch picker (app icons +
-- workspace snapshot); it stays up until Enter/Esc/click, and swiping again
-- moves the selection in the same direction.
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