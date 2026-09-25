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

-- Android Emulator / QEMU: PSEUDOTILED normal window (no fixed geometry).
--
-- Pseudotile = tiled + keeps its own requested size; dwindle lays out all
-- OTHER windows in the remaining space. That is exactly "size-following":
-- the phone's own width/height (from XWayland size hints, zoom changes,
-- boot reshapes) determines its tile, siblings adapt, any monitor, no
-- percentages, no resize loop. Verified: Omarchy's own defaults use
-- hl.dsp.window.pseudo() (default/hypr/bindings/tiling.lua), so the pseudo
-- rule key is valid on Hyprland 0.56.2.
--
-- Deliberately NO title conditions here (proven title race: at map time the
-- phone is titled exactly "Emulator" like the toolbar; rules don't
-- re-evaluate, so title rules cascade onto the wrong window). One
-- class-wide rule, zero geometry numbers. The 54px toolbar auto-floats as a
-- Qt dialog and stays out of the tiling tree on its own.
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$" }, {
  pseudo = true,
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  rounding = 20,
})

-- Small emulator helper toolbar / extended-controls dialog: keep floating,
-- compact, and out of the tiling grid so it can dock flush beside the phone.
-- (Title matching is safe HERE: these dialogs open on demand with their final
-- titles, unlike the phone/toolbar at initial map.)
o.window({ class = "^([Ee]mulator|qemu-system-x86_64)$", title = "(Extended controls|Emulator Settings|Snapshots|Toolbar)" }, {
  float = true,
  size = { 380, 600 },
  center = true,
})

-- Ghostty touchpad scroll: Omarchy's default damps it to scroll_touchpad =
-- 0.2 (ghostty multiplies deltas internally for its pixel-precise smooth
-- scrolling, so undamped deltas fly). But that 0.2 stacks multiplicatively
-- with the global touchpad scroll_factor (Omarchy default 0.4), which made
-- 2-finger scrolling in the terminal crawl. Now that the global factor is
-- 1.0 (see hypr/input.lua), 1.0 here restores full-speed smooth touchpad
-- scrolling in ghostty. User file loads after the defaults, so this wins.
o.window("com.mitchellh.ghostty", { scroll_touchpad = 1.0 })

-- Fully opaque windows EVERYWHERE: Omarchy tags every window default-opacity
-- (opacity 0.985 active / 0.96 inactive, browsers 1.0/0.985), so unfocused
-- windows let the desktop background faintly show through. Strip the tag
-- and pin 1:1 on everything (same pattern as davinci-resolve/hermes
-- defaults, just global). User file loads after all defaults, so this wins.
o.window(".*", { tag = "-default-opacity", opacity = "1 1" })