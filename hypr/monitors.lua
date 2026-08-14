-- Fixed dual-monitor layout for McCarthy.
-- Explicit connectors, coordinates, refresh rates, and scale avoid hotplug reordering.
hl.env("GDK_SCALE", "1")

hl.monitor({ output = "DP-3", mode = "1920x1080@144", position = "0x0", scale = 1 })
hl.monitor({ output = "DVI-D-1", mode = "1920x1080@144", position = "1920x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", disabled = true })
