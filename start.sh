#!/usr/bin/env zsh

# start.sh — Bootstrap a fresh macOS installation
# Run: curl -sL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh | zsh
# Or:  ~/.dotfiles/start.sh [options]
#
# Options:
#   --all          Run everything without prompts (uses safe defaults)
#   --interactive  Prompt before each step (default)
#   --module NAME  Run only a specific module
#   --list         List available modules
#   --dry-run      Show what would be done without making changes
#   --force        Skip all confirmation prompts
#   --help         Show this help message

set -o pipefail

###############################################################################
# Global Configuration
###############################################################################

DOTFILES="$HOME/.dotfiles"
GITHUB_USER="mhismail3"
SCRIPT_NAME="${0:t}"

# Execution modes
MODE="interactive"  # interactive, all, module
TARGET_MODULE=""
DRY_RUN=false
FORCE=false

###############################################################################
# Pre-flight: Basic Checks Before Anything Else
###############################################################################

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi

# Warn if running as root
if [[ "$EUID" -eq 0 ]]; then
    echo "⚠️  Warning: Running as root is not recommended for dotfiles."
    echo "   Dotfiles should be installed as your normal user."
    echo ""
    echo -n "Continue anyway? (y/N) "
    read REPLY </dev/tty 2>/dev/null || REPLY="n"
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
fi

###############################################################################
# Parse Command Line Arguments
###############################################################################

show_help() {
    cat << 'EOF'
start.sh — Bootstrap a fresh macOS installation

USAGE:
  ./start.sh [OPTIONS]
  curl -sL .../start.sh | zsh

OPTIONS:
  --all, -a         Run everything (prompts for required input only)
  --interactive, -i Prompt before each step (default)
  --module, -m NAME Run only a specific module
  --list, -l        List available modules
  --dry-run, -n     Show what would be done without making changes
  --force, -f       Skip all confirmation prompts (use with --all)
  --help, -h        Show this help message

MODULES:
  core              Xcode CLI Tools, Homebrew, Oh My Zsh
  packages          Install Brewfile packages
  symlinks          Create dotfile symlinks
  ssh               SSH key setup
  shell             Set Zsh as default, configure plugins
  version-managers  Set up nvm, rustup, etc.
  cursor            Cursor IDE configuration
  claude            Claude Code CLI configuration
  superwhisper      SuperWhisper configuration
  raycast           Raycast configuration
  agent-ledger      Agent memory ledger setup
  arc-extensions    Arc browser extensions (1Password, Raindrop.io)
  macos             macOS system preferences

EXAMPLES:
  ./start.sh                      # Interactive mode (default)
  ./start.sh --all                # Run everything, prompt only when needed
  ./start.sh --all --force        # Run everything, no prompts (CI mode)
  ./start.sh --module cursor      # Only set up Cursor
  ./start.sh --list               # Show available modules
  ./start.sh --dry-run --all      # Preview what would happen

EOF
}

list_modules() {
    echo ""
    echo "Available modules:"
    echo ""
    echo "  core              Xcode CLI Tools, Homebrew, Oh My Zsh"
    echo "  packages          Install Brewfile packages"
    echo "  symlinks          Create dotfile symlinks"
    echo "  ssh               SSH key setup"
    echo "  shell             Set Zsh as default shell"
    echo "  version-managers  Set up nvm, Node, Rust, etc."
    echo "  cursor            Cursor IDE configuration"
    echo "  claude            Claude Code CLI configuration"
    echo "  superwhisper      SuperWhisper configuration"
    echo "  raycast           Raycast configuration"
    echo "  agent-ledger      Agent memory ledger setup"
    echo "  arc-extensions    Arc browser extensions (1Password, Raindrop.io)"
    echo "  macos             macOS system preferences"
    echo ""
    echo "Run a specific module with: ./start.sh --module <name>"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all|-a)
            MODE="all"
            shift
            ;;
        --interactive|-i)
            MODE="interactive"
            shift
            ;;
        --module|-m)
            MODE="module"
            TARGET_MODULE="$2"
            shift 2
            ;;
        --list|-l)
            list_modules
            exit 0
            ;;
        --dry-run|-n)
            DRY_RUN=true
            export DOTFILES_DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            export DOTFILES_FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage information."
            exit 1
            ;;
    esac
done

###############################################################################
# Helper Functions
###############################################################################

info() {
    printf "\n\033[1;34m→ %s\033[0m\n" "$1"
}

success() {
    printf "\033[1;32m✓ %s\033[0m\n" "$1"
}

warn() {
    printf "\033[1;33m⚠ %s\033[0m\n" "$1"
}

err() {
    printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2
}

die() {
    err "$1"
    exit 1
}

# Fix known Homebrew cask installation quirks
# Some casks report failure but actually install successfully (e.g., quarantine removal)
fix_cask_quirks() {
    local fixed=0

    # Private Internet Access: Installer succeeds but fails to remove quarantine attribute
    # The app is installed correctly, just needs quarantine cleared manually
    if [[ -d "/Applications/Private Internet Access.app" ]]; then
        if xattr "/Applications/Private Internet Access.app" 2>/dev/null | grep -q "com.apple.quarantine"; then
            echo "  Fixing PIA quarantine attribute (known cask quirk)..."
            sudo xattr -rd com.apple.quarantine "/Applications/Private Internet Access.app" 2>/dev/null && {
                echo "  ✓ PIA quarantine attribute removed"
                ((fixed++))
            } || echo "  ⚠ Could not remove PIA quarantine (non-critical, app will still work)"
        fi
    fi

    # Add other known cask quirks here as needed
    # Example pattern:
    # if [[ -d "/Applications/SomeApp.app" ]]; then
    #     # Fix specific issue
    # fi

    [[ $fixed -gt 0 ]] && echo "  Fixed $fixed known cask quirk(s)"
    return 0
}

# Check if we can prompt interactively
can_prompt() {
    [[ -t 0 ]] || [[ -c /dev/tty ]]
}

# Prompt with default value
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local reply
    
    if [[ "$FORCE" == "true" ]]; then
        [[ "$default" == "y" ]]
        return $?
    fi
    
    if ! can_prompt; then
        warn "Cannot prompt (not a terminal). Using default: $default"
        [[ "$default" == "y" ]]
        return $?
    fi
    
    if [[ "$default" == "y" ]]; then
        echo -n "$prompt (Y/n) "
    else
        echo -n "$prompt (y/N) "
    fi
    
    read reply </dev/tty 2>/dev/null || reply="$default"
    [[ -z "$reply" ]] && reply="$default"
    
    if [[ "$default" == "y" ]]; then
        [[ ! "$reply" =~ ^[Nn]$ ]]
    else
        [[ "$reply" =~ ^[Yy]$ ]]
    fi
}

# Should we run this step?
should_run_step() {
    local step_name="$1"
    
    # In module mode, only run the specified module
    if [[ "$MODE" == "module" ]]; then
        [[ "$step_name" == "$TARGET_MODULE" ]]
        return $?
    fi
    
    # In all mode, run everything
    if [[ "$MODE" == "all" ]]; then
        return 0
    fi
    
    # In interactive mode, ask
    confirm "Run $step_name?" "y"
}

# Safely create a symlink (idempotent)
symlink() {
    local src="$1"
    local dst="$2"
    
    if [[ ! -f "$src" ]] && [[ ! -d "$src" ]]; then
        warn "Source not found: $src"
        return 1
    fi
    
    # Ensure parent directory exists
    local parent="$(dirname "$dst")"
    if [[ ! -d "$parent" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would create: $parent"
        else
            mkdir -p "$parent" || { err "Failed to create: $parent"; return 1; }
        fi
    fi
    
    # Already correctly linked?
    if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
        echo "  Already linked: $dst"
        return 0
    fi
    
    # Handle existing file/symlink
    if [[ -L "$dst" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would remove old symlink: $dst"
        else
            rm "$dst"
        fi
    elif [[ -e "$dst" ]]; then
        local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would backup: $dst → $backup"
        else
            mv "$dst" "$backup" || { err "Failed to backup: $dst"; return 1; }
            echo "  Backed up: $dst → $backup"
        fi
    fi
    
    # Create symlink
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would link: $dst → $src"
    else
        ln -s "$src" "$dst" || { err "Failed to link: $dst → $src"; return 1; }
        echo "  Linked: $dst → $src"
    fi
    
    return 0
}

###############################################################################
# SSH Check: Warn if SSH URL rewriting is enabled but SSH isn't working yet
###############################################################################

# Note: We don't modify .gitconfig here because it's symlinked to dotfiles.
# If SSH isn't working, git operations using GitHub URLs will fail until
# the SSH module runs. This is expected on fresh installs.
if git config --global --get url."git@github.com:".insteadOf &>/dev/null; then
    if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        warn "SSH URL rewriting is enabled but SSH keys aren't set up yet."
        echo "  Git operations to GitHub will fail until SSH module runs."
        echo "  This is normal on fresh installs - SSH will be configured later."
    fi
fi

###############################################################################
# Machine-Specific Configuration
###############################################################################

CONFIG_FILE="$HOME/.dotfiles_config"

load_or_prompt_config() {
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    echo ""
    echo "📋 Using saved configuration:"
    echo "   Computer name: $COMPUTER_NAME"
    echo "   macOS username: $MACOS_USER"
    echo ""
        
        if [[ "$FORCE" != "true" ]] && can_prompt; then
            if ! confirm "Use these settings?" "y"; then
        rm "$CONFIG_FILE"
            fi
    fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🖥️  Machine Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
        local current_name=$(scutil --get ComputerName 2>/dev/null || echo "My-Mac")
        local current_user=$(whoami)
    
        if [[ "$FORCE" == "true" ]] || ! can_prompt; then
            COMPUTER_NAME="$current_name"
            MACOS_USER="$current_user"
        else
    echo "Computer name (for network, sharing, Terminal prompt)"
            echo -n "  [$current_name]: "
            read INPUT_NAME </dev/tty 2>/dev/null || INPUT_NAME=""
            COMPUTER_NAME="${INPUT_NAME:-$current_name}"
            
    echo ""
    echo "macOS username (for SSH access restriction)"
            echo -n "  [$current_user]: "
            read INPUT_USER </dev/tty 2>/dev/null || INPUT_USER=""
            MACOS_USER="${INPUT_USER:-$current_user}"
        fi
        
        if [[ "$DRY_RUN" != "true" ]]; then
            cat > "$CONFIG_FILE" << EOF
# Dotfiles machine-specific configuration
# Generated on $(date)
export COMPUTER_NAME="$COMPUTER_NAME"
export MACOS_USER="$MACOS_USER"
EOF
    echo ""
            success "Configuration saved to $CONFIG_FILE"
        else
            echo "[dry-run] Would save configuration to $CONFIG_FILE"
        fi
    fi

export COMPUTER_NAME
export MACOS_USER
}

###############################################################################
# Show Execution Plan
###############################################################################

show_execution_plan() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Dotfiles Bootstrap"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Mode: $MODE"
    [[ "$DRY_RUN" == "true" ]] && echo "      (dry-run: no changes will be made)"
    [[ "$FORCE" == "true" ]] && echo "      (force: no prompts)"
    [[ -n "$TARGET_MODULE" ]] && echo "Module: $TARGET_MODULE"
    echo ""
    
    if [[ "$MODE" == "interactive" ]]; then
        echo "You will be prompted before each step."
        echo "Press Ctrl+C at any time to abort."
        echo ""
        if ! confirm "Start bootstrap?" "y"; then
            echo "Aborted."
            exit 0
        fi
    fi
}

###############################################################################
# Module: Core (Xcode, Homebrew, Dotfiles Clone, Oh My Zsh)
###############################################################################

run_core() {
    # Xcode Command Line Tools
info "Checking Xcode Command Line Tools..."

if ! xcode-select -p &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would install Xcode Command Line Tools"
        else
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    
            echo "Waiting for Xcode Command Line Tools installation..."
    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    success "Xcode Command Line Tools installed"
        fi
else
    success "Xcode Command Line Tools already installed"
fi

# Homebrew
info "Checking Homebrew..."

if [[ $(uname -m) == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

if [[ ! -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would install Homebrew"
        else
    info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
    success "Homebrew installed"
        fi
else
    success "Homebrew already installed"
fi

    # Add Homebrew to PATH
    if [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_PREFIX
    fi

# Update Homebrew
    if [[ "$DRY_RUN" != "true" ]] && command -v brew &>/dev/null; then
info "Updating Homebrew..."
        brew update || warn "Homebrew update failed (continuing anyway)"
success "Homebrew updated"
    fi

    # Clone Dotfiles
info "Checking dotfiles..."

if [[ ! -d "$DOTFILES" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would clone dotfiles to $DOTFILES"
        else
    info "Cloning dotfiles..."
    if git clone git@github.com:$GITHUB_USER/dotfiles.git "$DOTFILES" 2>/dev/null; then
        success "Dotfiles cloned via SSH"
            elif git clone https://github.com/$GITHUB_USER/dotfiles.git "$DOTFILES"; then
                success "Dotfiles cloned via HTTPS"
    else
                die "Failed to clone dotfiles repository"
            fi
    fi
else
    success "Dotfiles already present at $DOTFILES"
        if [[ "$DRY_RUN" != "true" ]]; then
    info "Pulling latest dotfiles..."
            (cd "$DOTFILES" && git pull --rebase 2>/dev/null) || warn "Could not pull latest (continuing with local copy)"
        fi
fi

    cd "$DOTFILES" 2>/dev/null || true

# Oh My Zsh
info "Checking Oh My Zsh..."

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would install Oh My Zsh"
        else
    info "Installing Oh My Zsh..."
            RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    success "Oh My Zsh installed"
        fi
else
    success "Oh My Zsh already installed"
fi
}

###############################################################################
# Module: Packages
###############################################################################

run_packages() {
info "Installing packages from Brewfile..."

    if [[ ! -f "$DOTFILES/Brewfile" ]]; then
        warn "Brewfile not found at $DOTFILES/Brewfile"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would run: brew bundle --file=$DOTFILES/Brewfile --no-upgrade"
    else
        # Request sudo password upfront for cask installations that require it
        # (e.g., Synology Drive, Google Drive, Logi Options+)
        info "Some apps require admin privileges to install. Requesting password upfront..."
        sudo -v < /dev/tty 2>/dev/null || sudo -v

        # Keep sudo alive during the entire brew bundle process
        (while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done) &
        SUDO_KEEPALIVE_PID=$!

        # Run brew bundle with --no-upgrade to prevent upgrading existing packages
        # Individual package failures won't stop the entire bundle
        brew bundle --file="$DOTFILES/Brewfile" --no-upgrade
        local brew_exit=$?

        # Stop sudo keepalive
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true

        # Handle brew bundle exit code
        if [[ $brew_exit -ne 0 ]]; then
            warn "brew bundle exited with code $brew_exit (some packages may have had issues)"
            warn "You can retry failed packages with: brew bundle --file=~/.dotfiles/Brewfile"
        fi

        # Fix known cask installation quirks
        # Some casks report failure but actually install successfully
        fix_cask_quirks

    success "Brewfile packages installed"
fi

    # Fix Homebrew directory permissions for zsh compinit security check
    # Homebrew directories sometimes get group-write permissions which zsh considers insecure
    info "Fixing Homebrew directory permissions for zsh..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would fix permissions on Homebrew share directories"
    else
        local brew_dirs=(
            "$HOMEBREW_PREFIX/share"
            "$HOMEBREW_PREFIX/share/zsh"
            "$HOMEBREW_PREFIX/share/zsh/site-functions"
            "$HOMEBREW_PREFIX/share/zsh-completions"
        )
        for dir in "${brew_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                chmod go-w "$dir" 2>/dev/null || true
            fi
        done
        success "Homebrew directory permissions fixed"
    fi
}

###############################################################################
# Module: Symlinks
###############################################################################

run_symlinks() {
info "Creating symlinks..."

    local failed=0
    
    symlink "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc" || ((failed++))
    symlink "$DOTFILES/git/.gitconfig" "$HOME/.gitconfig" || ((failed++))
    symlink "$DOTFILES/git/.gitignore_global" "$HOME/.gitignore_global" || ((failed++))
    symlink "$DOTFILES/mackup/.mackup.cfg" "$HOME/.mackup.cfg" || ((failed++))
    symlink "$DOTFILES/mackup/.mackup" "$HOME/.mackup" || ((failed++))
    symlink "$DOTFILES/tmux/.tmux.conf" "$HOME/.tmux.conf" || ((failed++))

    if [[ $failed -gt 0 ]]; then
        warn "$failed symlink(s) failed"
    else
        success "Symlinks created"
    fi
}

###############################################################################
# Module: SSH
###############################################################################

run_ssh() {
    info "SSH Keys..."

    local SSH_KEY="$HOME/.ssh/id_ed25519"

    # Ensure .ssh directory exists with correct permissions
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

if [[ -f "$SSH_KEY" ]]; then
    success "SSH key already exists"
        return 0
    fi

    echo ""
    echo "No SSH key found. You'll need one for GitHub, servers, etc."
    echo ""
    
    if ! confirm "Generate SSH key now?" "y"; then
        echo "  Skipped. Run ~/.dotfiles/setup/ssh.sh later."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would generate SSH key"
        return 0
    fi

    local EMAIL="${GIT_EMAIL:-mhismail3@gmail.com}"
        
        echo ""
        echo "Generating SSH key for $EMAIL..."
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" </dev/tty || {
        err "SSH key generation failed"
        return 1
    }
        
        # Start ssh-agent and add key
        eval "$(ssh-agent -s)" > /dev/null
        ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || ssh-add "$SSH_KEY"
        
        # Create SSH config if needed
    local SSH_CONFIG="$HOME/.ssh/config"
        if [[ ! -f "$SSH_CONFIG" ]]; then
            cat > "$SSH_CONFIG" << 'EOF'
Host *
    # IgnoreUnknown makes this config compatible with both Apple's SSH and Homebrew's OpenSSH
    IgnoreUnknown UseKeychain,AddKeysToAgent
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
        echo ""
    
    if can_prompt && [[ "$FORCE" != "true" ]]; then
        echo -n "Press Enter after adding the key to GitHub..."
        read </dev/tty
        
        echo ""
        echo "Testing GitHub SSH connection..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            success "SSH working! GitHub authentication verified."
        else
            warn "Could not verify SSH connection (this is sometimes normal)"
            echo "  You may need to wait a moment and try: ssh -T git@github.com"
        fi
    fi
}

###############################################################################
# Module: Shell
###############################################################################

run_shell() {
info "Checking default shell..."

if [[ "$SHELL" != *"zsh"* ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would set Zsh as default shell"
        else
    info "Setting Zsh as default shell..."
            chsh -s "$(which zsh)" || warn "Failed to change default shell"
    success "Default shell set to Zsh"
        fi
else
    success "Zsh is already the default shell"
fi

    # Create common directories
    info "Creating directories..."
    
    local dirs=("$HOME/Downloads/projects" "$HOME/.ssh")
    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            [[ ! -d "$dir" ]] && echo "[dry-run] Would create: $dir"
        else
            mkdir -p "$dir"
        fi
    done
    
    success "Directories created"
}

###############################################################################
# Module: Version Managers
###############################################################################

run_version_managers() {
info "Setting up version managers..."

    # NVM and Node
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"

    local nvm_sh="$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
    
    if [[ -s "$nvm_sh" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would install Node LTS via nvm"
        else
    source "$nvm_sh"

    local current_node
    current_node=$( (command -v node >/dev/null 2>&1 && node -v 2>/dev/null) || echo "" )

    if [[ -z "$current_node" ]]; then
        info "Installing latest LTS Node via nvm..."
    else
        info "Ensuring latest LTS Node via nvm (current: $current_node)..."
    fi

            if nvm install --lts --latest-npm 2>/dev/null; then
        nvm alias default "lts/*" >/dev/null 2>&1 || true
        success "Node (LTS) installed via nvm"
    else
                warn "nvm install failed (Node may need manual installation)"
            fi

            command -v corepack &>/dev/null && corepack enable >/dev/null 2>&1 || true
        fi
    else
        warn "nvm not found (install via Brewfile first)"
    fi

    # Rust
if command -v rustup-init &>/dev/null && [[ ! -d "$HOME/.rustup" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would install Rust toolchain"
        else
    info "Installing Rust toolchain..."
            rustup-init -y --no-modify-path || warn "Rust installation failed"
    success "Rust installed"
        fi
elif [[ -d "$HOME/.rustup" ]]; then
    success "Rust already installed"
fi

    # Git LFS
    if command -v git-lfs &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would configure Git LFS"
        else
            info "Setting up Git LFS..."
            git lfs install --system 2>/dev/null || git lfs install
            success "Git LFS configured"
        fi
    fi

    success "Version managers configured"
}

###############################################################################
# Module: Cursor
###############################################################################

run_cursor() {
    if [[ -f "$DOTFILES/setup/cursor.sh" ]]; then
        _DOTFILES_SOURCING=1 source "$DOTFILES/setup/cursor.sh"
    else
        warn "Cursor setup script not found"
    fi
}

###############################################################################
# Module: Claude Code
###############################################################################

run_claude() {
    if [[ -f "$DOTFILES/setup/claude.sh" ]]; then
        _DOTFILES_SOURCING=1 source "$DOTFILES/setup/claude.sh"
    else
        warn "Claude Code setup script not found"
    fi
}

###############################################################################
# Module: SuperWhisper
###############################################################################

run_superwhisper() {
    if [[ -f "$DOTFILES/setup/superwhisper.sh" ]]; then
        _DOTFILES_SOURCING=1 source "$DOTFILES/setup/superwhisper.sh"
    else
        warn "SuperWhisper setup script not found"
    fi
}

###############################################################################
# Module: Raycast
###############################################################################

run_raycast() {
    if [[ -f "$DOTFILES/setup/raycast.sh" ]]; then
        _DOTFILES_SOURCING=1 source "$DOTFILES/setup/raycast.sh"
    else
        warn "Raycast setup script not found"
    fi
}

###############################################################################
# Module: Agent Ledger
###############################################################################

run_agent_ledger() {
    if [[ -f "$DOTFILES/setup/agent-ledger.sh" ]]; then
        _DOTFILES_SOURCING=1 source "$DOTFILES/setup/agent-ledger.sh"
    else
        warn "Agent ledger setup script not found"
    fi
}

###############################################################################
# Module: Arc Browser Extensions
###############################################################################

run_arc_extensions() {
    info "Arc browser extensions..."

    if [[ ! -d "/Applications/Arc.app" ]]; then
        echo "  Arc not installed, skipping extensions"
        return 0
    fi

    if [[ ! -d "$HOME/Library/Application Support/Arc/User Data" ]]; then
        warn "Arc hasn't been launched yet. Launch Arc first to set up extensions."
        return 0
    fi

    if [[ -f "$DOTFILES/setup/arc-extensions.sh" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            "$DOTFILES/setup/arc-extensions.sh" --dry-run
        else
            "$DOTFILES/setup/arc-extensions.sh"
        fi
    else
        warn "Arc extensions script not found"
    fi
}

###############################################################################
# Module: macOS Preferences
###############################################################################

run_macos() {
    info "macOS preferences..."

    local MACOS_SCRIPT="$DOTFILES/macos/.macos"

    if [[ ! -f "$MACOS_SCRIPT" ]]; then
        warn ".macos not found at $MACOS_SCRIPT"
        return 1
    fi

    echo ""
    echo "The .macos script will:"
    echo "  - Set system preferences (requires sudo password)"
    echo "  - Restart Dock, Finder, and other system processes"
    echo ""
    
    if ! confirm "Apply macOS preferences?" "n"; then
        echo "  Skipped. Run later: source ~/.dotfiles/macos/.macos"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would source $MACOS_SCRIPT"
    else
        source "$MACOS_SCRIPT"
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Show execution plan
    show_execution_plan
    
    # Load or prompt for machine config
    load_or_prompt_config
    
    # Execute modules based on mode
    if [[ "$MODE" == "module" ]]; then
        case "$TARGET_MODULE" in
            core)             run_core ;;
            packages)         run_packages ;;
            symlinks)         run_symlinks ;;
            ssh)              run_ssh ;;
            shell)            run_shell ;;
            version-managers) run_version_managers ;;
            cursor)           run_cursor ;;
            claude)           run_claude ;;
            superwhisper)     run_superwhisper ;;
            raycast)          run_raycast ;;
            agent-ledger)     run_agent_ledger ;;
            arc-extensions)   run_arc_extensions ;;
            macos)            run_macos ;;
            *)
                die "Unknown module: $TARGET_MODULE (use --list to see available modules)"
                ;;
        esac
    else
        # Run all modules (with prompts in interactive mode)
        should_run_step "core" && run_core
        should_run_step "packages" && run_packages
        should_run_step "symlinks" && run_symlinks
        should_run_step "ssh" && run_ssh
        should_run_step "shell" && run_shell
        should_run_step "version-managers" && run_version_managers
        should_run_step "cursor" && run_cursor
        should_run_step "claude" && run_claude
        should_run_step "superwhisper" && run_superwhisper
        should_run_step "raycast" && run_raycast
        should_run_step "agent-ledger" && run_agent_ledger
        should_run_step "arc-extensions" && run_arc_extensions
        should_run_step "macos" && run_macos
    fi

    # Done!
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 Dry run complete! No changes were made."
    else
echo "🎉 Bootstrap complete!"
    fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
echo "Next steps:"
        echo "  1. Open a new terminal (or run: exec zsh)"
        echo "  2. Sign into Apple ID if not done"
echo "  3. Logout/restart to apply all macOS settings"
echo ""
        echo "Standalone scripts:"
        echo "  ~/.dotfiles/setup/cursor.sh"
        echo "  ~/.dotfiles/setup/claude.sh"
        echo "  ~/.dotfiles/setup/superwhisper.sh"
        echo "  ~/.dotfiles/setup/raycast.sh"
        echo "  ~/.dotfiles/setup/ssh.sh"
        echo "  ~/.dotfiles/setup/screenshots.sh"
echo ""
    fi
}

# Run main
main "$@"
