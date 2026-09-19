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

-- Android Emulator / QEMU: tile EVERYTHING (phone + toolbar + dialogs stay
-- in the grid; extended-controls keeps its centered float below).
--
-- Two lessons that killed the fancier setups:
--   * Floating phone overlays the code underneath (unusable editor where it
--     covers) and floating windows get left behind / stuck across workspace
--     and monitor switches. Tiled windows do neither.
--   * Title-based rules CANNOT split phone vs toolbar: at map time both
--     windows are titled exactly "Emulator" (initialTitle; the phone only
--     becomes "Android Emulator - ..." later, and rules don't re-evaluate),
--     so any title rule matches both and they cascade into float. A single
--     class-wide tile rule has no race: everything tiles, the 54px toolbar
--     takes a slim column, and omarchy-emulator-snap holds the phone column
--     at 460px (content is ~384px, so no white canvas). Pinned/floating is
--     deliberately NOT used here for exactly the stuck-window reason above.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$" }, {
  -- NOTE: no `tile` key exists -- tiling is Hyprland's default, and this
  -- rule stays title-free on purpose (see above). Cosmetics only below.
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

-- NOTE: omarchy-emulator-snap (socket2 daemon, see ~/.local/bin/) stays as a
-- backstop: if you ever tile the phone manually (Super+T), it snaps the
-- column back to 460px. It ignores floating windows, so it stays out of the
-- way of the floating tool-window setup above.