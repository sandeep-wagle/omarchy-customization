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

-- KVM guest output. ONLY one rule for Virtual-1: two conflicting rules used
-- to live here (1024x768@1 and 1920x1080@1.25) and the last one won, so the
-- guest silently rendered 2400x1350.
--
-- scale = 1 on purpose. This guest has a QXL paravirtual adapter with no 3D
-- acceleration, so Mesa falls back to llvmpipe and Hyprland rasterizes every
-- frame on the CPU. A fractional scale multiplies the pixel count (1.25^2 =
-- 1.56x) for a cost that llvmpipe cannot absorb, which showed up as laggy
-- typing and a laggy pointer. At scale 1 the compositor moves ~44% fewer
-- pixels. Raise to 1.25 only on a real GPU.
hl.monitor({ output = "Virtual-1", mode = "1920x1080@60.00000", position = "0x0", scale = 1 })