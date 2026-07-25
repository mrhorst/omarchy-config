# Omarchy configuration

Public, portable backup of the hand-maintained Omarchy overrides used in `~/.config`.

## Safety model

- Everything is ignored unless explicitly allowlisted in `.gitignore`.
- Runtime state, caches, backups, screenshots, downloaded themes, credentials, and unrelated application configuration are excluded.
- The pre-commit hook rejects unapproved paths, binary files, oversized files, likely credentials, email addresses, fixed IP addresses, and user-specific absolute home paths.
- Do not use `git add -f` to bypass the allowlist.
- Every push should pass both the pre-commit check and a full-history privacy audit.

## Tracked scope

- `hypr/*.conf`
- `waybar/config.jsonc`, `waybar/style.css`, and `waybar/scripts/*.{py,sh}`
- `walker/config.toml`
- `omarchy/current/theme.name`
- The safety hook and restore/install helpers

## Daily workflow

Commit and push each logical configuration change immediately:

```sh
git -C ~/.config status --short
git -C ~/.config add -u
git -C ~/.config commit -m "config: describe the change"
git -C ~/.config push
```

## Restore after an Omarchy update

Run:

```sh
~/.config/restore-omarchy-config
```

The helper fetches `origin/main`, saves uncommitted tracked changes as a private local patch, preserves unpushed commits on a backup branch, resets tracked configuration to the public canonical version, and reloads Hyprland and Waybar. Ignored application data is untouched.

## Install on a fresh Omarchy system

```sh
curl -fsSL https://raw.githubusercontent.com/mrhorst/omarchy-config/main/install.sh | bash
```

The installer backs up only files that the repository will replace, installs the repository directly into `~/.config`, enables the safety hook, and reloads Hyprland and Waybar. Unrelated configuration remains untouched.

Restore one accidentally changed file without resetting everything:

```sh
git -C ~/.config restore path/to/file
```
