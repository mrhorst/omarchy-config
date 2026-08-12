# Omarchy Quattro upgrade runbook for Nostalrius

Do not run the current Quattro beta migration on this primary machine. As of
2026-08-12, upstream labels Quattro a draft beta, describes the transition as
one-way, and recommends it only for test or secondary machines.

Re-read the current official release announcement and migration script on the
day of the upgrade. Do not reuse a previously downloaded beta script.

## Before upgrading

1. Confirm that Quattro has reached the release channel you intend to use.
2. Confirm the public configuration backup is clean and pushed:

   ```bash
   git -C ~/.config status --short --branch
   git -C ~/.config fetch origin main
   git -C ~/.config rev-parse HEAD origin/main
   ```

   The two commit IDs should match and the status should contain no modified or
   untracked allowlisted files.

3. Run and verify the protected off-disk backup:

   ```bash
   sudo systemctl start nostalrius-backup.service
   sudo journalctl -u nostalrius-backup.service -n 100 --no-pager
   sudo systemctl --failed
   findmnt -no OPTIONS /mnt/backup
   ```

   The backup service must succeed. Afterward, `/mnt/backup` must report `ro`.

4. Create named local pre-risk snapshots:

   ```bash
   sudo pre-risk-snapshot "before Omarchy Quattro"
   sudo snapper -c root list
   sudo snapper -c home list
   ```

5. Save open work and stop any disposable development jobs. Leave Home Assistant
   and other intentionally persistent services alone unless the current official
   upgrade notes require otherwise.

6. Download the current official migration to a file and inspect it. Do not pipe
   an upgrade script directly into a shell. Do not request automatic reboot.

## During the upgrade

- Run only the command documented by the current stable Omarchy release.
- Do not pass `--reboot`; inspect the complete result first.
- If the migration says the system is partially upgraded, do not reboot. Fix the
  reported error and rerun the official migration, which is designed to resume.
- Do not reboot if it cannot confirm the root/LUKS kernel command line or rebuild
  the boot image.
- Keep the pre-upgrade snapshot IDs and Restic backup timestamp nearby.

## What upstream changes

Quattro replaces the legacy Waybar, Walker, Mako, SwayOSD, Hyprlock, Hypridle,
and Hyprland `.conf` UI stack with Omarchy Shell and Lua-based Hyprland config.
The migration archives the old UI directories using timestamped
`.omarchy-upgrade-to-quattro.<timestamp>.bak` names and leaves old Hyprland
`.conf` files for reference. Those legacy files are not the active Quattro
configuration.

The legacy Omarchy Git checkout is moved to a timestamped backup and replaced by
the package-owned `/usr/share/omarchy` layout. Never copy custom files into that
package-owned tree.

## Machine-specific post-upgrade work

### 1. Restore the organized home-directory map

The migration currently points Desktop, Templates, and Public back to `$HOME`
and creates `~/Projects`. Restore the tracked canonical file:

```bash
git -C ~/.config restore user-dirs.dirs
mkdir -p ~/Desktop ~/Templates ~/Public
xdg-user-dirs-update
```

Verify that `XDG_PROJECTS_DIR` is `$HOME/workspace/projects`. Remove an empty
`~/Projects` only after confirming that no files were placed in it.

### 2. Port monitor layout to `~/.config/hypr/monitors.lua`

Preserve this topology using the current Quattro Lua API:

```lua
hl.env("GDK_SCALE", "1")
hl.monitor({ output = "DP-3", mode = "1920x1080@144", position = "0x0", scale = 1 })
hl.monitor({ output = "DVI-D-1", mode = "1920x1080@144", position = "1920x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", disabled = true })
```

Check `hyprctl monitors all` first because connector names can change after a
kernel or driver update. Validate the exact `disabled` field against the shipped
Quattro example before saving.

### 3. Port personal bindings to `~/.config/hypr/bindings.lua`

Compare the archived `bindings.conf` with Quattro defaults before adding
anything. Do not duplicate new defaults. The genuinely machine-specific bindings
that need attention are:

- `SUPER + SHIFT + A`: launch the real ChatGPT application with
  `uwsm-app -- chatgpt`, not the retired web app.
- `SUPER + H`: `$HOME/.local/bin/hermes-voice-log toggle`.
- `CTRL + ESCAPE`: `$HOME/.local/bin/hermes-voice-log cancel`.
- `XF86Tools`: `omarchy capture screenshot` for the WASD CODE key.
- the custom tmux terminal binding and any web-app bindings not supplied by
  Quattro.

If a Quattro default already owns a key, call `hl.unbind(...)` before `o.bind(...)`.
Use `omarchy menu keybindings --print` to confirm conflicts.

### 4. Port Health Log and scanned-docs integration

The old `hyprland.conf` sources for these integrations will not become active Lua
automatically:

- `~/.config/health-log/desktop/hyprland.conf`
- `~/.config/scanned-docs/desktop/hyprland.conf`

Translate only their actual window rules into the current Lua/Hyprland syntax.
Fetch the current official Hyprland window-rule documentation at that time; the
syntax changes frequently. Validate with:

```bash
hyprctl reload
hyprctl configerrors
```

Mako-specific include files and styling will no longer apply. Test that both apps'
`notify-send` notifications reach Omarchy Shell, then reproduce only missing
behavior using supported shell configuration or plugins.

### 5. Reconcile the old Waybar features

Do not restore the archived Waybar directory over Quattro. First try Quattro's
built-in model-usage/Codex and Tailscale widgets. Review the archived scripts for
anything still missing:

- `ai-subscriptions.py`
- `tailscale-status.py`
- `microphone-status.py`
- `system-health.py`
- `codex-status.py`

Port only missing functionality through the supported Omarchy Shell plugin
system. Keep the archived scripts as reference until the replacement is verified.

### 6. Restore behavior and appearance

- Set the active theme back to Ethereal if migration does not preserve it:
  `omarchy theme set Ethereal`.
- Configure a five-minute lock timeout through the new shell/power settings;
  `hypridle.conf` is retired.
- Verify the ChatGPT PWA stays absent and `SUPER + SHIFT + A` opens the packaged
  ChatGPT app.
- Verify user services for Hermes, Health Log, scanned-docs, rclone, EasyEffects,
  and Home Assistant-related workflows.
- Verify the custom application launchers in `~/.local/share/applications`.

### 7. Final validation

```bash
omarchy version
omarchy debug --no-sudo --print
hyprctl configerrors
systemctl --failed
systemctl --user --failed
git -C ~/.config status --short
```

Test both displays, lock/unlock, audio, screenshots, notifications, ChatGPT,
Hermes voice, Health Log, scanned-docs, Tailscale, and one restore of a harmless
file from the latest Restic snapshot before deleting any migration `.bak` files.
