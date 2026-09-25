local omarchy_gdk_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Strictly per-output monitor rules. Every rule names its output — there is
-- no generic `output = ""` catch-all — so editing one display can never
-- overwrite or retarget another.

-- Laptop display (untouched when HDMI-A-1 is edited):
hl.monitor({ output = "eDP-1", mode = "1920x1080@144.42000", position = "1440x0", scale = 1.25 })

-- External display (the only entry that changes when HDMI-A-1 is edited):
-- Native panel timing is 1280x1024@75.02 (5:4, DMT 0x24) per EDID. The old
-- 1920x1080@60 was CEA 1080p being scaled by the monitor itself — going
-- native removes that scaler AND raises the refresh 60 -> 75, so motion on
-- the secondary is smoother and pixel-sharp 1:1 (scale 1).
hl.monitor({ output = "HDMI-A-1", mode = "1280x1024@75.024675", position = "0x0", scale = 1 })