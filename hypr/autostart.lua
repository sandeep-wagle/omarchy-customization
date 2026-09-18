-- Extra autostart processes.
o.launch_on_start("mogtab run")
-- Thumbnail cache for omarchy-switch: captures active windows in the
-- background so Alt-Tab cards show real previews for inactive /
-- other-workspace windows (single-instance, self-detaches).
o.launch_on_start("omarchy-switch daemon")
