# Omarchy configuration

This repository tracks the active, hand-maintained Omarchy overrides in `~/.config` without copying them elsewhere.

## Safety model

- Everything is ignored unless explicitly allowlisted in `.gitignore`.
- Runtime state, caches, backups, screenshots, themes, credentials, and the rest of `~/.config` are excluded.
- The pre-commit hook rejects unapproved paths, binary files, oversized files, likely credentials, email addresses, fixed IP addresses, and user-specific absolute home paths.
- Do not use `git add -f` to bypass the allowlist.
- This repository is local-only until a separately audited **private** remote is explicitly created.

## Tracked scope

- `hypr/*.conf`
- `waybar/config.jsonc`, `waybar/style.css`, and `waybar/scripts/*.{py,sh}`
- `walker/config.toml`
- `omarchy/current/theme.name`

## Workflow

Commit each logical configuration change immediately as its own commit. Before an Omarchy update, confirm the tree is clean:

```sh
git -C ~/.config status --short
git -C ~/.config add -u
git -C ~/.config commit -m "config: describe the change"
```

After an update:

```sh
git -C ~/.config status
git -C ~/.config diff
```

Restore an accidentally changed file:

```sh
git -C ~/.config restore path/to/file
```
