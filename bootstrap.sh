#!/usr/bin/env bash
set -Eeuo pipefail

# Re-runnable workstation bootstrap for a fresh Omarchy installation.
# Public by design: this file never contains credentials or private account IDs.

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="${HOME}/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-bootstrap"
MODE="all"
DRY_RUN=0
NON_INTERACTIVE="${OMARCHY_BOOTSTRAP_NON_INTERACTIVE:-0}"
STRICT=0
SKIP_SYSTEM="${OMARCHY_BOOTSTRAP_SKIP_SYSTEM:-0}"
SKIP_HERMES="${OMARCHY_BOOTSTRAP_SKIP_HERMES:-0}"
SKIP_WEBAPPS="${OMARCHY_BOOTSTRAP_SKIP_WEBAPPS:-0}"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [all|install|auth|verify] [options]

Modes:
  all       Install software, guide account sign-ins, then verify (default)
  install   Install/update software and web-app launchers only
  auth      Guide only the sign-ins that are still missing
  verify    Check software and authenticated integrations without showing data

Options:
  --dry-run          Print intended changes without executing them
  --non-interactive  Never prompt; skip interactive sign-ins
  --strict           Make verify exit non-zero when anything is pending
  -h, --help         Show this help

Environment controls used by tests/advanced runs:
  OMARCHY_BOOTSTRAP_SKIP_SYSTEM=1   Skip pacman/yay/systemd operations
  OMARCHY_BOOTSTRAP_SKIP_HERMES=1   Skip Hermes Agent installation/setup
  OMARCHY_BOOTSTRAP_SKIP_WEBAPPS=1  Skip web-app launcher creation
  OMARCHY_BOOTSTRAP_NON_INTERACTIVE=1  Never prompt during installer chaining
  OMARCHY_CONFIG_REPO_URL=...       Override the public config repository
EOF
}

while (($#)); do
  case "$1" in
  all | install | auth | verify) MODE="$1" ;;
  --dry-run) DRY_RUN=1 ;;
  --non-interactive) NON_INTERACTIVE=1 ;;
  --strict) STRICT=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'Unknown argument: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if ((DRY_RUN == 0)); then
  mkdir -p "$STATE_DIR" "$LOCAL_BIN"
fi
umask 077

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[1;32mOK\033[0m  %s\n' "$*"; }
pending() { printf '  \033[1;33mTODO\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33mWARN\033[0m %s\n' "$*" >&2; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*" >&2; }

run() {
  if ((DRY_RUN)); then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  local prompt=$1 default=${2:-yes} answer
  if ((NON_INTERACTIVE)); then
    [[ $default == yes ]]
    return
  fi
  if ! { true </dev/tty; } 2>/dev/null; then
    return 1
  fi
  if [[ $default == yes ]]; then
    read -r -p "$prompt [Y/n] " answer </dev/tty
    [[ -z $answer || $answer =~ ^[Yy] ]]
  else
    read -r -p "$prompt [y/N] " answer </dev/tty
    [[ $answer =~ ^[Yy] ]]
  fi
}

require_omarchy() {
  if ((EUID == 0)); then
    fail "Run this bootstrap as your normal user; it invokes sudo only for system packages."
    exit 1
  fi
  if [[ ! -d $HOME/.local/share/omarchy ]]; then
    fail "Omarchy was not detected. Install Omarchy first, then rerun this script."
    exit 1
  fi
  if [[ $(uname -s) != Linux ]]; then
    fail "This bootstrap targets Omarchy on Linux."
    exit 1
  fi
}

install_system_packages() {
  if [[ $SKIP_SYSTEM == 1 ]]; then
    warn "Skipping system package installation by request."
    return
  fi

  if ((NON_INTERACTIVE && DRY_RUN == 0)) && ! sudo -n true 2>/dev/null; then
    fail "Non-interactive system setup needs pre-authorized sudo. Run 'sudo -v' first or set OMARCHY_BOOTSTRAP_SKIP_SYSTEM=1."
    return 1
  fi

  info "Installing base packages"
  local packages=(git curl jq github-cli go libsecret tailscale chromium)
  have op || packages+=(1password-cli)
  have 1password || packages+=(1password)

  if ((NON_INTERACTIVE)); then
    run sudo -n pacman -S --needed --noconfirm "${packages[@]}"
  elif have omarchy-pkg-add; then
    run omarchy-pkg-add "${packages[@]}"
  else
    run sudo pacman -S --needed --noconfirm "${packages[@]}"
  fi

  if ! have yay; then
    fail "yay is missing; a normal Omarchy install should provide it."
    exit 1
  fi
  if ! have codexbar; then
    if ((NON_INTERACTIVE)); then
      run yay -S --needed --noconfirm --sudoflags=-n --answerclean=None --answerdiff=None --answeredit=None codexbar-cli
    else
      run yay -S --needed --noconfirm codexbar-cli
    fi
  else
    ok "CodexBar CLI already installed"
  fi

  if ((NON_INTERACTIVE)); then
    run sudo -n systemctl enable --now tailscaled.service
  else
    run sudo systemctl enable --now tailscaled.service
  fi
}

install_npx_wrapper() {
  local package=$1 command=$2
  if have "$command"; then
    ok "$command already installed"
    return
  fi
  if ! have omarchy-npx-install; then
    fail "omarchy-npx-install is unavailable. Update Omarchy and rerun."
    return 1
  fi
  run omarchy-npx-install "$package" "$command"
}

install_gog() {
  info "Installing gogcli"
  local arch asset api tag current tmp checksum expected release_json
  case $(uname -m) in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    fail "Unsupported gogcli architecture: $(uname -m)"
    return 1
    ;;
  esac

  api=https://api.github.com/repos/openclaw/gogcli/releases/latest
  if ((DRY_RUN)); then
    printf '  + download latest checksum-verified release from %s\n' "$api"
    return
  fi

  if ! release_json=$(curl -fsSL --retry 3 "$api"); then
    if have gog; then
      warn "Could not check gogcli releases; keeping the installed version."
      return
    fi
    fail "Could not query the latest gogcli release."
    return 1
  fi
  tag=$(jq -r .tag_name <<<"$release_json")
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    fail "Could not resolve a valid gogcli release tag."
    return 1
  }
  current=""
  if have gog; then
    current=$(gog --version 2>/dev/null | sed -n 's/^v\([^ ]*\).*/\1/p' | sed -n '1p')
  fi
  if [[ $current == "${tag#v}" ]]; then
    ok "gogcli ${tag#v} already installed"
    return
  fi

  asset="gogcli_${tag#v}_linux_${arch}.tar.gz"
  tmp=$(mktemp -d "$STATE_DIR/gog.XXXXXX")
  if ! curl -fsSL --retry 3 "https://github.com/openclaw/gogcli/releases/download/${tag}/${asset}" -o "$tmp/$asset" ||
    ! curl -fsSL --retry 3 "https://github.com/openclaw/gogcli/releases/download/${tag}/checksums.txt" -o "$tmp/checksums.txt"; then
    rm -rf "$tmp"
    if have gog; then
      warn "Could not download the gogcli update; keeping the installed version."
      return
    fi
    fail "Could not download gogcli."
    return 1
  fi
  expected=""
  while read -r checksum name; do
    if [[ $name == "$asset" ]]; then
      expected=$checksum
      break
    fi
  done <"$tmp/checksums.txt"
  if [[ ! $expected =~ ^[a-fA-F0-9]{64}$ ]]; then
    rm -rf "$tmp"
    fail "No valid checksum found for $asset."
    return 1
  fi
  if ! printf '%s  %s\n' "$expected" "$tmp/$asset" | sha256sum --check --status; then
    rm -rf "$tmp"
    fail "Checksum verification failed for $asset."
    return 1
  fi
  if ! tar -xOzf "$tmp/$asset" gog >"$tmp/gog"; then
    rm -rf "$tmp"
    fail "Could not extract the gogcli binary."
    return 1
  fi
  chmod 0755 "$tmp/gog"
  local extracted_version
  if ! extracted_version=$("$tmp/gog" --version 2>/dev/null) ||
    [[ $extracted_version != "v${tag#v}" && $extracted_version != "v${tag#v} "* ]]; then
    rm -rf "$tmp"
    fail "The extracted gogcli binary did not report the expected version."
    return 1
  fi
  if ! install -m 0755 "$tmp/gog" "$LOCAL_BIN/gog"; then
    rm -rf "$tmp"
    fail "Could not install gogcli into $LOCAL_BIN."
    return 1
  fi
  if ! "$LOCAL_BIN/gog" --version >/dev/null; then
    rm -rf "$tmp"
    fail "The installed gogcli binary did not start successfully."
    return 1
  fi
  rm -rf "$tmp"
  ok "Installed gogcli ${tag#v} with checksum verification"
}

install_hey() {
  info "Installing HEY CLI"
  local latest current
  if ((DRY_RUN)); then
    printf '  + GOBIN=%q go install %q\n' "$LOCAL_BIN" 'github.com/basecamp/hey-cli/cmd/hey@latest'
    return
  fi
  if ! latest=$(go list -m -f '{{.Version}}' github.com/basecamp/hey-cli@latest); then
    if have hey; then
      warn "Could not check HEY CLI releases; keeping the installed version."
      return
    fi
    fail "Could not resolve the latest HEY CLI version."
    return 1
  fi
  current=""
  if have hey; then
    current=$(hey --version 2>/dev/null | sed -n 's/^hey version //p' | sed -n '1p')
  fi
  if [[ $current == "$latest" ]]; then
    ok "HEY CLI already current"
    return
  fi
  if ! GOBIN="$LOCAL_BIN" go install github.com/basecamp/hey-cli/cmd/hey@latest; then
    if have hey; then
      warn "HEY CLI update failed; keeping the installed version."
      return
    fi
    fail "HEY CLI installation failed."
    return 1
  fi
  "$LOCAL_BIN/hey" --version >/dev/null
  ok "Installed HEY CLI"
}

install_hermes() {
  if [[ $SKIP_HERMES == 1 ]]; then
    warn "Skipping Hermes Agent installation by request."
    return
  fi
  info "Installing Hermes Agent"
  if have hermes; then
    ok "Hermes Agent already installed"
    return
  fi
  if ((DRY_RUN)); then
    printf '  + curl -fsSL --retry 3 %q -o %q\n' \
      https://hermes-agent.nousresearch.com/install.sh "$STATE_DIR/hermes-install.XXXXXX"
    printf '  + bash %q --skip-setup\n' "$STATE_DIR/hermes-install.XXXXXX"
    return
  fi
  local installer
  installer=$(mktemp "$STATE_DIR/hermes-install.XXXXXX")
  if ! run curl -fsSL --retry 3 https://hermes-agent.nousresearch.com/install.sh -o "$installer"; then
    rm -f "$installer"
    return 1
  fi
  if ! run bash "$installer" --skip-setup; then
    rm -f "$installer"
    return 1
  fi
  rm -f "$installer"
}

ensure_webapp() {
  local name=$1 url=$2 icon=$3 desktop
  desktop="$HOME/.local/share/applications/$name.desktop"
  if [[ -f $desktop ]]; then
    ok "$name web app already present"
  else
    run omarchy-webapp-install "$name" "$url" "$icon"
  fi
}

install_webapps() {
  if [[ $SKIP_WEBAPPS == 1 ]]; then
    warn "Skipping web-app launchers by request."
    return
  fi
  info "Ensuring account web apps"
  have omarchy-webapp-install || {
    fail "omarchy-webapp-install is unavailable."
    return 1
  }
  local icons=https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png
  ensure_webapp ChatGPT https://chatgpt.com "$icons/chatgpt.png"
  ensure_webapp Grok https://grok.com "$icons/grok.png"
  ensure_webapp HEY https://app.hey.com HEY.png
  ensure_webapp GitHub https://github.com "$icons/github-light.png"
  ensure_webapp "Google Maps" https://maps.google.com "$icons/google-maps.png"
  ensure_webapp "Google Drive" https://drive.google.com "$icons/google-drive.png"
}

configure_codexbar() {
  info "Configuring CodexBar providers"
  if ! have codexbar && ((DRY_RUN == 0)); then
    fail "CodexBar is unavailable after installation."
    return 1
  fi
  run codexbar config enable --provider codex
  run codexbar config enable --provider grok
  if ((DRY_RUN == 0)); then
    chmod 0600 "$CONFIG_DIR/codexbar/config.json" 2>/dev/null || true
    codexbar config validate >/dev/null
  fi
}

install_all() {
  require_omarchy
  install_system_packages
  export PATH="$LOCAL_BIN:$PATH"
  info "Installing AI command-line tools"
  install_npx_wrapper @openai/codex codex
  install_npx_wrapper @xai-official/grok grok
  install_gog
  install_hey
  install_hermes
  install_webapps
  configure_codexbar
  ok "Software installation phase complete"
}

upsert_private_env() {
  local file=$1 key=$2 value=$3
  mkdir -p "$(dirname "$file")"
  printf '%s' "$value" | python3 -c '
from pathlib import Path
import os, sys, tempfile
path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.stdin.read().strip()
if not value or "\n" in value or "\r" in value:
    raise SystemExit("invalid concealed value")
lines = path.read_text(errors="ignore").splitlines() if path.exists() else []
lines = [line for line in lines if not line.startswith(key + "=")]
lines.append(key + "=" + value)
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
try:
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write("\n".join(lines) + "\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
' "$file" "$key"
  chmod 0600 "$file"
}

validate_hermes_op_token() {
  local file="$HOME/.hermes/.env" token owner
  [[ -f $file && ! -L $file ]] || return 1
  owner=$(stat -c %u "$file" 2>/dev/null) || return 1
  [[ $owner == "$EUID" ]] || return 1
  chmod 0600 "$file" || return 1
  token=$(python3 - "$file" <<'PY'
from pathlib import Path
import sys
value = ""
for line in Path(sys.argv[1]).read_text(errors="ignore").splitlines():
    if line.startswith("OP_SERVICE_ACCOUNT_TOKEN="):
        value = line.split("=", 1)[1].strip()
if value and "\n" not in value and "\r" not in value:
    print(value, end="")
PY
  )
  [[ -n $token ]] || return 1
  if OP_SERVICE_ACCOUNT_TOKEN="$token" timeout 15s op whoami --format json >/dev/null 2>&1; then
    unset token
    return 0
  fi
  unset token
  return 1
}

auth_tailscale() {
  info "Tailscale"
  if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
    ok "Tailscale authenticated"
  elif ((NON_INTERACTIVE)); then
    pending "Run: sudo tailscale up --accept-routes"
  elif ask "Authenticate Tailscale now?" yes; then
    run sudo tailscale up --accept-routes
  else
    pending "Tailscale authentication skipped"
  fi
}

auth_onepassword() {
  info "1Password"
  if timeout 15s op whoami --format json >/dev/null 2>&1; then
    ok "1Password CLI authenticated"
  elif ((NON_INTERACTIVE)); then
    pending "Unlock 1Password, enable CLI integration, then run: op signin"
  else
    printf '  Unlock the 1Password desktop app and enable Developer → Connect with 1Password CLI.\n'
    if ask "Run the 1Password sign-in now?" yes; then
      op signin </dev/tty || warn "1Password sign-in is still pending."
    else
      pending "1Password sign-in skipped"
    fi
  fi

  if [[ $SKIP_HERMES != 1 ]] && ! validate_hermes_op_token; then
    if [[ -e $HOME/.hermes/.env ]]; then
      warn "Hermes's unattended 1Password token is missing, invalid, or not stored in a private user-owned regular file."
    fi
    if ((NON_INTERACTIVE)); then
      pending "Hermes still needs its scoped 1Password service-account token for unattended use"
    elif ask "Configure the scoped 1Password service-account token for unattended Hermes?" no; then
      local op_token
      read -r -s -p "Paste the token (hidden; it will not be printed): " op_token </dev/tty
      printf '\n'
      if OP_SERVICE_ACCOUNT_TOKEN="$op_token" timeout 15s op whoami --format json >/dev/null 2>&1; then
        upsert_private_env "$HOME/.hermes/.env" OP_SERVICE_ACCOUNT_TOKEN "$op_token"
        unset op_token
        ok "Stored the validated token in Hermes's private 0600 env file"
      else
        unset op_token
        warn "The token was not stored because validation failed."
      fi
    else
      pending "Hermes unattended 1Password token skipped"
    fi
  fi
}

configure_github_git_helper() {
  local helper gh_path quoted_config quoted_gh host key
  gh_path=$(command -v gh)
  printf -v quoted_config '%q' "$CONFIG_DIR/gh"
  printf -v quoted_gh '%q' "$gh_path"
  helper="!/usr/bin/env GH_CONFIG_DIR=$quoted_config $quoted_gh auth git-credential"
  for host in github.com gist.github.com; do
    key="credential.https://${host}.helper"
    git config --global --unset-all "$key" 2>/dev/null || true
    git config --global --add "$key" ''
    git config --global --add "$key" "$helper"
  done
}

auth_github() {
  info "GitHub"
  if timeout 20s env GH_CONFIG_DIR="$CONFIG_DIR/gh" gh auth status >/dev/null 2>&1; then
    ok "GitHub CLI authenticated"
    configure_github_git_helper
  elif ((NON_INTERACTIVE)); then
    pending "Run: gh auth login --web --git-protocol https"
  elif ask "Authenticate GitHub now?" yes; then
    GH_CONFIG_DIR="$CONFIG_DIR/gh" gh auth login --web --git-protocol https </dev/tty
    configure_github_git_helper
  else
    pending "GitHub authentication skipped"
  fi

  local git_name git_email
  git_name=$(git config --global user.name 2>/dev/null || true)
  git_email=$(git config --global user.email 2>/dev/null || true)
  if [[ -n $git_name && -n $git_email ]]; then
    ok "Global Git author identity configured"
  elif ((NON_INTERACTIVE)); then
    pending "Configure global Git user.name and user.email"
  elif ask "Configure your global Git commit identity now?" yes; then
    read -r -p "Git author name: " git_name </dev/tty
    read -r -p "Git author email: " git_email </dev/tty
    if [[ -n $git_name && $git_email == *@* ]]; then
      git config --global user.name "$git_name"
      git config --global user.email "$git_email"
      ok "Global Git author identity configured"
    else
      warn "Git identity was not changed because the values were incomplete."
    fi
  else
    pending "Global Git author identity skipped"
  fi
}

auth_codex() {
  info "ChatGPT / Codex"
  if codex login status >/dev/null 2>&1; then
    ok "Codex authenticated with ChatGPT"
  elif ((NON_INTERACTIVE)); then
    pending "Run: codex login --device-auth"
  elif ask "Authenticate Codex with your ChatGPT subscription now?" yes; then
    codex login --device-auth </dev/tty
  else
    pending "ChatGPT / Codex authentication skipped"
  fi
}

auth_grok() {
  info "Grok"
  if [[ -s $HOME/.grok/auth.json ]] && timeout 30s grok models >/dev/null 2>&1; then
    ok "Grok CLI authenticated"
  elif ((NON_INTERACTIVE)); then
    pending "Run: grok login --device-auth"
  elif ask "Authenticate Grok with your subscription now?" yes; then
    grok login --device-auth </dev/tty
  else
    pending "Grok authentication skipped"
  fi
}

hey_is_authenticated() {
  timeout 15s hey auth status --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and isinstance(d.get("data"), dict):
    d = d["data"]
ok = isinstance(d, dict) and d.get("authenticated") is True
raise SystemExit(0 if ok else 1)
'
}

auth_hey() {
  info "HEY"
  if hey_is_authenticated; then
    ok "HEY CLI authenticated"
  elif ((NON_INTERACTIVE)); then
    pending "Run: hey setup"
  elif ask "Authenticate HEY now?" yes; then
    hey setup </dev/tty
  else
    pending "HEY authentication skipped"
  fi
}

gog_has_account() {
  gog auth list --no-input --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, list):
    ok = bool(d)
elif isinstance(d, dict):
    candidates = d.get("accounts", d.get("data", []))
    ok = bool(candidates)
else:
    ok = False
raise SystemExit(0 if ok else 1)
'
}

gog_has_credentials() {
  gog auth credentials list --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, list):
    ok = bool(d)
elif isinstance(d, dict):
    ok = bool(d.get("clients", d.get("data", [])))
else:
    ok = False
raise SystemExit(0 if ok else 1)
'
}

auth_google() {
  info "Google via gogcli"
  if gog_has_account && check_gog_readonly; then
    ok "Google OAuth configured and live read probes passed"
    return
  fi
  if ((NON_INTERACTIVE)); then
    pending "Run: gog auth setup, then authorize Gmail read-only and Calendar normally"
    return
  fi
  if ! ask "Configure Google OAuth for gogcli now?" yes; then
    pending "Google OAuth skipped"
    return
  fi

  local account
  read -r -p "Google account email (stored only by gogcli): " account </dev/tty
  [[ $account == *@* ]] || {
    warn "That did not look like an email address; Google setup skipped."
    return
  }

  if ! gog_has_credentials; then
    gog auth setup --services gmail,calendar,drive,docs,sheets,contacts </dev/tty
  fi
  gog auth add "$account" \
    --services gmail,calendar,drive,docs,sheets,contacts \
    --gmail-scope readonly </dev/tty
  ok "Google authorized: Gmail read-only; Calendar and the selected workspace services enabled"
}

auth_hermes() {
  if [[ $SKIP_HERMES == 1 ]]; then
    return
  fi
  info "Hermes Agent"
  if timeout 60s hermes doctor >/dev/null 2>&1; then
    ok "Hermes Agent healthy"
  elif ((NON_INTERACTIVE)); then
    pending "Run: hermes setup"
  elif ask "Run the Hermes setup wizard now?" yes; then
    hermes setup </dev/tty
  else
    pending "Hermes setup skipped"
  fi
}

open_browser_accounts() {
  if ((NON_INTERACTIVE)) || [[ $SKIP_WEBAPPS == 1 ]]; then
    return
  fi
  info "Browser sessions"
  printf '  CLI authentication is separate from your Chromium web sessions.\n'
  if ask "Open ChatGPT, Grok, HEY, and Google so you can confirm their web logins?" yes; then
    for url in https://chatgpt.com https://grok.com https://app.hey.com https://accounts.google.com; do
      setsid -f xdg-open "$url" >/dev/null 2>&1 || true
    done
  fi
}

auth_all() {
  export PATH="$LOCAL_BIN:$PATH"
  auth_tailscale
  auth_onepassword
  auth_github
  auth_codex
  auth_grok
  auth_hey
  auth_google
  auth_hermes
  open_browser_accounts
}

CHECKS_FAILED=0
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$label"
  else
    pending "$label"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

check_gog_readonly() {
  timeout 30s gog --readonly --gmail-no-send --wrap-untrusted --no-input --json gmail labels list >/dev/null 2>&1 &&
    timeout 30s gog --readonly --no-input --json calendar calendars >/dev/null 2>&1
}

check_hey_readonly() {
  timeout 30s hey boxes --json >/dev/null 2>&1 && timeout 30s hey calendars --json >/dev/null 2>&1
}

verify_all() {
  export PATH="$LOCAL_BIN:$PATH"
  info "Software"
  for command in git gh op codex codexbar grok gog hey tailscale chromium; do
    check "$command installed" have "$command"
  done
  if [[ $SKIP_HERMES != 1 ]]; then
    check "hermes installed" have hermes
  fi

  info "Accounts and live read-only probes"
  check "GitHub authenticated" timeout 20s env GH_CONFIG_DIR="$CONFIG_DIR/gh" gh auth status
  check "Global Git author identity configured" bash -c '[[ -n "$(git config --global user.name)" && -n "$(git config --global user.email)" ]]'
  check "1Password authenticated" timeout 15s op whoami --format json
  check "Tailscale connected" bash -c 'tailscale status --json 2>/dev/null | jq -e '\''.BackendState == "Running"'\'''
  check "ChatGPT / Codex authenticated" codex login status
  check "Grok authenticated" bash -c '[[ -s "$HOME/.grok/auth.json" ]] && timeout 30s grok models >/dev/null 2>&1'
  check "CodexBar Codex usage available" timeout 45s codexbar usage --provider codex --source oauth --json
  check "CodexBar Grok usage available" timeout 45s codexbar usage --provider grok --json
  check "Google Gmail + Calendar read probes" check_gog_readonly
  check "HEY mail + calendar read probes" check_hey_readonly
  if [[ $SKIP_HERMES != 1 ]]; then
    check "Hermes unattended 1Password token valid and private" validate_hermes_op_token
    check "Hermes doctor healthy" timeout 60s hermes doctor
  fi

  info "Web apps"
  for name in ChatGPT Grok HEY GitHub "Google Maps" "Google Drive"; do
    if [[ -f $HOME/.local/share/applications/$name.desktop ]]; then
      ok "$name launcher present"
    else
      pending "$name launcher present"
      CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
  done

  if ((CHECKS_FAILED == 0)); then
    ok "Fresh-install bootstrap is fully ready"
    return 0
  fi
  warn "$CHECKS_FAILED checks remain pending. Rerun '$CONFIG_DIR/bootstrap.sh auth' and then 'verify'."
  if ((STRICT)); then
    return 1
  fi
}

if ((DRY_RUN)); then
  case "$MODE" in
  install) install_all ;;
  all)
    install_all
    warn "Dry-run skips authentication and verification because they perform live account probes."
    ;;
  auth | verify)
    warn "Dry-run performs no authentication or live verification."
    ;;
  esac
else
  case "$MODE" in
  install) install_all ;;
  auth) auth_all ;;
  verify) verify_all ;;
  all)
    install_all
    auth_all
    verify_all
    ;;
  esac
fi
