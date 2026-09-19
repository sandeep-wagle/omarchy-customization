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

-- Android Emulator / QEMU: tile the phone screen naturally in the grid
-- side-by-side with the editor (no floating overlay covering code).
-- Only a small helper/toolbar dialog (if it appears as a separate window)
-- is allowed to float beside the tiled phone.
-- Force Android emulator to tile naturally in the grid
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$" }, {
  tile = true,
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  rounding = 20,
})

-- Small emulator helper toolbar / extended-controls dialog: keep floating,
-- compact, and out of the tiling grid so it can dock flush beside the phone.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$", title = "(Extended controls|Emulator Settings|Snapshots|Toolbar)" }, {
  float = true,
  size = { 380, 600 },
  center = true,
})

-- NOTE: Hyprland `size` only affects floating windows, so a static rule
-- cannot force the tiled 430px column. omarchy-emulator-snap (socket2
-- daemon, see bin/) snaps the phone to exactly 430px on openwindow.