# Omarchy configuration

Public, portable backup of the hand-maintained Omarchy Quattro overrides used in `~/.config`, plus a re-runnable fresh-workstation bootstrap.

## Safety model

- Everything is ignored unless explicitly allowlisted in `.gitignore`.
- Runtime state, caches, migration backups, screenshots, credentials, OAuth files, and unrelated application configuration are excluded.
- The pre-commit hook rejects unapproved paths, binary files, oversized files, likely credentials, email addresses, fixed IP addresses, and user-specific absolute home paths.
- The bootstrap installs public software and guides interactive authentication. It never embeds or publishes credentials.
- Never use `git add -f` to bypass the allowlist.
- Every push should pass both the pre-commit check and a full-history privacy audit.

## Tracked scope

- Active Hyprland Lua entry points and overrides in `hypr/*.lua`
- Supported standalone Hyprland-adjacent files: `hypr/hyprsunset.conf` and `hypr/xdph.conf`
- Omarchy Shell layout and font overrides in `omarchy/shell.{json,toml}`
- The user-owned `mat.system-health` Omarchy Shell plugin
- PipeWire overrides and the organized XDG user-directory map
- Safety hooks, recovery/install helpers, and the workstation bootstrap

Waybar, Walker, Mako, Hypridle, Hyprlock, and legacy Hyprland `.conf` files are intentionally not tracked because Quattro retired that configuration stack. Their pre-migration versions remain available in Git history and Omarchy's timestamped local migration backups.

## Current machine behavior

- `DP-3`: left, `1920x1080@144`, scale `1`
- `DVI-D-1`: right, `1920x1080@144`, scale `1`
- `HDMI-A-1`: disabled
- `SUPER + CTRL + F12`: Health dashboard
- `SUPER + CTRL + F11`: DevLab
- `SUPER + H` / `CTRL + ESCAPE`: start/cancel Hermes voice capture
- `SUPER + SHIFT + A`: packaged ChatGPT app
- `SUPER + SHIFT + W`: Typora
- The native shell bar includes media, microphone, Tailscale, agent usage, and a user-owned CPU/GPU/system-health widget.

See [`QUATTRO-UPGRADE.md`](QUATTRO-UPGRADE.md) for the migration record and intentional compatibility decisions.

## Daily workflow

Commit and push each logical configuration change immediately:

```sh
git -C ~/.config status --short
git -C ~/.config add -- path/to/approved/file
git -C ~/.config commit -m "config: describe the change"
git -C ~/.config push origin main
```

## Restore after an Omarchy update

Run:

```sh
~/.config/restore-omarchy-config
```

The helper fetches `origin/main`, saves uncommitted tracked changes as a private local patch, preserves unpushed commits on a backup branch, resets tracked configuration to the public canonical version, reloads Hyprland, prevents a leftover Mako service from taking the notification bus, and restarts Omarchy Shell. Ignored application data and migration backups are untouched.

## Fresh Omarchy workstation

Start from a completed Omarchy installation. Run `omarchy update` separately first and finish any migration or reboot it requests; the bootstrap deliberately does not hide system upgrades inside itself.

The one-command path restores this repository, installs the workstation tools, then stops only for account sign-ins that genuinely require a browser or concealed token:

```sh
curl -fsSL https://raw.githubusercontent.com/mrhorst/omarchy-config/main/install.sh | bash -s -- --bootstrap
```

It installs or verifies Git/GitHub CLI, 1Password, Tailscale, Codex, Grok, CodexBar, HEY CLI, Google Workspace CLI support, Hermes Agent, and the configured web-app launchers.

The workflow is resumable:

```sh
~/.config/bootstrap.sh install
~/.config/bootstrap.sh auth
~/.config/bootstrap.sh verify --strict
```

`install` is re-runnable and skips current components. `auth` skips accounts that already verify. `verify` discards fetched account data and reports only pass/pending status.

Important boundaries:

- Browser, OAuth, and device-code approvals remain interactive by design.
- Secret values are accepted only through provider login pages or hidden terminal input and are written only to private provider/Hermes files.
- `--non-interactive` skips account prompts, but system installation first requires a cached non-prompting sudo session (`sudo -v`) or `OMARCHY_BOOTSTRAP_SKIP_SYSTEM=1`.
- The script does not copy `~/.hermes`, sessions, memories, cron jobs, OAuth databases, browser profiles, or the Obsidian vault. Restore those private data sets from their canonical backup/sync path separately.
- Do not start a second Hermes gateway with an existing messaging token until gateway ownership is confirmed.

## Config-only install

```sh
curl -fsSL https://raw.githubusercontent.com/mrhorst/omarchy-config/main/install.sh | bash
```

Restore one accidentally changed file without resetting everything:

```sh
git -C ~/.config restore path/to/file
```
