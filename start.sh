#!/usr/bin/env zsh

# start.sh — Bootstrap a fresh macOS installation
# Run: curl -sL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh | zsh
# Or:  ~/.dotfiles/start.sh

# Note: We don't use `set -e` because we want the script to continue
# even if some steps fail (e.g., a cask install fails but others succeed)

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi

DOTFILES="$HOME/.dotfiles"
GITHUB_USER="mhismail3"  # GitHub username, not email

###############################################################################
# Fix: Disable SSH URL rewriting until SSH keys are set up
# This prevents "Permission denied (publickey)" errors with brew/git
###############################################################################

if git config --global --get url."git@github.com:".insteadOf &>/dev/null; then
    # Check if SSH to GitHub actually works
    if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "⚠️  Disabling SSH URL rewriting (SSH keys not set up yet)"
        git config --global --unset url."git@github.com:".insteadOf 2>/dev/null || true
    fi
fi

###############################################################################
# Machine-Specific Configuration (prompted on first run)
###############################################################################

CONFIG_FILE="$HOME/.dotfiles_config"

if [[ -f "$CONFIG_FILE" ]]; then
    # Load existing config
    source "$CONFIG_FILE"
    echo ""
    echo "📋 Using saved configuration:"
    echo "   Computer name: $COMPUTER_NAME"
    echo "   macOS username: $MACOS_USER"
    echo ""
    echo -n "Use these settings? (Y/n) "
    read REPLY </dev/tty || REPLY="y"
    echo ""
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        rm "$CONFIG_FILE"
    fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🖥️  Machine Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Get current values as defaults
    CURRENT_COMPUTER_NAME=$(scutil --get ComputerName 2>/dev/null || echo "My-Mac")
    CURRENT_USER=$(whoami)
    
    # Prompt for computer name (read from /dev/tty to work with curl pipe)
    echo "Computer name (for network, sharing, Terminal prompt)"
    echo -n "  [$CURRENT_COMPUTER_NAME]: "
    read INPUT_COMPUTER_NAME </dev/tty || INPUT_COMPUTER_NAME=""
    COMPUTER_NAME="${INPUT_COMPUTER_NAME:-$CURRENT_COMPUTER_NAME}"
    
    # Prompt for macOS username (for SSH access restriction)
    echo ""
    echo "macOS username (for SSH access restriction)"
    echo -n "  [$CURRENT_USER]: "
    read INPUT_USER </dev/tty || INPUT_USER=""
    MACOS_USER="${INPUT_USER:-$CURRENT_USER}"
    
    # Save config for future runs
    echo "# Dotfiles machine-specific configuration" > "$CONFIG_FILE"
    echo "# Generated on $(date)" >> "$CONFIG_FILE"
    echo "export COMPUTER_NAME=\"$COMPUTER_NAME\"" >> "$CONFIG_FILE"
    echo "export MACOS_USER=\"$MACOS_USER\"" >> "$CONFIG_FILE"
    
    echo ""
    echo "✅ Configuration saved to $CONFIG_FILE"
    echo ""
fi

# Export for use in .macos
export COMPUTER_NAME
export MACOS_USER

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
    # Run Homebrew installer interactively (needs sudo password)
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
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
    # --no-upgrade: don't upgrade already installed packages (faster, idempotent)
    brew bundle --file="$DOTFILES/Brewfile" --no-upgrade || {
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
# SSH Key Setup
###############################################################################

info "SSH Keys..."

SSH_KEY="$HOME/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
    success "SSH key already exists"
else
    echo ""
    echo "No SSH key found. You'll need one for GitHub, servers, etc."
    echo ""
    echo -n "Generate SSH key now? (Y/n) "
    read REPLY </dev/tty || REPLY="y"
    
    if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
        EMAIL="${GIT_EMAIL:-mhismail3@gmail.com}"
        
        echo ""
        echo "Generating SSH key for $EMAIL..."
        ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" </dev/tty
        
        # Start ssh-agent and add key
        eval "$(ssh-agent -s)" > /dev/null
        ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || ssh-add "$SSH_KEY"
        
        # Create SSH config if needed
        SSH_CONFIG="$HOME/.ssh/config"
        if [[ ! -f "$SSH_CONFIG" ]]; then
            cat > "$SSH_CONFIG" << 'EOF'
Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
            chmod 600 "$SSH_CONFIG"
        fi
        
        chmod 600 "$SSH_KEY"
        chmod 644 "$SSH_KEY.pub"
        
        # Copy to clipboard
        pbcopy < "$SSH_KEY.pub"
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📋 SSH public key copied to clipboard!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Add it to GitHub now: https://github.com/settings/keys"
        echo "  1. Click 'New SSH key'"
        echo "  2. Paste (Cmd+V)"
        echo "  3. Click 'Add SSH key'"
        echo ""
        echo -n "Press Enter after adding the key to GitHub..."
        read </dev/tty
        
        # Test connection and enable SSH for git
        echo ""
        echo "Testing GitHub SSH connection..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            git config --global url."git@github.com:".insteadOf "https://github.com/"
            success "SSH working! Git configured to use SSH for GitHub"
        else
            echo "⚠️  Could not verify SSH connection (this is sometimes normal)"
            echo -n "Enable SSH for git anyway? (y/N) "
            read REPLY </dev/tty || REPLY="n"
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                git config --global url."git@github.com:".insteadOf "https://github.com/"
                success "Git configured to use SSH for GitHub"
            fi
        fi
    else
        echo "  Skipped. Run ~/.dotfiles/ssh.sh later to set up SSH."
    fi
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
    echo -n "Apply macOS preferences now? (y/N) "
    read REPLY </dev/tty || REPLY="n"
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
# iCloud Photo Library Sync
###############################################################################

info "iCloud Photo Library..."

echo ""
echo "If you've signed into your Apple ID and enabled iCloud Photos,"
echo "opening Photos now will start syncing your library in the background."
echo ""
echo -n "Open Photos app to start iCloud sync? (y/N) "
read REPLY </dev/tty || REPLY="n"
echo ""
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    # Open Photos in background (won't steal focus)
    open -gja "Photos"
    success "Photos opened in background — iCloud sync will begin"
else
    echo "  Skipped. Open Photos manually later to sync your library."
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
echo "  1. Sign into Apple ID (System Settings → Apple ID) if not done"
echo "  2. Open a new terminal (or run: exec zsh)"
echo "  3. Logout/restart to apply all macOS settings"
echo ""
echo "To re-run safely (idempotent):"
echo "  ~/.dotfiles/start.sh"
echo ""

