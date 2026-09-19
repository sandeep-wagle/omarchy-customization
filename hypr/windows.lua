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

-- Android Emulator / QEMU: floating tool-window (Android Studio style).
--
-- Why float instead of tile: when tiled, dwindle hands the phone a 50%+
-- column it can't fill (tall 1080x2424 panel), and bundled Qt paints the
-- leftover as a white canvas -- the window creeps 50% -> 75% -> 95% as Qt's
-- minimum grows during boot, and every extra window (dialogs, controllers)
-- steals another tile. Floating lets each window wrap its own content, so
-- there is no stretched allocation and no white void sitting over your code.
-- Drag either window once with Super+LeftDrag; Hyprland remembers.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$", title = "^Android Emulator" }, {
  float = true,
  size = { 480, 1040 },
  move = { "(monitor_w-window_w)", "(monitor_h-window_h)/2" },
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  rounding = 20,
})

-- Slim controller toolbar (title is exactly "Emulator", ~54px): float it
-- with its native size instead of letting it eat a whole tile column.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$", title = "^Emulator$" }, {
  float = true,
})

-- Small emulator helper toolbar / extended-controls dialog: keep floating,
-- compact, and out of the tiling grid so it can dock flush beside the phone.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$", title = "(Extended controls|Emulator Settings|Snapshots|Toolbar)" }, {
  float = true,
  size = { 380, 600 },
  center = true,
})

-- NOTE: omarchy-emulator-snap (socket2 daemon, see ~/.local/bin/) stays as a
-- backstop: if you ever tile the phone manually (Super+T), it snaps the
-- column back to 460px. It ignores floating windows, so it stays out of the
-- way of the floating tool-window setup above.