-- Extra autostart processes.
o.launch_on_start("mogtab run")
-- Thumbnail cache for omarchy-switch: captures active windows in the
-- background so Alt-Tab cards show real previews for inactive /
-- other-workspace windows (single-instance, self-detaches).
o.launch_on_start("omarchy-switch daemon")
-- Fullscreen trap healer: re-elevates client fullscreen dropped to tiling
-- (maximized + video 'f'), restores maximize on video exit. Single instance.
o.launch_on_start("omarchy-fullscreen-watch")
-- Emulator column snap: keeps the tiled phone at a slim 430px so bundled Qt
-- has no white canvas strip. Single instance socket2 daemon.
o.launch_on_start("omarchy-emulator-snap")
