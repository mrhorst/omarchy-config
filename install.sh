#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${OMARCHY_CONFIG_REPO_URL:-https://github.com/mrhorst/omarchy-config.git}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-config"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CONFIG_DIR" "$STATE_DIR/backups"
chmod 700 "$STATE_DIR" "$STATE_DIR/backups"

if git -C "$CONFIG_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -x "$CONFIG_DIR/restore-omarchy-config" ]; then
    exec "$CONFIG_DIR/restore-omarchy-config"
  fi
  printf 'An existing Git repository was found at %s, but its restore helper is missing.\n' "$CONFIG_DIR" >&2
  exit 1
fi

if [ -e "$CONFIG_DIR/.git" ]; then
  printf '%s already exists and is not a usable Git repository. Refusing to replace it.\n' "$CONFIG_DIR/.git" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
git clone --no-checkout "$REPO_URL" "$TEMP_DIR/repo"

BACKUP_DIR="$STATE_DIR/backups/pre-install-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"
while IFS= read -r -d '' path; do
  source_path="$CONFIG_DIR/$path"
  if [ -e "$source_path" ] || [ -L "$source_path" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$path")"
    cp -a "$source_path" "$BACKUP_DIR/$path"
  fi
done < <(git -C "$TEMP_DIR/repo" ls-files -z)

mv "$TEMP_DIR/repo/.git" "$CONFIG_DIR/.git"
git -C "$CONFIG_DIR" reset --hard HEAD
git -C "$CONFIG_DIR" config core.hooksPath .githooks

command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
command -v waybar >/dev/null 2>&1 && pkill -SIGUSR2 waybar >/dev/null 2>&1 || true

printf 'Omarchy configuration installed in %s\n' "$CONFIG_DIR"
printf 'Previous versions of replaced files, if any, are in %s\n' "$BACKUP_DIR"
