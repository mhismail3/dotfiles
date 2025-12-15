#!/usr/bin/env zsh

# raycast.sh — Import Raycast configuration
# Run standalone: ~/.dotfiles/setup/raycast.sh [options]
# Or sourced by start.sh during bootstrap
#
# Options:
#   --force, -f    Skip confirmation prompts
#   --dry-run, -n  Show what would be done
#   --help, -h     Show help
#
# Note: Raycast doesn't support symlinks for its config.
# This script helps you import the .rayconfig file manually.

# ============================================================================
# Initialization
# ============================================================================

# Parse arguments if running standalone
if [[ "${(%):-%N}" == "$0" ]] || [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)   export DOTFILES_FORCE=true; shift ;;
            --dry-run|-n) export DOTFILES_DRY_RUN=true; shift ;;
            --help|-h)
                echo "raycast.sh — Import Raycast configuration"
                echo ""
                echo "Usage: ./raycast.sh [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Skip confirmation (auto-open import dialog)"
                echo "  --dry-run, -n  Show what would be done"
                echo ""
                echo "This opens Raycast's import dialog and reveals your config file."
                echo "You'll need to drag the file into Raycast to complete the import."
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
fi

# Source shared library
SCRIPT_DIR="${0:A:h}"
if [[ -f "$SCRIPT_DIR/_lib.sh" ]]; then
    source "$SCRIPT_DIR/_lib.sh"
else
    # Minimal fallback
    DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
    DOTFILES_FORCE="${DOTFILES_FORCE:-false}"
    DOTFILES_DRY_RUN="${DOTFILES_DRY_RUN:-false}"
    info() { printf "\n\033[1;34m→ %s\033[0m\n" "$1"; }
    success() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
    warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
    confirm() {
        [[ "$DOTFILES_FORCE" == "true" ]] && return 0
        echo -n "$1 (Y/n) "; read r </dev/tty 2>/dev/null || r="y"
        [[ ! "$r" =~ ^[Nn]$ ]]
    }
fi

# ============================================================================
# Configuration
# ============================================================================

# Look for config in new location first, then fallback to old location
find_rayconfig() {
    local paths=(
        "$DOTFILES/raycast/Raycast.rayconfig"
        "$DOTFILES/Raycast.rayconfig"
    )
    
    for path in "${paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# ============================================================================
# Setup Function
# ============================================================================

setup_raycast() {
    info "Raycast configuration..."

    # Check if Raycast is installed
    if [[ ! -d "/Applications/Raycast.app" ]] && [[ ! -d "$HOME/Applications/Raycast.app" ]]; then
        echo "  Raycast not installed. Skipping."
        return 0
    fi

    # Find config file
    local rayconfig
    rayconfig="$(find_rayconfig)"
    
    if [[ -z "$rayconfig" ]]; then
        warn "No Raycast config file found"
        echo "  Looked in:"
        echo "    - $DOTFILES/raycast/Raycast.rayconfig"
        echo "    - $DOTFILES/Raycast.rayconfig"
        return 0
    fi

    echo ""
    echo "Raycast is installed and a config file is available."
    echo "Config: $rayconfig"
    echo ""
    echo "Note: Raycast requires manual import (no symlink support)."
    echo "This will open the import dialog and reveal the config file."
    echo ""

    if ! confirm "Open Raycast import?" "y"; then
        echo "  Skipped. Run later: ~/.dotfiles/setup/raycast.sh"
        return 0
    fi

    if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would open: raycast://extensions/raycast/raycast/import-settings-data"
        echo "[dry-run] Would reveal: $rayconfig"
        return 0
    fi

    echo ""

    # Open the import settings command via deeplink
    if ! open "raycast://extensions/raycast/raycast/import-settings-data" 2>/dev/null; then
        warn "Failed to open Raycast import dialog"
        echo "  Try opening Raycast and searching for 'Import Settings'"
    fi

    # Brief pause, then reveal the config file
    sleep 1
    if ! open -R "$rayconfig" 2>/dev/null; then
        warn "Failed to reveal config file in Finder"
        echo "  Config location: $rayconfig"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Raycast Import"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  1. The Raycast import dialog should now be open"
    echo "  2. The config file is highlighted in Finder"
    echo "  3. Drag the file into Raycast OR click 'Select File'"
    echo ""
    
    # Only wait for confirmation if we can prompt and not in force mode
    if [[ -t 0 ]] && [[ "$DOTFILES_FORCE" != "true" ]]; then
        echo -n "Press Enter after importing (or 's' to skip): "
        read reply </dev/tty 2>/dev/null || reply=""

        if [[ "$reply" =~ ^[Ss]$ ]]; then
            echo "  Manual import required later."
        else
            success "Raycast import initiated"
        fi
    else
        echo "  Complete the import manually by dragging the file into Raycast."
        success "Raycast import dialog opened"
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
    setup_raycast
else
    setup_raycast
    exit $?
fi
