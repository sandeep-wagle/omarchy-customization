-- Phase 3: Dwindle-native BSP tiling.
--
-- Removed the `maximize = true` windowrule. Dwindle handles all layout
-- natively: windows tile into a binary space partition tree. The maximize
-- action is now user-initiated via Super+Up (toggle maximize within layout).
-- Floating windows (dialogs, scratchpad, OSD) are left untouched by dwindle.

-- omarchy-switch picker: always floating, pinned, no frame, no rounded
-- corners, and it animates in (smooth even for a 4-finger swipe).
-- Positioned slightly above center (~35% from the top of the monitor):
-- center first, then shift to (50% x, 35% y) via monitor-relative move.
o.window({ class = "^omarchy\\.switch$" }, {
  float = true,
  border_size = 0,
  rounding = 0,
  pin = true,
  center = true,
  move = { "(monitor_w-window_w)/2", "(monitor_h-window_h)*0.35" },
  animation = "popin 90%",
})

-- Android Emulator / QEMU: the emulator is really two windows (the phone
-- screen plus a separate side toolbar), so it must float FREELY — no
-- workspace assignment, no rigid size (both trap input or clip the toolbar
-- on multi-monitor setups). Plain floating utility, decorations stripped
-- (Xwayland skin ghosting), normal focus passing everywhere.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$" }, {
  float = true,
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  no_initial_focus = true,
})