local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Forced 16:9 widescreen display configuration
hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = omarchy_monitor_scale })
