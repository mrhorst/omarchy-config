-- Personal bindings loaded after Omarchy defaults.

-- Keep the pre-Quattro desktop applications instead of new defaults.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "ChatGPT", { launch = "chatgpt" })
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Typora", o.launch("typora --enable-wayland-ime"))

-- Local workflows.
o.bind("SUPER + CTRL + F12", "Health dashboard", "$HOME/workspace/dev/lab/health-log/bin/health-log popup roundup")
o.bind("SUPER + CTRL + F11", "DevLab", "$HOME/workspace/dev/lab/software-engineering/labs/devlab/bin/devlab open")
o.bind("SUPER + H", "New Hermes voice session", "$HOME/.local/bin/hermes-voice-log toggle")
o.bind("CTRL + ESCAPE", "Cancel Hermes voice recording", "$HOME/.local/bin/hermes-voice-log cancel")

-- WASD CODE sends its Print Screen key as XF86Tools/F13.
o.bind("XF86Tools", "Screenshot (WASD CODE)", "omarchy-capture-screenshot")
