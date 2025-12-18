#!/usr/bin/env zsh

# ssh.sh — Generate SSH key and add to ssh-agent
# Run standalone: ~/.dotfiles/setup/ssh.sh [options] [email]
# Or sourced by start.sh during bootstrap
#
# Options:
#   --force, -f    Skip confirmation prompts
#   --dry-run, -n  Show what would be done
#   --help, -h     Show help
#
# Arguments:
#   email          Email for SSH key comment (default: mhismail3@gmail.com)

# ============================================================================
# Initialization
# ============================================================================

# Defaults
SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
EMAIL="mhismail3@gmail.com"
FORCE=false
DRY_RUN=false

# Parse arguments if running standalone
if [[ "${(%):-%N}" == "$0" ]] || [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE=true
                export DOTFILES_FORCE=true
                shift
                ;;
            --dry-run|-n)
                DRY_RUN=true
                export DOTFILES_DRY_RUN=true
                shift
                ;;
            --help|-h)
                cat << 'EOF'
ssh.sh — Generate SSH key and add to ssh-agent

USAGE:
  ./ssh.sh [OPTIONS] [EMAIL]

OPTIONS:
  --force, -f    Skip confirmation prompts
  --dry-run, -n  Show what would be done
  --help, -h     Show this help

ARGUMENTS:
  EMAIL          Email for SSH key comment (default: mhismail3@gmail.com)

EXAMPLES:
  ./ssh.sh                           # Interactive mode
  ./ssh.sh user@example.com          # Use specific email
  ./ssh.sh --force                   # Non-interactive (skip if key exists)

EOF
                exit 0
                ;;
            --*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                EMAIL="$1"
                shift
                ;;
        esac
    done
fi

# Read from environment if set
FORCE="${DOTFILES_FORCE:-$FORCE}"
DRY_RUN="${DOTFILES_DRY_RUN:-$DRY_RUN}"

# Source shared library (optional - script works without it)
SCRIPT_DIR="${0:A:h}"
if [[ -f "$SCRIPT_DIR/_lib.sh" ]]; then
    source "$SCRIPT_DIR/_lib.sh"
fi

# Minimal helpers if _lib.sh not loaded
info() { printf "\n\033[1;34m→ %s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
err() { printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2; }

can_prompt() {
    [[ -t 0 ]] || [[ -c /dev/tty ]]
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    [[ "$FORCE" == "true" ]] && { [[ "$default" == "y" ]]; return $?; }
    
    if ! can_prompt; then
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

# ============================================================================
# Setup Function
# ============================================================================

setup_ssh() {
    info "SSH Key Setup..."

    # Ensure .ssh directory exists with correct permissions
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would ensure $SSH_DIR exists with mode 700"
    else
        mkdir -p "$SSH_DIR" || { err "Failed to create $SSH_DIR"; return 1; }
        chmod 700 "$SSH_DIR"
    fi

    # Check for existing key
    if [[ -f "$SSH_KEY" ]]; then
        success "SSH key already exists at $SSH_KEY"
        
        if [[ "$FORCE" == "true" ]]; then
            echo "  (force mode: keeping existing key)"
            return 0
        fi
        
        if ! can_prompt; then
            echo "  (no terminal: keeping existing key)"
            return 0
        fi
        
        echo ""
        if ! confirm "Generate a new key? This will overwrite the existing one." "n"; then
            echo "  Keeping existing key."
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would generate SSH key for $EMAIL"
        echo "[dry-run] Would add key to ssh-agent"
        echo "[dry-run] Would create SSH config if needed"
        return 0
    fi

    # Generate SSH key
    echo ""
    info "Generating SSH key for $EMAIL..."
    
    if can_prompt; then
        ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" </dev/tty || {
            err "SSH key generation failed"
            return 1
        }
    else
        # Non-interactive: generate with empty passphrase
        ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" -N "" || {
            err "SSH key generation failed"
            return 1
        }
    fi

    # Start ssh-agent and add key
    info "Adding key to ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null 2>&1 || true
    
    # Try with Keychain first (macOS), fall back to regular add
    if ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null; then
        echo "  Added with Keychain integration"
    elif ssh-add "$SSH_KEY" 2>/dev/null; then
        echo "  Added to ssh-agent"
    else
        warn "Could not add key to ssh-agent (may need passphrase)"
    fi

    # Create/update SSH config for Keychain
    SSH_CONFIG="$SSH_DIR/config"
    if [[ ! -f "$SSH_CONFIG" ]]; then
        cat > "$SSH_CONFIG" << 'EOF'
# Default settings for all hosts
Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
        chmod 600 "$SSH_CONFIG"
        echo "  Created SSH config with macOS Keychain integration"
    elif ! grep -q "AddKeysToAgent" "$SSH_CONFIG"; then
        cat >> "$SSH_CONFIG" << 'EOF'

# Added by ssh.sh
Host *
    AddKeysToAgent yes
    UseKeychain yes
EOF
        echo "  Updated SSH config with Keychain integration"
    else
        echo "  SSH config already configured"
    fi

    # Set correct permissions
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_KEY.pub"

    success "SSH key generated!"

    # Copy to clipboard if possible
    if command -v pbcopy &>/dev/null; then
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
    else
        echo ""
        echo "Your public key:"
        cat "$SSH_KEY.pub"
        echo ""
        echo "Add it to GitHub: https://github.com/settings/keys"
        echo ""
    fi

    # Wait for user to add key to GitHub (interactive only)
    if can_prompt && [[ "$FORCE" != "true" ]]; then
        echo -n "Press Enter after adding the key to GitHub..."
        read </dev/tty

        echo ""
        info "Testing GitHub SSH connection..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            success "SSH working! GitHub authentication verified."
        else
            warn "Could not verify SSH connection (this is sometimes normal)"
            echo "  You may need to wait a moment and try: ssh -T git@github.com"
        fi
    fi

    return 0
}

# ============================================================================
# Entry Point
# ============================================================================

# Detect if being sourced
_is_being_sourced() {
    [[ -n "$_DOTFILES_SOURCING" ]] && return 0
    [[ "$ZSH_EVAL_CONTEXT" == *:file:* ]] && return 0
    [[ -n "${BASH_SOURCE[0]}" ]] && [[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0
    return 1
}

if _is_being_sourced; then
    setup_ssh
else
    setup_ssh
    exit $?
fi
