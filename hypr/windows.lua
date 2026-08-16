-- Personal app placement and local desktop integration rules.

-- Open primary apps on dedicated workspaces.
o.window("^chromium$", { workspace = "2" })
o.window("^Hermes$", { workspace = "3" })
o.window("^[Bb]uzz-[Dd]esktop$", { workspace = "4" })
o.window("^chrome-x\\.com__-Default$", { workspace = "5" })

-- Stremio does not publish an idle inhibitor itself. Keep the screen awake only
-- while its native Wayland window is fullscreen.
o.window("^com\\.stremio\\.Stremio$", { idle_inhibit = "fullscreen" })

local function popup(title, width, height)
  o.window({ title = title }, {
    float = true,
    size = { width, height },
    -- Use the requested width directly: move can be evaluated before size on map.
    move = { "(monitor_w-" .. tostring(width) .. "-30)", "76" },
    border_size = 0,
  })
end

-- Health Log amount picker, roundup, and dashboard.
popup("^Log water intake$", 420, 320)
popup("^Today's health roundup$", 620, 720)
popup("^Health dashboard$", 1120, 840)

-- Private scan pipeline control-room window.
popup("^Scan archive status$", 560, 470)
