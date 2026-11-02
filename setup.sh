#!/usr/bin/env zsh

# setup.sh — Bootstrap test-host (headless M4 Mac mini for builds/tests)
# Run: ~/.dotfiles/setup.sh [--reset]
#
# Default mode: skip what's already done (safe to re-run)
# --reset mode: force re-apply everything to match dotfiles
#
# Pins (keep in sync with tron/config/ci-toolchain.env):
XCODE_VERSION="${XCODE_VERSION:-26.6}"
IOS_RUNTIME="${IOS_RUNTIME:-26.5}"

set -o pipefail

DOTFILES="$HOME/.dotfiles"
GITHUB_USER="mhismail3"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-test-host}"
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

    if [[ "$RESET" == "true" ]]; then
        # Force: remove whatever's there and re-link
        [[ -L "$dst" ]] && rm "$dst"
        [[ -e "$dst" ]] && mv "$dst" "$dst.bak.$(date +%s)"
        ln -s "$src" "$dst" && echo "  Linked: $dst -> $src"
        return 0
    fi

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

step_clt() {
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
    HOMEBREW_PREFIX="/opt/homebrew"
    [[ $(uname -m) == "arm64" ]] || HOMEBREW_PREFIX="/usr/local"
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
        (cd "$DOTFILES" && git fetch origin "$DOTFILES_BRANCH" && git checkout "$DOTFILES_BRANCH" && git pull --rebase 2>/dev/null) || true
    else
        git clone --branch "$DOTFILES_BRANCH" https://github.com/$GITHUB_USER/dotfiles.git "$DOTFILES" || \
            { err "Failed to clone"; return 1; }
        success "Cloned"
    fi
}

###############################################################################
# Step 4: Brew bundle
###############################################################################

step_packages() {
    info "Installing packages from Brewfile"
    if [[ "$RESET" == "true" ]]; then
        brew bundle --file="$DOTFILES/Brewfile" --force
    else
        brew bundle --file="$DOTFILES/Brewfile" --no-upgrade
    fi
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
    mkdir -p "$HOME/Workspace" "$HOME/.local/bin"
    success "Symlinks created"
}

###############################################################################
# Step 6: GitHub CLI auth + Git LFS
###############################################################################

step_gh_auth() {
    info "GitHub CLI authentication"
    if gh auth status &>/dev/null && [[ "$RESET" != "true" ]]; then
        success "Already authenticated"
    else
        echo "  Sets up the git credential helper for HTTPS clones."
        gh auth login </dev/tty
        gh auth setup-git
        success "Authenticated"
    fi
    git lfs install 2>/dev/null && success "Git LFS configured"
}

###############################################################################
# Step 7: Xcode + iOS simulator runtime
###############################################################################

step_xcode() {
    info "Xcode $XCODE_VERSION + iOS $IOS_RUNTIME runtime"
    local want="/Applications/Xcode.app"
    if [[ -d "$want" ]] && /usr/bin/xcodebuild -version 2>/dev/null | grep -qx "Xcode $XCODE_VERSION"; then
        success "Xcode $XCODE_VERSION already installed"
    else
        echo "  xcodes needs your Apple ID once (stored in Keychain)."
        xcodes install "$XCODE_VERSION" --experimental-unxip --directory /Applications </dev/tty || \
            { warn "xcodes install failed; install Xcode $XCODE_VERSION manually"; return 0; }
        local installed
        installed="$(ls -d /Applications/Xcode-"$XCODE_VERSION"*.app 2>/dev/null | head -1)"
        [[ -n "$installed" && ! -e "$want" ]] && sudo mv "$installed" "$want"
    fi
    sudo xcode-select -s "$want/Contents/Developer"
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch
    sudo DevToolsSecurity -enable >/dev/null 2>&1 || true
    sudo dseditgroup -o edit -a "$(whoami)" -t user _developer 2>/dev/null || true

    if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS $IOS_RUNTIME"; then
        success "iOS $IOS_RUNTIME runtime present"
    else
        xcodebuild -downloadPlatform iOS -buildVersion "$IOS_RUNTIME" || \
            xcodes runtimes install "iOS $IOS_RUNTIME" || warn "Install iOS $IOS_RUNTIME runtime manually"
    fi
    success "Xcode ready: $(xcodebuild -version | head -1)"
}

###############################################################################
# Step 8: Tailscale (system daemon, survives logout)
###############################################################################

step_tailscale() {
    info "Tailscale"
    sudo tailscaled install-system-daemon 2>/dev/null || true
    sleep 2
    if tailscale status &>/dev/null; then
        success "Already on the tailnet as $(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' 2>/dev/null)"
    else
        echo "  Opens a login URL; sign in with the same tailnet as the main Mac."
        sudo tailscale up --ssh --hostname "${HOST_NAME:-tron-test-mini}"
        success "Joined tailnet"
    fi
}

###############################################################################
# Step 9: macOS preferences (headless, always-on, lean)
###############################################################################

step_macos() {
    info "macOS preferences"
    if [[ "$RESET" == "true" ]] || confirm "Apply macOS preferences (hostname, SSH, power, lean services)?" "y"; then
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
    echo "  test-host setup — $( [[ "$RESET" == "true" ]] && echo RESET || echo normal ) mode"
    echo "  Xcode $XCODE_VERSION, iOS runtime $IOS_RUNTIME, host ${HOST_NAME:-tron-test-mini}"
    echo ""
    confirm "Start?" "y" || { echo "Aborted."; exit 0; }

    step_clt
    step_homebrew
    step_dotfiles
    step_packages
    step_symlinks
    step_gh_auth
    step_xcode
    step_tailscale
    step_macos

    echo ""
    echo "  Done. Restart once so auto-login, power and lean settings take effect."
    echo "  Then from the main Mac:  ssh $(whoami)@${HOST_NAME:-tron-test-mini}"
    echo ""
}

main "$@"
