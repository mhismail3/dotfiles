#!/usr/bin/env zsh

# setup.sh — Bootstrap personal MacBook from scratch
# Run: ~/Workspace/dotfiles/setup.sh [--reset]
#
# Default mode: skip what's already done (safe to re-run)
# --reset mode: force re-apply everything to match dotfiles

set -o pipefail

CANONICAL_DOTFILES="$HOME/Workspace/dotfiles"
SCRIPT_DIR="${0:A:h}"
if [[ -z "${DOTFILES:-}" ]]; then
    if [[ -d "$CANONICAL_DOTFILES/.git" ]]; then
        DOTFILES="$CANONICAL_DOTFILES"
    elif [[ -d "$SCRIPT_DIR/.git" ]]; then
        DOTFILES="$SCRIPT_DIR"
    else
        DOTFILES="$CANONICAL_DOTFILES"
    fi
fi
DOTFILES="${DOTFILES:A}"
DOTFILES_COMPAT_LINK="$HOME/.dotfiles"
GITHUB_REPO="mhismail3/dotfiles"
DOTFILES_BRANCH="main"
DOTFILES_REMOTE="https://github.com/$GITHUB_REPO.git"
RESET=false

# Parse args
for arg in "$@"; do
    case "$arg" in
        --reset) RESET=true ;;
        --help|-h)
            echo "Usage: ./setup.sh [--reset]"
            echo ""
            echo "  Default: skip what's already done (idempotent)"
            echo "  --reset: force re-apply everything to match dotfiles"
            exit 0
            ;;
    esac
done

###############################################################################
# Helpers
###############################################################################

info()    { printf "\n\033[1;34m→ %s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn()    { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
err()     { printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2; }

CONFIG_LINKS=(
    ".zshrc:$HOME/.zshrc"
    ".gitconfig:$HOME/.gitconfig"
    ".gitignore_global:$HOME/.gitignore_global"
    ".tmux.conf:$HOME/.tmux.conf"
    "starship.toml:$HOME/.config/starship.toml"
    "codex.AGENTS.md:$HOME/.codex/AGENTS.md"
)

confirm() {
    local prompt="$1" default="${2:-y}" reply
    if [[ "$default" == "y" ]]; then
        echo -n "$prompt (Y/n) "
    else
        echo -n "$prompt (y/N) "
    fi
    read reply </dev/tty 2>/dev/null || reply="$default"
    [[ -z "$reply" ]] && reply="$default"
    [[ "$reply" =~ ^[Yy]$ ]]
}

symlink() {
    local src="$1" dst="$2" current
    [[ ! -e "$src" ]] && { warn "Source not found: $src"; return 1; }
    mkdir -p "$(dirname "$dst")"

    if [[ "$RESET" == "true" ]]; then
        # Force: remove whatever's there and re-link
        [[ -L "$dst" ]] && rm "$dst"
        [[ -e "$dst" ]] && mv "$dst" "$dst.bak.$(date +%s)"
        ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
        return 0
    fi

    if [[ -L "$dst" ]]; then
        current="$(readlink "$dst")"
        if [[ "$current" == "$src" || "${current:A}" == "${src:A}" ]]; then
            echo "  Already linked: $dst"
            return 0
        fi
    fi

    if [[ -L "$dst" ]]; then
        mv "$dst" "$dst.bak.$(date +%s)"
        ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
        return 0
    fi

    if [[ -e "$dst" ]]; then
        mv "$dst" "$dst.bak.$(date +%s)"
        ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
        return 0
    fi

    ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
}

ensure_dotfiles_compat_link() {
    local current

    if [[ "$DOTFILES" == "$DOTFILES_COMPAT_LINK" ]]; then
        return 0
    fi

    if [[ -L "$DOTFILES_COMPAT_LINK" ]]; then
        current="$(readlink "$DOTFILES_COMPAT_LINK")"
        if [[ "${current:A}" == "$DOTFILES" ]]; then
            success "$DOTFILES_COMPAT_LINK points to $DOTFILES"
            return 0
        fi
        mv "$DOTFILES_COMPAT_LINK" "$DOTFILES_COMPAT_LINK.bak.$(date +%s)"
    elif [[ -e "$DOTFILES_COMPAT_LINK" ]]; then
        warn "$DOTFILES_COMPAT_LINK exists and is not a symlink; leaving it in place"
        return 0
    fi

    ln -s "$DOTFILES" "$DOTFILES_COMPAT_LINK"
    success "Linked $DOTFILES_COMPAT_LINK -> $DOTFILES"
}

ensure_existing_ssh_key() {
    local key="$1"
    chmod 600 "$key" 2>/dev/null || true
    if [[ ! -f "$key.pub" ]]; then
        ssh-keygen -y -f "$key" > "$key.pub" 2>/dev/null || \
            warn "Could not regenerate SSH public key"
    fi
    [[ -f "$key.pub" ]] && chmod 644 "$key.pub" 2>/dev/null || true
    ssh-add -K "$key" 2>/dev/null || \
        ssh-add --apple-use-keychain "$key" 2>/dev/null || \
        ssh-add "$key" 2>/dev/null || true
}

fix_zsh_compinit_permissions() {
    local dirs=(
        "$HOMEBREW_PREFIX/share"
        "$HOMEBREW_PREFIX/share/zsh"
        "$HOMEBREW_PREFIX/share/zsh/site-functions"
        "$HOMEBREW_PREFIX/share/zsh-completions"
    )
    local d
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] && chmod go-w "$d" 2>/dev/null || true
    done
}

repair_private_internet_access() {
    local app="/Applications/Private Internet Access.app"
    if [[ -d "$app" ]]; then
        xattr -d com.apple.quarantine "$app" 2>/dev/null || true
    fi
    brew install --cask private-internet-access --adopt
}

write_ssh_config() {
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if [[ ! -f "$HOME/.ssh/config" ]] || [[ "$RESET" == "true" ]]; then
        cat > "$HOME/.ssh/config" << 'EOF'
Host *
    IgnoreUnknown UseKeychain,AddKeysToAgent
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
        chmod 600 "$HOME/.ssh/config"
    fi
}

toml_python() {
    local py
    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        if command -v "$py" &>/dev/null && "$py" -c 'import tomllib' &>/dev/null; then
            print -r -- "$py"
            return 0
        fi
    done
    return 1
}

merge_codex_config() {
    local baseline="$1" live="$2" py
    py="$(toml_python)" || {
        warn "No Python with tomllib found; leaving existing Codex config in place"
        return 0
    }

    "$py" - "$baseline" "$live" <<'PY'
import json
import pathlib
import re
import shutil
import sys
import time
import tomllib

baseline_path = pathlib.Path(sys.argv[1])
live_path = pathlib.Path(sys.argv[2])

baseline = tomllib.loads(baseline_path.read_text())
live = tomllib.loads(live_path.read_text()) if live_path.exists() else {}


def deep_merge(defaults, current):
    merged = {}
    for key, value in defaults.items():
        if isinstance(value, dict) and isinstance(current.get(key), dict):
            merged[key] = deep_merge(value, current[key])
        else:
            merged[key] = value
    for key, value in current.items():
        if key not in merged:
            merged[key] = value
    return merged


bare_key = re.compile(r"^[A-Za-z0-9_-]+$")


def toml_key(key):
    return key if bare_key.match(key) else json.dumps(key)


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    raise TypeError(f"Unsupported TOML value: {value!r}")


def emit_table(mapping, path=()):
    lines = []
    scalars = [(key, value) for key, value in mapping.items() if not isinstance(value, dict)]
    children = [(key, value) for key, value in mapping.items() if isinstance(value, dict)]

    if path and scalars:
        lines.append("[" + ".".join(toml_key(part) for part in path) + "]")
    for key, value in scalars:
        lines.append(f"{toml_key(key)} = {toml_value(value)}")
    if scalars:
        lines.append("")

    for key, value in children:
        lines.extend(emit_table(value, path + (key,)))

    return lines


merged = deep_merge(baseline, live)

# Older bootstrap revisions wrote app configuration keys under [desktop]. The
# Codex app reads these as top-level configuration keys, so prune stale copies.
desktop = merged.get("desktop")
if isinstance(desktop, dict):
    for key in (
        "followUpQueueMode",
        "conversationDetailMode",
        "ambient-suggestions-enabled",
    ):
        desktop.pop(key, None)
    if not desktop:
        merged.pop("desktop", None)

if live_path.exists():
    backup = live_path.with_name(live_path.name + f".bak.{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(live_path, backup)

live_path.parent.mkdir(parents=True, exist_ok=True)
live_path.write_text("\n".join(emit_table(merged)).rstrip() + "\n")
live_path.chmod(0o600)
PY
}

###############################################################################
# Step 1: Xcode Command Line Tools
###############################################################################

step_xcode() {
    info "Xcode Command Line Tools"
    if xcode-select -p &>/dev/null; then
        success "Already installed"
    else
        xcode-select --install
        echo "Waiting for installation..."
        until xcode-select -p &>/dev/null; do sleep 5; done
        success "Installed"
    fi
}

###############################################################################
# Step 2: Homebrew
###############################################################################

step_homebrew() {
    info "Homebrew"

    if [[ $(uname -m) == "arm64" ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
    else
        HOMEBREW_PREFIX="/usr/local"
    fi

    if [[ ! -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
        success "Installed"
    else
        success "Already installed"
    fi

    eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
    brew update || warn "Update failed (continuing)"
}

###############################################################################
# Step 3: Clone dotfiles
###############################################################################

step_dotfiles() {
    info "Dotfiles"
    mkdir -p "$(dirname "$DOTFILES")"

    if [[ -d "$DOTFILES/.git" ]]; then
        success "Already at $DOTFILES"
        (cd "$DOTFILES" && git fetch origin "$DOTFILES_BRANCH" 2>/dev/null) || true
        if [[ "$(cd "$DOTFILES" && git branch --show-current)" == "$DOTFILES_BRANCH" ]]; then
            (cd "$DOTFILES" && git pull --rebase origin "$DOTFILES_BRANCH" 2>/dev/null) || true
        else
            warn "Dotfiles repo is not on $DOTFILES_BRANCH; leaving branch unchanged"
        fi
    elif [[ -e "$DOTFILES" ]]; then
        err "$DOTFILES exists but is not a git repo"
        return 1
    else
        git clone --branch "$DOTFILES_BRANCH" "$DOTFILES_REMOTE" "$DOTFILES" || \
            { err "Failed to clone"; return 1; }
        success "Cloned"
    fi

    ensure_dotfiles_compat_link
}

###############################################################################
# Step 4: Brew bundle
###############################################################################

step_packages() {
    info "Installing packages from Brewfile"
    sudo -v < /dev/tty 2>/dev/null || sudo -v
    (while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done) >/dev/null 2>&1 &
    local keepalive=$!
    local bundle_status=0 package_status=0

    if [[ "$RESET" == "true" ]]; then
        # Force reinstall/upgrade everything
        brew bundle --file="$DOTFILES/Brewfile" --force || bundle_status=$?
    else
        brew bundle --file="$DOTFILES/Brewfile" --no-upgrade || bundle_status=$?
    fi

    if (( bundle_status != 0 )); then
        warn "brew bundle reported failures; trying known repairs"
        repair_private_internet_access || true
    fi

    if ! brew bundle check --file="$DOTFILES/Brewfile"; then
        package_status=1
    fi

    kill "$keepalive" 2>/dev/null || true
    wait "$keepalive" 2>/dev/null || true

    # Fix zsh compinit permissions
    fix_zsh_compinit_permissions

    if (( package_status != 0 )); then
        err "Brewfile dependencies are still not satisfied"
        return 1
    fi
    success "Packages installed"
}

###############################################################################
# Step 4b: Full Xcode app
###############################################################################

step_xcode_app() {
    info "Xcode app"
    local developer_dir="/Applications/Xcode.app/Contents/Developer"

    if [[ ! -d "$developer_dir" ]]; then
        warn "Xcode.app not installed"
        echo "  App Store installs can require Apple ID approval."
        echo "  Re-run: mas install 497799835"
        return 0
    fi

    sudo xcode-select -s "$developer_dir" || warn "Could not select Xcode developer directory"
    sudo xcodebuild -license accept 2>/dev/null || true
    sudo xcodebuild -runFirstLaunch 2>/dev/null || warn "Xcode first-launch setup did not complete"

    success "Xcode selected"
}

###############################################################################
# Step 5: Symlinks
###############################################################################

step_symlinks() {
    info "Creating symlinks"
    local entry src dst
    for entry in "${CONFIG_LINKS[@]}"; do
        src="${entry%%:*}"
        dst="${entry#*:}"
        symlink "$DOTFILES/$src" "$dst"
    done
    success "Symlinks created"
}

step_codex_config() {
    info "Codex config"
    local src="$DOTFILES/codex.config.toml"
    local dst="$HOME/.codex/config.toml"
    mkdir -p "$HOME/.codex"

    if [[ ! -f "$src" ]]; then
        warn "Baseline Codex config not found: $src"
        return 0
    fi

    if [[ ! -e "$dst" ]]; then
        cp "$src" "$dst"
        chmod 600 "$dst" 2>/dev/null || true
        success "Seeded $dst from baseline"
        return 0
    fi

    if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
        success "Already linked: $dst"
        return 0
    fi

    merge_codex_config "$src" "$dst"
    success "Merged durable Codex defaults into $dst"
    echo "  Preserved app/plugin/project state from the live config."
}

step_codex_skills() {
    info "Codex skills"
    local src_dir="$DOTFILES/skills"
    local dst_dir="$HOME/.codex/skills"
    local backup_dir="$HOME/.codex/backups/skills"
    local skill dst current backup count=0

    if [[ ! -d "$src_dir" ]]; then
        warn "No personal Codex skills found at $src_dir"
        return 0
    fi

    mkdir -p "$dst_dir" "$backup_dir"
    for skill in "$src_dir"/*(N/); do
        dst="$dst_dir/${skill:t}"
        if [[ -L "$dst" ]]; then
            current="$(readlink "$dst")"
            if [[ "$current" == "$skill" || "${current:A}" == "${skill:A}" ]]; then
                echo "  Already linked: $dst"
                (( count++ ))
                continue
            fi
        fi

        if [[ -e "$dst" || -L "$dst" ]]; then
            backup="$backup_dir/${skill:t}.bak.$(date +%s)"
            mv "$dst" "$backup"
            echo "  Backed up existing skill to $backup"
        fi

        if ln -s "$skill" "$dst"; then
            echo "  Linked: $dst -> $skill"
            (( count++ ))
        else
            warn "Could not link Codex skill: $skill"
        fi
    done

    if (( count == 0 )); then
        warn "No personal Codex skills found at $src_dir"
        return 0
    fi

    success "Codex skills linked"
}

###############################################################################
# Step 6: SSH key
###############################################################################

step_ssh() {
    info "SSH key"
    local key="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    write_ssh_config

    if [[ -f "$key" ]] && [[ "$RESET" != "true" ]]; then
        ensure_existing_ssh_key "$key"
        success "Key already exists"
        return 0
    fi

    if [[ -f "$key" ]] && [[ "$RESET" == "true" ]]; then
        ensure_existing_ssh_key "$key"
        success "Key already exists (keeping existing key)"
        return 0
    fi

    if ! confirm "Generate SSH key?" "y"; then
        echo "  Skipped"
        return 0
    fi

    ssh-keygen -t ed25519 -C "mhismail3@gmail.com" -f "$key" </dev/tty
    eval "$(ssh-agent -s)" > /dev/null
    ssh-add -K "$key" 2>/dev/null || ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add "$key"

    chmod 600 "$key"
    chmod 644 "$key.pub"
    pbcopy < "$key.pub"
    echo ""
    echo "  Public key copied to clipboard."
    echo "  GitHub SSH access will be verified after gh auth."
    success "SSH key configured"
}

ensure_github_ssh_key() {
    local key_pub="$HOME/.ssh/id_ed25519.pub"
    [[ ! -f "$key_pub" ]] && return 0

    local ssh_output
    ssh_output="$(ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1)" || true
    if [[ "$ssh_output" == *"successfully authenticated"* ]]; then
        success "GitHub SSH configured"
        return 0
    fi

    warn "GitHub SSH key is not accepted yet"
    if confirm "Upload SSH public key to GitHub with gh?" "y"; then
        gh auth refresh -h github.com -s admin:public_key </dev/tty || \
            warn "Could not refresh gh token scope"
        gh ssh-key add "$key_pub" \
            --title "$(hostname) $(date +%F)" \
            --type authentication || warn "Could not upload SSH key"
    fi
}

###############################################################################
# Step 7: GitHub CLI auth
###############################################################################

step_gh_auth() {
    info "GitHub CLI authentication"
    if gh auth status &>/dev/null && [[ "$RESET" != "true" ]]; then
        success "Already authenticated"
    else
        echo "  This sets GitHub CLI up for SSH git operations."
        gh auth login --git-protocol ssh </dev/tty
        success "Authenticated"
    fi
    gh config set git_protocol ssh -h github.com >/dev/null 2>&1 || true

    # Git LFS (always safe to re-run)
    if command -v git-lfs &>/dev/null; then
        git lfs install --system 2>/dev/null || git lfs install
        success "Git LFS configured"
    fi

    ensure_github_ssh_key
}

###############################################################################
# Step 8: Shell setup
###############################################################################

step_shell() {
    info "Shell"
    if [[ "$SHELL" != *"zsh"* ]]; then
        chsh -s "$(which zsh)" || warn "Failed to change shell"
        success "Zsh set as default"
    else
        success "Zsh already default"
    fi

    mkdir -p "$HOME/Workspace" "$HOME/.local/bin"
    success "Created $HOME/Workspace and $HOME/.local/bin"
}

###############################################################################
# Step 9: Language runtimes
###############################################################################

step_languages() {
    info "Language runtimes"

    # Rust
    local rustup_cmd=""
    if command -v rustup &>/dev/null; then
        rustup_cmd="$(command -v rustup)"
    elif [[ -n "$HOMEBREW_PREFIX" && -x "$HOMEBREW_PREFIX/opt/rustup/bin/rustup" ]]; then
        rustup_cmd="$HOMEBREW_PREFIX/opt/rustup/bin/rustup"
    fi

    if [[ -n "$rustup_cmd" ]]; then
        if [[ ! -d "$HOME/.rustup" ]]; then
            "$rustup_cmd" default stable || warn "Rust install failed"
            success "Rust installed"
        elif [[ "$RESET" == "true" ]]; then
            "$rustup_cmd" update 2>/dev/null || true
            success "Rust updated"
        else
            success "Rust already installed"
        fi
    else
        warn "rustup not found"
    fi

    # Node (via nvm)
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    if [[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]]; then
        source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
        if ! command -v node &>/dev/null; then
            nvm install --lts --latest-npm 2>/dev/null && \
                nvm alias default "lts/*" >/dev/null 2>&1
            success "Node LTS installed"
        elif [[ "$RESET" == "true" ]]; then
            nvm install --lts --latest-npm --reinstall-packages-from=current 2>/dev/null && \
                nvm alias default "lts/*" >/dev/null 2>&1
            success "Node LTS updated"
        else
            success "Node already installed ($(node -v))"
        fi
    fi

    # Ruby (via rbenv)
    if command -v rbenv &>/dev/null; then
        success "rbenv available"
    fi

    # Python
    if command -v uv &>/dev/null; then
        success "uv available (Python managed via uv)"
    fi

    success "Languages configured"
}

###############################################################################
# Step 10: Ollama
###############################################################################

step_ollama() {
    info "Ollama"
    if command -v ollama &>/dev/null; then
        brew services start ollama 2>/dev/null || true
        success "Ollama installed and set to auto-start"
    else
        warn "Ollama not found"
    fi
}

###############################################################################
# Step 11: App preferences
###############################################################################

apply_synology_drive_preferences() {
    local db_path="$HOME/Library/Application Support/SynologyDrive/data/db/sys.sqlite"

    if [[ ! -f "$db_path" ]]; then
        warn "Synology Drive preferences skipped; sync database does not exist yet"
        echo "  Complete Synology Drive setup, then re-run ./setup.sh."
        return 0
    fi
    if ! command -v sqlite3 &>/dev/null; then
        warn "sqlite3 not found; could not apply Synology Drive preferences"
        return 0
    fi

    sqlite3 "$db_path" <<'SQL'
BEGIN;
UPDATE system_table SET value = '0' WHERE key = 'enable_desktop_notification';
INSERT INTO system_table (key, value)
SELECT 'enable_desktop_notification', '0'
WHERE changes() = 0;

UPDATE system_table SET value = '1' WHERE key = 'use_black_white_icon';
INSERT INTO system_table (key, value)
SELECT 'use_black_white_icon', '1'
WHERE changes() = 0;
COMMIT;
SQL

    success "Synology Drive preferences applied"
    echo "  File event notifications disabled; minimalist menu bar icon enabled."
}

apply_docker_desktop_preferences() {
    local app="/Applications/Docker.app"
    local settings_path="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
    local preferences_domain="com.electron.dockerdesktop"
    local py

    if [[ ! -d "$app" ]]; then
        warn "Docker Desktop preferences skipped; app is not installed"
        return 0
    fi

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done

    if [[ -z "$py" ]]; then
        warn "Python not found; Docker Desktop settings store skipped"
        return 0
    fi

    if ! "$py" - "$settings_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)

if path.exists():
    data = json.loads(path.read_text())
else:
    data = {}

data.update({
    "AutoStart": False,
    "UseContainerdSnapshotter": True,
})

path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
    then
        warn "Could not update Docker Desktop settings store"
        return 1
    fi

    defaults write "$preferences_domain" "NSStatusItem Visible Item-0" -bool false
    killall cfprefsd >/dev/null 2>&1 || true

    success "Docker Desktop preferences applied"
    echo "  Login launch disabled, containerd image store enabled, menu bar status icon hidden."
    echo "  If Docker Desktop is already running, quit and reopen it for the icon change to apply."
}

apply_private_internet_access_preferences() {
    local app="/Applications/Private Internet Access.app"
    local settings_path="$HOME/Library/Preferences/com.privateinternetaccess.vpn/clientsettings.json"
    local py

    if [[ ! -d "$app" ]]; then
        warn "Private Internet Access preferences skipped; app is not installed"
        return 0
    fi

    if command -v piactl &>/dev/null; then
        piactl set protocol openvpn >/dev/null 2>&1 || warn "Could not set PIA protocol"
        piactl set region auto >/dev/null 2>&1 || warn "Could not set PIA region"
        piactl set allowlan true >/dev/null 2>&1 || warn "Could not set PIA LAN access"
        piactl set requestportforward false >/dev/null 2>&1 || warn "Could not set PIA port forwarding"
        piactl set debuglogging false >/dev/null 2>&1 || warn "Could not set PIA debug logging"
    else
        warn "piactl not found; PIA daemon preferences skipped"
    fi

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done

    if [[ -z "$py" ]]; then
        warn "Python not found; PIA client preferences skipped"
        return 0
    fi

    "$py" - "$settings_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)

if path.exists():
    data = json.loads(path.read_text())
else:
    data = {}

data.update({
    "connectOnLaunch": False,
    "dashboardFrame": "popup",
    "desktopNotifications": True,
    "iconSet": "auto",
    "regionSortKey": "latency",
    "themeName": "dark",
})

path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

    success "Private Internet Access preferences applied"
    echo "  Auto region, OpenVPN, LAN allowed, no port forwarding, no connect-on-launch."
}

apply_qbittorrent_preferences() {
    local app="/Applications/qBittorrent.app"
    local config_path="$HOME/.config/qBittorrent/qBittorrent.ini"
    local download_dir="$HOME/Downloads/qBittorrent"
    local incomplete_dir="$download_dir/incomplete"
    local py

    if [[ ! -d "$app" ]]; then
        warn "qBittorrent preferences skipped; app is not installed"
        return 0
    fi

    if pgrep -x qbittorrent >/dev/null 2>&1; then
        warn "qBittorrent preferences skipped; quit qBittorrent and re-run ./setup.sh"
        return 0
    fi

    mkdir -p "$download_dir" "$incomplete_dir" "${config_path:h}"

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done

    if [[ -z "$py" ]]; then
        warn "Python not found; qBittorrent preferences skipped"
        return 0
    fi

    "$py" - "$config_path" "$download_dir" "$incomplete_dir" <<'PY'
import configparser
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
download_dir = pathlib.Path(sys.argv[2])
incomplete_dir = pathlib.Path(sys.argv[3])

config = configparser.RawConfigParser(delimiters=("=",), strict=False)
config.optionxform = str
if config_path.exists():
    config.read(config_path)

def put(section, key, value):
    if not config.has_section(section):
        config.add_section(section)
    config.set(section, key, value)

put("BitTorrent", r"Session\AddExtensionToIncompleteFiles", "true")
put("BitTorrent", r"Session\AddTorrentStopped", "true")
put("BitTorrent", r"Session\AnonymousModeEnabled", "true")
put("BitTorrent", r"Session\DefaultSavePath", str(download_dir))
put("BitTorrent", r"Session\DHTEnabled", "true")
put("BitTorrent", r"Session\LSDEnabled", "false")
put("BitTorrent", r"Session\PeXEnabled", "true")
put("BitTorrent", r"Session\TempPath", str(incomplete_dir))
put("BitTorrent", r"Session\TempPathEnabled", "true")

put("Core", "AutoDeleteAddedTorrentFile", "Never")

put("Network", "PortForwardingEnabled", "false")
put("Network", r"Proxy\HostnameLookupEnabled", "false")
put("Network", r"Proxy\Profiles\BitTorrent", "true")
put("Network", r"Proxy\Profiles\Misc", "true")
put("Network", r"Proxy\Profiles\RSS", "true")
put("Network", r"Proxy\Type", "None")

put("Preferences", r"Advanced\AnonymousMode", "true")
put("Preferences", r"Advanced\trackerPortForwarding", "false")
put("Preferences", r"Connection\UPnP", "false")
put("Preferences", r"Downloads\SavePath", str(download_dir))
put("Preferences", r"Downloads\TempPath", str(incomplete_dir))
put("Preferences", r"Downloads\TempPathEnabled", "true")
put("Preferences", r"General\StatusbarExternalIPDisplayed", "false")
put("Preferences", r"MailNotification\enabled", "false")
put("Preferences", r"MailNotification\req_auth", "true")
put("Preferences", r"WebUI\Enabled", "false")
put("Preferences", r"WebUI\UseUPnP", "false")

with config_path.open("w") as f:
    config.write(f, space_around_delimiters=False)
PY

    success "qBittorrent preferences applied"
    echo "  Downloads go to $download_dir; torrents add stopped; anonymous mode on; UPnP/WebUI off."
}

resolve_tailscale_peer_ip() {
    local peer="$1" status_json py

    command -v tailscale &>/dev/null || return 1
    status_json="$(mktemp)"
    if ! tailscale status --json >"$status_json" 2>/dev/null; then
        rm -f "$status_json"
        return 1
    fi

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done
    if [[ -z "$py" ]]; then
        rm -f "$status_json"
        return 1
    fi

    "$py" - "$peer" "$status_json" <<'PY'
import json
import pathlib
import sys

expected = sys.argv[1].casefold()
data = json.loads(pathlib.Path(sys.argv[2]).read_text())

for peer in (data.get("Peer") or {}).values():
    names = [
        peer.get("HostName") or "",
        peer.get("DNSName") or "",
        peer.get("Name") or "",
    ]
    if any(expected in name.casefold() for name in names):
        ips = peer.get("TailscaleIPs") or []
        if ips:
            print(ips[0])
            raise SystemExit(0)

raise SystemExit(1)
PY
    local status
    status=$?
    rm -f "$status_json"
    return "$status"
}

apply_tailscale_screen_sharing_connection() {
    local peer="${TAILSCALE_SERVER_PEER:-mooses-macbook-server}"
    local fallback_ip="${TAILSCALE_SERVER_IP:-100.82.140.87}"
    local display_name="${TAILSCALE_SERVER_DISPLAY_NAME:-Moose's MacBook Server}"
    local username="${TAILSCALE_SERVER_USERNAME:-moose}"
    local peer_ip url app_support_dir app_location_path share_dir share_link launcher pref_path py

    app_support_dir="$HOME/Library/Containers/com.apple.ScreenSharing/Data/Library/Application Support/Screen Sharing"
    app_location_path="$app_support_dir/$display_name.vncloc"
    share_dir="$HOME/.local/share/dotfiles/remote-control"
    share_link="$share_dir/Mooses MacBook Server.vncloc"
    launcher="$HOME/.local/bin/screen-share-macbook-server"
    pref_path="$HOME/Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences/com.apple.ScreenSharing.plist"

    peer_ip="$(resolve_tailscale_peer_ip "$peer" 2>/dev/null || true)"
    if [[ -z "$peer_ip" ]]; then
        peer_ip="$fallback_ip"
        warn "Could not resolve $peer from Tailscale; using fallback IP $peer_ip"
    fi
    url="vnc://$peer"

    mkdir -p "$app_support_dir" "$share_dir" "$HOME/.local/bin" "$(dirname "$pref_path")"

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done

    if [[ -n "$py" ]]; then
        "$py" - "$pref_path" "$app_location_path" "$url" "$display_name" "$peer" "$peer_ip" "$username" <<'PY'
import datetime as dt
import pathlib
import plistlib
import sys
import uuid

pref_path = pathlib.Path(sys.argv[1])
location_path = pathlib.Path(sys.argv[2])
url = sys.argv[3]
display_name = sys.argv[4]
peer = sys.argv[5]
peer_ip = sys.argv[6]
username = sys.argv[7]

default_pref = {
    "AppleIDOnlyDomains": ["mac.com", "me.com", "icloud.com", "gmail.com", "hotmail.com", "yahoo.com"],
    "DisabledAuthenticationMethods": [],
    "DontQuitWhenLastWindowCloses": False,
    "MigratedTo1011": True,
    "MigratedTo112": True,
    "lastRunMigrationVersion": 1,
}
store = {
    "connectionDetails": {},
    "connectionGroups": {},
    "sessionMetadatas": {},
    "connectionsMigrated": True,
}

if pref_path.exists():
    prefs = plistlib.loads(pref_path.read_bytes())
    if not isinstance(prefs, dict):
        prefs = {}
else:
    prefs = {}

if isinstance(prefs.get("connectionsStore"), bytes):
    try:
        store = plistlib.loads(prefs["connectionsStore"])
    except Exception:
        store = store

details = store.setdefault("connectionDetails", {})
metadata = store.setdefault("sessionMetadatas", {})
store.setdefault("connectionGroups", {})
store["connectionsMigrated"] = True

connection_id = None
for existing_id, detail in details.items():
    params = detail.get("connectionParameters", {})
    network = params.get("networkAddress", {}).get("_0", {})
    if network.get("address") in {peer, peer_ip} or network.get("displayName") == display_name:
        connection_id = existing_id
        break
if connection_id is None:
    connection_id = str(uuid.uuid4()).upper()

display_configuration = {
    "displayType": {
        "virtualDisplays": {
            "numberOfDisplays": 0,
        },
    },
}
details[connection_id] = {
    "id": connection_id,
    "isManaged": False,
    "createdFromMigration": False,
    "connectionParameters": {
        "networkAddress": {
            "_0": {
                "displayName": display_name,
                "displayConfiguration": display_configuration,
                "address": peer,
                "port": 5900,
                "username": username,
            },
        },
    },
}

previous_session = metadata.get(connection_id, {})
session_state = previous_session.get("sessionState", {})
if not session_state:
    session_state = {
        "URL": url,
        "restorationAttributes": {
            "targetAddress": url,
            "quality": 5,
            "displayType": 1,
            "controlMode": 1,
            "scalingMode": 1,
            "dynamicResolution": 0,
            "autoClipboard": 1,
            "isFullScreen": 0,
        },
    }
metadata[connection_id] = {
    **previous_session,
    "lastConnectedDate": previous_session.get("lastConnectedDate", dt.datetime.now()),
    "supportsProMode": previous_session.get("supportsProMode", False),
    "sessionState": session_state,
}

def decode_recent_ids(value):
    if isinstance(value, bytes):
        try:
            value = plistlib.loads(value)
        except Exception:
            return []
    if not isinstance(value, (list, tuple)):
        return []
    return [item for item in value if isinstance(item, str)]

recent_ids = [connection_id]
for existing_id in decode_recent_ids(prefs.get("recentConnectionIDs")):
    if existing_id != connection_id:
        recent_ids.append(existing_id)

prefs = {**default_pref, **prefs}
prefs["recentConnectionIDs"] = plistlib.dumps(recent_ids, fmt=plistlib.FMT_BINARY, sort_keys=True)
prefs["connectionsStore"] = plistlib.dumps(store, fmt=plistlib.FMT_BINARY, sort_keys=True)
pref_path.write_bytes(plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY, sort_keys=True))

location_path.write_bytes(plistlib.dumps({
    "URL": url,
    "restorationAttributes": {
        "targetAddress": url,
        "quality": "adaptive",
        "displayType": 1,
        "controlMode": 1,
        "scalingMode": True,
        "dynamicResolution": False,
        "autoClipboard": True,
        "isFullScreen": False,
    },
}, fmt=plistlib.FMT_XML, sort_keys=True))
PY
    else
        warn "Python not found; Screen Sharing connectionsStore was not updated"
        cat > "$app_location_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>$url</string>
</dict>
</plist>
EOF
    fi

    ln -sf "$app_location_path" "$share_link"
    cat > "$launcher" <<EOF
#!/usr/bin/env zsh
open "$app_location_path"
EOF
    chmod 755 "$launcher"

    success "Screen Sharing connection configured"
    echo "  $display_name appears in Screen Sharing Connections."
    echo "  $app_location_path -> $url"
    echo "  Current Tailscale IP: $peer_ip"
    echo "  CLI launcher: screen-share-macbook-server"
}

apply_tailscale_app_preferences() {
    if [[ ! -d "/Applications/Tailscale.app" ]]; then
        warn "Tailscale app not found; app preferences were not configured"
        return 1
    fi

    defaults write io.tailscale.ipn.macsys TailscaleStartOnLogin -bool true
    defaults write io.tailscale.ipn.macsys HideDockIcon -bool true
    defaults write io.tailscale.ipn.macsys FileSharingConfiguration -string show

    success "Tailscale app preferences configured"
    echo "  Launch at login: on"
    echo "  Hide Dock icon: on"
    echo "  File Sharing UI: shown"
}

apply_tailscale_taildrive() {
    local share_name="${TAILDRIVE_SHARE_NAME:-moose}"
    local share_path="${TAILDRIVE_SHARE_PATH:-$HOME}"
    local body py status_json shares_json bookmark_data swift_bin

    if ! command -v tailscale &>/dev/null; then
        warn "Tailscale CLI not found; Taildrive share was not configured"
        return 1
    fi

    for py in python3.14 python3.13 python3.12 python3.11 python3; do
        command -v "$py" &>/dev/null && break
        py=""
    done
    if [[ -z "$py" ]]; then
        warn "Python not found; Taildrive share was not configured"
        return 1
    fi

    if [[ ! -d "$share_path" ]]; then
        warn "Taildrive share path does not exist: $share_path"
        return 1
    fi

    status_json="$(mktemp)"
    if ! tailscale status --json >"$status_json" 2>/dev/null; then
        rm -f "$status_json"
        warn "Tailscale status is unavailable; Taildrive share was not configured"
        return 1
    fi

    if ! "$py" - "$status_json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
self_node = data.get("Self") or {}
caps = set(self_node.get("Capabilities") or [])
missing = {"drive:share", "drive:access"} - caps
if data.get("BackendState") != "Running" or missing or self_node.get("NoFileSharingReason"):
    raise SystemExit(1)
PY
    then
        rm -f "$status_json"
        warn "Taildrive is not enabled by the tailnet policy for this Mac"
        return 1
    fi
    rm -f "$status_json"

    # Show the File Sharing pane in the macOS GUI app.
    defaults write io.tailscale.ipn.macsys FileSharingConfiguration -string show 2>/dev/null || true

    shares_json="$(tailscale debug localapi GET /localapi/v0/drive/shares 2>/dev/null || echo "[]")"
    bookmark_data="$("$py" - "$share_name" "$share_path" "$shares_json" <<'PY'
import json
import pathlib
import sys

expected_name = sys.argv[1]
expected_path = str(pathlib.Path(sys.argv[2]))
try:
    shares = json.loads(sys.argv[3] or "[]") or []
except json.JSONDecodeError:
    shares = []

for share in shares:
    if share.get("name") == expected_name and str(pathlib.Path(share.get("path", ""))) == expected_path:
        print(share.get("bookmarkData", ""))
        raise SystemExit(0)
PY
)"

    if [[ -z "$bookmark_data" ]]; then
        swift_bin="$(command -v swift || true)"
        if [[ -n "$swift_bin" ]]; then
            bookmark_data="$("$swift_bin" - "$share_path" <<'SWIFT' 2>/dev/null || true
import Foundation

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
print(data.base64EncodedString())
SWIFT
)"
        fi
    fi

    if [[ -z "$bookmark_data" ]]; then
        warn "Could not generate Taildrive security-scoped bookmark; add the folder once through Tailscale Settings > File Sharing"
        return 1
    fi

    body="$("$py" - "$share_name" "$share_path" "$bookmark_data" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1], "path": sys.argv[2], "bookmarkData": sys.argv[3]}))
PY
)"

    if ! tailscale debug localapi PUT /localapi/v0/drive/shares "$body" >/dev/null 2>&1; then
        warn "Could not configure Taildrive share through Tailscale LocalAPI"
        return 1
    fi

    success "Taildrive share configured"
    echo "  $share_name -> $share_path"
}

step_app_preferences() {
    info "App preferences"
    apply_synology_drive_preferences
    apply_docker_desktop_preferences
    apply_private_internet_access_preferences
    apply_qbittorrent_preferences
    apply_tailscale_app_preferences
    apply_tailscale_screen_sharing_connection
    apply_tailscale_taildrive
}

###############################################################################
# Step 12: macOS preferences
###############################################################################

step_macos() {
    info "macOS preferences"
    if [[ ! -f "$DOTFILES/.macos" ]]; then
        warn ".macos not found"
        return 1
    fi

    if [[ "$RESET" == "true" ]]; then
        echo "  Reset mode: re-applying all macOS preferences."
        source "$DOTFILES/.macos"
    else
        echo "  This will set system preferences and restart Finder/Dock."
        if confirm "Apply macOS preferences?" "n"; then
            source "$DOTFILES/.macos"
        else
            echo "  Skipped. Run later: source $DOTFILES/.macos"
        fi
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  personal MacBook setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if [[ "$RESET" == "true" ]]; then
        echo "  MODE: RESET — force re-apply everything to match dotfiles"
    else
        echo "  MODE: Normal — skip what's already done"
    fi
    echo "  You'll be prompted before each step."
    echo ""

    if ! confirm "Start?" "y"; then
        echo "Aborted."
        exit 0
    fi

    step_xcode
    step_homebrew
    step_dotfiles
    step_packages
    step_xcode_app
    step_symlinks
    step_codex_config
    step_codex_skills
    step_ssh
    step_gh_auth
    step_shell
    step_languages
    step_ollama
    step_app_preferences
    step_macos

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Done!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Next:"
    echo "    1. Open a new terminal (or: exec zsh)"
    echo "    2. Logout/restart for macOS settings"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  APP SETUP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Continue with the app setup registry:"
    echo "    cd $DOTFILES && ./app-status.sh next"
    echo ""
}

if [[ "${DOTFILES_SKIP_MAIN:-false}" != "true" ]]; then
    main "$@"
fi
