#!/usr/bin/env zsh

# _lib.sh — Shared helper functions for dotfiles setup scripts
# Source this file at the top of each setup script:
#   source "${0:A:h}/_lib.sh"

# Prevent double-sourcing
[[ -n "$_DOTFILES_LIB_LOADED" ]] && return 0
export _DOTFILES_LIB_LOADED=1

# ============================================================================
# Configuration
# ============================================================================

export DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# Detect Homebrew prefix (Apple Silicon vs Intel)
if [[ $(uname -m) == "arm64" ]]; then
    export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
else
    export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/usr/local}"
fi

# Global flags (can be set before sourcing)
export DOTFILES_FORCE="${DOTFILES_FORCE:-false}"      # Skip all prompts, use defaults
export DOTFILES_DRY_RUN="${DOTFILES_DRY_RUN:-false}"  # Show what would happen without doing it
export DOTFILES_VERBOSE="${DOTFILES_VERBOSE:-false}"  # Extra output

# ============================================================================
# Output Helpers
# ============================================================================

info() {
    printf "\n\033[1;34m→ %s\033[0m\n" "$1"
}

success() {
    printf "\033[1;32m✓ %s\033[0m\n" "$1"
}

warn() {
    printf "\033[1;33m⚠ %s\033[0m\n" "$1"
}

# Non-fatal error (continues execution)
err() {
    printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2
}

# Fatal error (exits)
die() {
    printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2
    exit 1
}

debug() {
    [[ "$DOTFILES_VERBOSE" == "true" ]] && printf "\033[0;37m  [debug] %s\033[0m\n" "$1"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        die "This script is designed for macOS only."
    fi
}

# Warn if running as root (usually not desired for dotfiles)
check_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        warn "Running as root is not recommended for dotfiles setup."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    fi
}

# Check network connectivity
check_network() {
    if ! ping -c 1 -W 2 github.com &>/dev/null; then
        warn "No network connectivity detected (could not reach github.com)"
        return 1
    fi
    return 0
}

# ============================================================================
# Symlink Helpers
# ============================================================================

# Ensure parent directory exists
ensure_parent_dir() {
    local file_path="$1"
    local parent_dir
    parent_dir="$(dirname "$file_path")"
    
    if [[ ! -d "$parent_dir" ]]; then
        if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would create directory: $parent_dir"
        else
            mkdir -p "$parent_dir" || {
                err "Failed to create directory: $parent_dir"
                return 1
            }
            debug "Created directory: $parent_dir"
        fi
    fi
    return 0
}

# Safely create a symlink (idempotent, backs up existing files)
# Usage: symlink "/source/path" "/destination/path"
# Returns: 0 on success, 1 on failure
symlink() {
    local src="$1"
    local dst="$2"
    
    # Validate source exists
    if [[ ! -f "$src" ]] && [[ ! -d "$src" ]]; then
        warn "Source not found: $src"
        return 1
    fi
    
    # Ensure parent directory exists
    ensure_parent_dir "$dst" || return 1
    
    # Check if already correctly linked
    if [[ -L "$dst" ]]; then
        local current_target
        current_target="$(readlink "$dst")"
        if [[ "$current_target" == "$src" ]]; then
            echo "  Already linked: $dst"
            return 0
        else
            # Symlink exists but points elsewhere
            if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
                echo "  [dry-run] Would update symlink: $dst"
                echo "            Old target: $current_target"
                echo "            New target: $src"
            else
                rm "$dst"
                debug "Removed old symlink: $dst -> $current_target"
            fi
        fi
    elif [[ -e "$dst" ]]; then
        # Real file/directory exists - back it up
        local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
        if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would backup: $dst → $backup"
        else
            mv "$dst" "$backup" || {
                err "Failed to backup: $dst"
                return 1
            }
            echo "  Backed up: $dst → $backup"
        fi
    fi
    
    # Create the symlink
    if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would link: $dst → $src"
    else
        ln -s "$src" "$dst" || {
            err "Failed to create symlink: $dst → $src"
            return 1
        }
        echo "  Linked: $dst → $src"
    fi
    
    return 0
}

# Symlink for directories (handles empty vs non-empty backup logic)
# Usage: symlink_dir "/source/dir" "/destination/dir"
symlink_dir() {
    local src="$1"
    local dst="$2"
    local name="$(basename "$src")"
    
    # Validate source exists
    if [[ ! -d "$src" ]]; then
        warn "Source directory not found: $src"
        return 1
    fi
    
    # Ensure parent directory exists
    ensure_parent_dir "$dst" || return 1
    
    # Check if already correctly linked
    if [[ -L "$dst" ]]; then
        local current_target
        current_target="$(readlink "$dst")"
        if [[ "$current_target" == "$src" ]]; then
            echo "  Already linked: $name"
            return 0
        else
            if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
                echo "  [dry-run] Would update symlink: $name"
            else
                rm "$dst"
            fi
        fi
    elif [[ -d "$dst" ]]; then
        # Real directory exists
        if [[ -n "$(ls -A "$dst" 2>/dev/null)" ]]; then
            # Directory has content - back it up
            local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
            if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
                echo "  [dry-run] Would backup: $name → $backup"
            else
                mv "$dst" "$backup" || {
                    err "Failed to backup: $dst"
                    return 1
                }
                echo "  Backed up: $name → $backup"
            fi
        else
            # Empty directory - just remove it
            if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
                echo "  [dry-run] Would remove empty: $name"
            else
                rm -rf "$dst"
            fi
        fi
    fi
    
    # Create the symlink
    if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would link: $name → $src"
    else
        ln -s "$src" "$dst" || {
            err "Failed to create symlink: $dst → $src"
            return 1
        }
        echo "  Linked: $name → $src"
    fi
    
    return 0
}

# ============================================================================
# Script Mode Detection
# ============================================================================

# Check if script is being sourced or executed directly
# Usage: if is_sourced; then ... fi
is_sourced() {
    [[ "${(%):-%N}" != "$0" ]] 2>/dev/null || [[ "${BASH_SOURCE[0]}" != "$0" ]] 2>/dev/null
}

# ============================================================================
# Interactive Helpers
# ============================================================================

# Check if we can read from terminal
can_prompt() {
    [[ -t 0 ]] || [[ -c /dev/tty ]]
}

# Prompt for yes/no with default
# Usage: if confirm "Apply settings?" "y"; then ... fi
# In DOTFILES_FORCE mode, returns based on default
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local reply
    
    # Force mode: use default without prompting
    if [[ "$DOTFILES_FORCE" == "true" ]]; then
        debug "Force mode: using default '$default' for: $prompt"
        [[ "$default" == "y" ]]
        return $?
    fi
    
    # Check if we can prompt
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
    
    # Try to read from /dev/tty first (works with piped input)
    if [[ -c /dev/tty ]]; then
        read reply </dev/tty 2>/dev/null || reply="$default"
    else
        read reply || reply="$default"
    fi
    
    # Empty reply uses default
    [[ -z "$reply" ]] && reply="$default"
    
    if [[ "$default" == "y" ]]; then
        [[ ! "$reply" =~ ^[Nn]$ ]]
    else
        [[ "$reply" =~ ^[Yy]$ ]]
    fi
}

# Prompt for text input with default
# Usage: result=$(prompt_input "Enter value" "default_value")
prompt_input() {
    local prompt="$1"
    local default="$2"
    local reply
    
    if [[ "$DOTFILES_FORCE" == "true" ]]; then
        echo "$default"
        return 0
    fi
    
    if ! can_prompt; then
        echo "$default"
        return 0
    fi
    
    echo -n "$prompt [$default]: " >&2
    
    if [[ -c /dev/tty ]]; then
        read reply </dev/tty 2>/dev/null || reply=""
    else
        read reply || reply=""
    fi
    
    echo "${reply:-$default}"
}

# ============================================================================
# Application Helpers
# ============================================================================

# Check if an application is installed
# Usage: if app_installed "Cursor"; then ... fi
app_installed() {
    local app_name="$1"
    [[ -d "/Applications/${app_name}.app" ]] || [[ -d "$HOME/Applications/${app_name}.app" ]]
}

# Check if a command is available
# Usage: if cmd_exists "git"; then ... fi
cmd_exists() {
    command -v "$1" &>/dev/null
}

# ============================================================================
# File Operation Helpers
# ============================================================================

# Safely create a directory
# Usage: safe_mkdir "/path/to/dir"
safe_mkdir() {
    local dir="$1"
    
    if [[ -d "$dir" ]]; then
        debug "Directory already exists: $dir"
        return 0
    fi
    
    if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would create directory: $dir"
        return 0
    fi
    
    mkdir -p "$dir" || {
        err "Failed to create directory: $dir"
        return 1
    }
    
    debug "Created directory: $dir"
    return 0
}

# ============================================================================
# Progress Tracking
# ============================================================================

# Track which steps have been completed (for resume capability)
declare -A _COMPLETED_STEPS

mark_complete() {
    local step="$1"
    _COMPLETED_STEPS[$step]=1
}

is_complete() {
    local step="$1"
    [[ -n "${_COMPLETED_STEPS[$step]}" ]]
}
