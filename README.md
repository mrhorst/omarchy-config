# Omarchy configuration

Public, portable backup of the hand-maintained Omarchy overrides used in `~/.config`, plus a re-runnable fresh-workstation bootstrap.

## Safety model

- Everything is ignored unless explicitly allowlisted in `.gitignore`.
- Runtime state, caches, backups, screenshots, downloaded themes, credentials, OAuth files, and unrelated application configuration are excluded.
- The pre-commit hook rejects unapproved paths, binary files, oversized files, likely credentials, email addresses, fixed IP addresses, and user-specific absolute home paths.
- The bootstrap installs public software, creates launchers, and guides interactive authentication. It never embeds or publishes credentials.
- Do not use `git add -f` to bypass the allowlist.
- Every push should pass both the pre-commit check and a full-history privacy audit.

## Tracked scope

- `hypr/*.conf`
- `waybar/config.jsonc`, `waybar/style.css`, and `waybar/scripts/*.{py,sh}`
- `walker/config.toml`
- `omarchy/current/theme.name`
- The safety hook, configuration recovery helper, and workstation bootstrap

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

## Fresh Omarchy workstation

Start from a completed Omarchy installation. Run `omarchy update` separately first and finish any migration or reboot it requests; the bootstrap deliberately does not hide system upgrades inside itself.

The one-command path restores this repository, installs the workstation tools, then stops only for account sign-ins that genuinely require a browser or concealed token:

```sh
curl -fsSL https://raw.githubusercontent.com/mrhorst/omarchy-config/main/install.sh | bash -s -- --bootstrap
```

It installs or verifies:

- Git and authenticated GitHub CLI support
- 1Password desktop app and CLI
- Tailscale
- OpenAI Codex CLI and ChatGPT authentication
- xAI Grok CLI and Grok authentication
- CodexBar CLI with Codex and Grok enabled
- HEY CLI
- `gog` for Google Workspace, with Gmail intentionally read-only
- Hermes Agent
- ChatGPT, Grok, HEY, GitHub, Google Maps, and Google Drive web-app launchers

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
- Strict verification treats the scoped unattended 1Password token as required while Hermes setup is enabled; the token is validated live and its private env file is forced to mode `0600`.
- `--non-interactive` skips account prompts, but system installation first requires a cached non-prompting sudo session (`sudo -v`) or `OMARCHY_BOOTSTRAP_SKIP_SYSTEM=1`.
- The script does not copy `~/.hermes`, sessions, memories, cron jobs, OAuth databases, browser profiles, or the Obsidian vault. Restore those private data sets from their canonical backup/sync path separately.
- Do not start a second Hermes gateway with an existing Telegram or Discord token until gateway ownership is confirmed.

## Config-only install

To restore just the public configuration without installing applications:

```sh
curl -fsSL https://raw.githubusercontent.com/mrhorst/omarchy-config/main/install.sh | bash
```

Restore one accidentally changed file without resetting everything:

```sh
git -C ~/.config restore path/to/file
```
