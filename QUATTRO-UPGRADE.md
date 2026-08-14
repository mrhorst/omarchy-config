# Omarchy Quattro migration record

This repository has been migrated from the Omarchy 3.8.5 configuration model to Quattro 4.0. The old runbook is preserved in Git history; this file documents the active result.

## What changed upstream

Quattro replaced the legacy Waybar, Walker, Mako, SwayOSD, Hyprlock, Hypridle, and Hyprland `.conf` UI stack with Omarchy Shell and Lua-based Hyprland configuration. The package-owned implementation now lives under `/usr/share/omarchy`; personal overrides belong under `~/.config`.

Timestamped `.omarchy-upgrade-to-quattro.*.bak` directories are migration evidence only. Do not copy them back over the active setup.

## Active replacements

| Legacy behavior | Quattro replacement |
|---|---|
| `hyprland.conf` include chain | `hypr/hyprland.lua` plus required personal modules |
| `monitors.conf` | `hypr/monitors.lua` with fixed connectors, coordinates, scale, and refresh |
| `bindings.conf` | `hypr/bindings.lua` with only personal overrides and required unbinds |
| App/workspace/window rules | `hypr/windows.lua` |
| `hypridle.conf` | `omarchy/shell.json` idle settings |
| Waybar Tailscale and AI usage | Native `omarchy.tailscale` and `omarchy.agents` widgets |
| Waybar microphone module | Native `omarchy.microphone` widget |
| Waybar MPRIS module | Native `omarchy.media` widget |
| Waybar system-health script | User-owned `mat.system-health` QML plugin |
| Mako notification daemon | Native `omarchy.notifications` service |

`hyprsunset.conf` and `xdph.conf` remain supported standalone files and are still tracked.

## Notification ownership

The migration left the `mako` package installed on this machine, allowing D-Bus activation to steal `org.freedesktop.Notifications` from Omarchy Shell. The user service is now stopped and masked, and the native Quickshell process owns the notification bus.

The install and restore helpers repeat that safe user-level mask when a leftover Mako service exists. Removing the obsolete package later with the system package manager is optional cleanup; it is not required for correct notification behavior.

## Intentional differences

- Quattro's lock screen hard-codes a 3-pixel field outline; the old 2-pixel Hyprlock customization has no supported user override. Forking the entire lock plugin for one pixel would be an update liability, so it was not done.
- The native Agents widget replaces the old selector for Claude, Codex, and Fireworks. The retired Waybar script's Grok/reset-credit details are not restored because Quattro has no native collector for them.
- Walker's unified prefix search is retired. Quattro supplies native app, clipboard, emoji, calculator, and menu surfaces rather than recreating Walker.
- Application-specific Mako sizing/color criteria are retired. Window geometry is handled in Hyprland Lua; notification actions must be supplied by the sender or a supported shell plugin.

## Validation

```sh
hyprctl reload
hyprctl configerrors
hyprctl -j monitors
hyprctl binds -j
omarchy-shell shell listPlugins
busctl --user status org.freedesktop.Notifications
systemctl --user --failed
```

The expected display layout is DP-3 left and DVI-D-1 right, both at 144 Hz and scale 1. Health Log and DevLab bindings should each appear exactly once, and `omarchy.media`, `omarchy.microphone`, and `mat.system-health` should report enabled.
