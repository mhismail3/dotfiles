#!/usr/bin/env zsh

# setup.sh — Bootstrap mac-server from scratch
# Run: ~/.dotfiles/setup.sh

set -o pipefail

DOTFILES="$HOME/.dotfiles"
GITHUB_USER="mhismail3"

###############################################################################
# Helpers
###############################################################################

info()    { printf "\n\033[1;34m→ %s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn()    { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
err()     { printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2; }

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
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { warn "Source not found: $src"; return 1; }
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
        echo "  Already linked: $dst"
        return 0
    fi
    [[ -e "$dst" ]] && mv "$dst" "$dst.bak.$(date +%s)"
    ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
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
    if [[ -d "$DOTFILES" ]]; then
        success "Already at $DOTFILES"
        (cd "$DOTFILES" && git pull --rebase 2>/dev/null) || true
    else
        git clone https://github.com/$GITHUB_USER/dotfiles.git "$DOTFILES" || \
            { err "Failed to clone"; return 1; }
        success "Cloned"
    fi
}

###############################################################################
# Step 4: Brew bundle
###############################################################################

step_packages() {
    info "Installing packages from Brewfile"
    sudo -v < /dev/tty 2>/dev/null || sudo -v
    (while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done) &
    local keepalive=$!

    brew bundle --file="$DOTFILES/Brewfile" --no-upgrade
    kill "$keepalive" 2>/dev/null || true

    # Fix zsh compinit permissions
    local dirs=("$HOMEBREW_PREFIX/share" "$HOMEBREW_PREFIX/share/zsh" "$HOMEBREW_PREFIX/share/zsh/site-functions" "$HOMEBREW_PREFIX/share/zsh-completions")
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] && chmod go-w "$d" 2>/dev/null || true
    done
    success "Packages installed"
}

###############################################################################
# Step 5: Symlinks
###############################################################################

step_symlinks() {
    info "Creating symlinks"
    symlink "$DOTFILES/zsh/.zshrc"             "$HOME/.zshrc"
    symlink "$DOTFILES/git/.gitconfig"         "$HOME/.gitconfig"
    symlink "$DOTFILES/git/.gitignore_global"  "$HOME/.gitignore_global"
    symlink "$DOTFILES/tmux/.tmux.conf"        "$HOME/.tmux.conf"
    symlink "$DOTFILES/starship/starship.toml" "$HOME/.config/starship.toml"
    success "Symlinks created"
}

###############################################################################
# Step 6: SSH key
###############################################################################

step_ssh() {
    info "SSH key"
    local key="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

    if [[ -f "$key" ]]; then
        success "Key already exists"
        return 0
    fi

    if ! confirm "Generate SSH key?" "y"; then
        echo "  Skipped"
        return 0
    fi

    ssh-keygen -t ed25519 -C "mhismail3@gmail.com" -f "$key" </dev/tty
    eval "$(ssh-agent -s)" > /dev/null
    ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add "$key"

    if [[ ! -f "$HOME/.ssh/config" ]]; then
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

    chmod 600 "$key"
    chmod 644 "$key.pub"
    pbcopy < "$key.pub"
    echo ""
    echo "  Public key copied to clipboard!"
    echo "  Add to GitHub: https://github.com/settings/keys"
    echo ""
    echo -n "  Press Enter after adding..."
    read </dev/tty
    success "SSH key configured"
}

###############################################################################
# Step 7: GitHub CLI auth
###############################################################################

step_gh_auth() {
    info "GitHub CLI authentication"
    if gh auth status &>/dev/null; then
        success "Already authenticated"
    else
        echo "  This sets up git credential helper for HTTPS."
        gh auth login </dev/tty
        success "Authenticated"
    fi

    # Configure Git LFS
    if command -v git-lfs &>/dev/null; then
        git lfs install --system 2>/dev/null || git lfs install
        success "Git LFS configured"
    fi
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
    success "Directories created"
}

###############################################################################
# Step 9: Language runtimes
###############################################################################

step_languages() {
    info "Language runtimes"

    # Rust
    if [[ ! -d "$HOME/.rustup" ]] && command -v rustup-init &>/dev/null; then
        rustup-init -y --no-modify-path || warn "Rust install failed"
        success "Rust installed"
    elif [[ -d "$HOME/.rustup" ]]; then
        success "Rust already installed"
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
        else
            success "Node already installed ($(node -v))"
        fi
    fi

    # Ruby (via rbenv)
    if command -v rbenv &>/dev/null; then
        success "rbenv available"
    fi

    # Python — uv handles everything, no pyenv needed
    if command -v uv &>/dev/null; then
        success "uv available (Python managed via uv)"
    fi

    success "Languages configured"
}

###############################################################################
# Step 10: Claude Code
###############################################################################

step_claude() {
    info "Claude Code"
    if ! command -v claude &>/dev/null; then
        warn "Claude Code not installed yet (will be available after Brewfile)"
        return 0
    fi

    local src="$DOTFILES/claude"
    local dst="$HOME/.claude"
    mkdir -p "$dst" "$dst/skills"

    [[ -f "$src/CLAUDE.md" ]]     && symlink "$src/CLAUDE.md"     "$dst/CLAUDE.md"
    [[ -f "$src/settings.json" ]] && symlink "$src/settings.json" "$dst/settings.json"
    [[ -f "$src/LEDGER.jsonl" ]]  && symlink "$src/LEDGER.jsonl"  "$dst/LEDGER.jsonl"
    [[ -d "$src/skills" ]]        && {
        [[ -L "$dst/skills" ]] && rm "$dst/skills"
        [[ -d "$dst/skills" ]] && rm -rf "$dst/skills"
        ln -s "$src/skills" "$dst/skills" && echo "  Linked: skills/"
    }

    success "Claude Code configured"
}

###############################################################################
# Step 11: Ollama
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
# Step 12: macOS preferences
###############################################################################

step_macos() {
    info "macOS preferences"
    if [[ ! -f "$DOTFILES/macos/.macos" ]]; then
        warn ".macos not found"
        return 1
    fi

    echo "  This will set system preferences and restart Finder/Dock."
    if confirm "Apply macOS preferences?" "n"; then
        source "$DOTFILES/macos/.macos"
    else
        echo "  Skipped. Run later: source ~/.dotfiles/macos/.macos"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  mac-server setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  This will set up a fresh macOS install."
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
    step_symlinks
    step_ssh
    step_gh_auth
    step_shell
    step_languages
    step_claude
    step_ollama
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
    echo "  APP LOGINS — Sign in to these manually"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  [ ] Google Chrome — sign in to sync bookmarks/extensions/passwords"
    echo "  [ ] Tailscale — sign in to link this machine to your tailnet"
    echo "  [ ] Synology Drive — connect to NAS (server address + credentials)"
    echo "  [ ] Google Drive — sign in to Google account"
    echo "  [ ] Private Internet Access — sign in with PIA credentials"
    echo "  [ ] Cursor — sign in for AI features / settings sync"
    echo "  [ ] RustDesk — set up password and ID for remote access"
    echo "  [ ] Claude Code — run 'claude' to authenticate (browser-based)"
    echo "  [ ] Docker Desktop — enable 'Start Docker Desktop when you sign in'"
    echo "      in Docker Desktop > Settings > General, then optionally log in"
    echo ""
}

main "$@"
