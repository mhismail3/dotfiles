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

step_app_preferences() {
    info "App preferences"
    apply_synology_drive_preferences
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
