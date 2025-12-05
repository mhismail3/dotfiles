#!/usr/bin/env zsh

# start.sh — Bootstrap a fresh macOS installation
# Run: curl -sL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh | zsh
# Or:  ~/.dotfiles/start.sh

set -e

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi

DOTFILES="$HOME/.dotfiles"
GITHUB_USER="mhismail3"  # GitHub username, not email

###############################################################################
# Helper Functions
###############################################################################

info() {
    printf "\n\033[1;34m→ %s\033[0m\n" "$1"
}

success() {
    printf "\033[1;32m✓ %s\033[0m\n" "$1"
}

error() {
    printf "\033[1;31m✗ %s\033[0m\n" "$1"
    exit 1
}

###############################################################################
# Xcode Command Line Tools
###############################################################################

info "Checking Xcode Command Line Tools..."

if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    
    # Wait for installation
    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    success "Xcode Command Line Tools installed"
else
    success "Xcode Command Line Tools already installed"
fi

###############################################################################
# Homebrew
###############################################################################

info "Checking Homebrew..."

# Ensure Homebrew is in PATH for this script (Apple Silicon vs Intel)
if [[ $(uname -m) == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

if [[ ! -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
    info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success "Homebrew installed"
else
    success "Homebrew already installed"
fi

# Add Homebrew to PATH for this session
eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_PREFIX

# Update Homebrew
info "Updating Homebrew..."
brew update
success "Homebrew updated"

###############################################################################
# Clone Dotfiles (if not already present)
###############################################################################

info "Checking dotfiles..."

if [[ ! -d "$DOTFILES" ]]; then
    info "Cloning dotfiles..."
    # Try SSH first, fall back to HTTPS
    if git clone git@github.com:$GITHUB_USER/dotfiles.git "$DOTFILES" 2>/dev/null; then
        success "Dotfiles cloned via SSH"
    else
        git clone https://github.com/$GITHUB_USER/dotfiles.git "$DOTFILES"
        success "Dotfiles cloned via HTTPS"
    fi
else
    success "Dotfiles already present at $DOTFILES"
    # Optionally pull latest changes
    info "Pulling latest dotfiles..."
    cd "$DOTFILES" && git pull --rebase 2>/dev/null || true
fi

cd "$DOTFILES"

###############################################################################
# Oh My Zsh
###############################################################################

info "Checking Oh My Zsh..."

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    success "Oh My Zsh installed"
else
    success "Oh My Zsh already installed"
fi

###############################################################################
# Homebrew Bundle
###############################################################################

info "Installing packages from Brewfile..."

if [[ -f "$DOTFILES/Brewfile" ]]; then
    # --no-lock: don't create Brewfile.lock.json
    # --no-upgrade: don't upgrade already installed packages (faster, idempotent)
    brew bundle --file="$DOTFILES/Brewfile" --no-lock --no-upgrade || {
        echo "  Some packages may have failed to install. Check output above."
    }
    success "Brewfile packages installed"
else
    error "Brewfile not found at $DOTFILES/Brewfile"
fi

###############################################################################
# Symlink Dotfiles
###############################################################################

info "Creating symlinks..."

# Function to safely symlink (idempotent)
symlink() {
    local src="$1"
    local dst="$2"
    
    if [[ -f "$src" ]] || [[ -d "$src" ]]; then
        # If already correctly linked, skip
        if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
            echo "  Already linked: $dst"
            return 0
        fi
        
        # Remove existing symlink or backup existing file
        if [[ -L "$dst" ]]; then
            rm "$dst"
        elif [[ -e "$dst" ]]; then
            local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
            mv "$dst" "$backup"
            echo "  Backed up existing $dst → $backup"
        fi
        
        ln -s "$src" "$dst"
        echo "  Linked: $dst → $src"
    else
        echo "  Warning: Source not found: $src"
    fi
}

symlink "$DOTFILES/.zshrc" "$HOME/.zshrc"
symlink "$DOTFILES/.gitconfig" "$HOME/.gitconfig"
symlink "$DOTFILES/.gitignore_global" "$HOME/.gitignore_global"
symlink "$DOTFILES/.mackup.cfg" "$HOME/.mackup.cfg"
symlink "$DOTFILES/.mackup" "$HOME/.mackup"

success "Symlinks created"

###############################################################################
# Zsh Plugins (from Homebrew)
###############################################################################

info "Configuring Zsh plugins..."

# Source plugins in .zshrc will handle this, but ensure they're available
ZSH_PLUGINS_DIR="${HOMEBREW_PREFIX:-/opt/homebrew}/share"

if [[ -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]]; then
    success "Zsh plugins available"
fi

###############################################################################
# Create Common Directories
###############################################################################

info "Creating directories..."

mkdir -p "$HOME/Downloads/projects"
mkdir -p "$HOME/.ssh"

success "Directories created"

###############################################################################
# SSH Setup Reminder
###############################################################################

info "SSH Keys..."

if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    echo "  No SSH key found. Run ssh.sh to generate one:"
    echo "  ~/.dotfiles/ssh.sh"
else
    success "SSH key exists"
fi

###############################################################################
# Set Default Shell to Zsh
###############################################################################

info "Checking default shell..."

if [[ "$SHELL" != *"zsh"* ]]; then
    info "Setting Zsh as default shell..."
    chsh -s "$(which zsh)"
    success "Default shell set to Zsh"
else
    success "Zsh is already the default shell"
fi

###############################################################################
# Initialize Version Managers (one-time setup)
###############################################################################

info "Setting up version managers..."

# Create nvm directory (nvm needs this)
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"

# Initialize rustup (if not already done)
if command -v rustup-init &>/dev/null && [[ ! -d "$HOME/.rustup" ]]; then
    info "Installing Rust toolchain..."
    rustup-init -y --no-modify-path
    success "Rust installed"
elif [[ -d "$HOME/.rustup" ]]; then
    success "Rust already installed"
fi

# Note: pyenv, nvm, rbenv will be lazy-loaded in .zshrc for fast shell startup
success "Version managers configured (lazy-loaded in shell)"

###############################################################################
# macOS Preferences (Run Last!)
###############################################################################

info "Applying macOS preferences..."

if [[ -f "$DOTFILES/.macos" ]]; then
    # Ask before running .macos (it restarts Dock/Finder and requires sudo)
    echo ""
    echo "The .macos script will:"
    echo "  - Set system preferences (requires sudo password)"
    echo "  - Restart Dock, Finder, and other system processes"
    echo ""
    read -q "REPLY?Apply macOS preferences now? (y/N) "
    echo ""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        source "$DOTFILES/.macos"
    else
        echo "  Skipped. Run manually later: source ~/.dotfiles/.macos"
    fi
else
    echo "  Warning: .macos not found"
fi

###############################################################################
# Git LFS Setup
###############################################################################

if command -v git-lfs &>/dev/null; then
    info "Setting up Git LFS..."
    git lfs install --system 2>/dev/null || git lfs install
    success "Git LFS configured"
fi

###############################################################################
# Done
###############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Bootstrap complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Review any MANUAL STEPS printed above"
echo "  2. Generate SSH key: ~/.dotfiles/ssh.sh"
echo "  3. Open a new terminal (or run: exec zsh)"
echo "  4. Logout/restart to apply all macOS settings"
echo ""
echo "To re-run safely (idempotent):"
echo "  ~/.dotfiles/start.sh"
echo ""

