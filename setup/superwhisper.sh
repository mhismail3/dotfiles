#!/usr/bin/env zsh

# superwhisper.sh — Set up SuperWhisper configuration symlinks
# Run standalone: ~/.dotfiles/setup/superwhisper.sh [options]
# Or sourced by start.sh during bootstrap
#
# Options:
#   --force, -f    Skip confirmation prompts
#   --dry-run, -n  Show what would be done
#   --help, -h     Show help

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
                echo "superwhisper.sh — Set up SuperWhisper configuration"
                echo ""
                echo "Usage: ./superwhisper.sh [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Skip confirmation prompts"
                echo "  --dry-run, -n  Show what would be done"
                echo ""
                echo "This script symlinks modes/ and settings/ from your dotfiles"
                echo "to SuperWhisper's data folder. Recordings and models stay local."
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
    symlink_dir() {
        local src="$1" dst="$2" name="$(basename "$src")"
        [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]] && { echo "  Already linked: $name"; return 0; }
        [[ -d "$dst" ]] && [[ ! -L "$dst" ]] && mv "$dst" "$dst.backup.$(date +%Y%m%d%H%M%S)"
        [[ -L "$dst" ]] && rm "$dst"
        ln -s "$src" "$dst" && echo "  Linked: $name → $src"
    }
fi

# ============================================================================
# Configuration
# ============================================================================

SUPERWHISPER_CONFIG_SRC="$DOTFILES/superwhisper"

# ============================================================================
# Helper Functions
# ============================================================================

detect_superwhisper_folder() {
    # SuperWhisper stores appFolderDirectory in its preferences
    local sw_folder
    sw_folder=$(defaults read com.superduper.superwhisper appFolderDirectory 2>/dev/null || echo "")
    
    if [[ -n "$sw_folder" ]]; then
        echo "$sw_folder/superwhisper"
    else
        # Default location
        echo "$HOME/Downloads/superwhisper"
    fi
}

# ============================================================================
# Setup Function
# ============================================================================

setup_superwhisper() {
    info "SuperWhisper configuration..."

    # Check if SuperWhisper is installed
    if [[ ! -d "/Applications/superwhisper.app" ]] && [[ ! -d "$HOME/Applications/superwhisper.app" ]]; then
        echo "  SuperWhisper not installed. Skipping."
        return 0
    fi

    # Check if config exists in dotfiles
    if [[ ! -d "$SUPERWHISPER_CONFIG_SRC" ]]; then
        warn "No SuperWhisper config found at $SUPERWHISPER_CONFIG_SRC"
        return 0
    fi

    # Check for modes and settings directories
    local has_modes=false has_settings=false
    [[ -d "$SUPERWHISPER_CONFIG_SRC/modes" ]] && has_modes=true
    [[ -d "$SUPERWHISPER_CONFIG_SRC/settings" ]] && has_settings=true
    
    if [[ "$has_modes" == "false" ]] && [[ "$has_settings" == "false" ]]; then
        warn "No modes/ or settings/ directories in $SUPERWHISPER_CONFIG_SRC"
        return 0
    fi

    # Detect SuperWhisper's data folder
    local app_folder
    app_folder="$(detect_superwhisper_folder)"

    echo ""
    echo "SuperWhisper is installed and dotfiles config is available."
    echo "This will symlink modes/ and settings/ to your dotfiles."
    echo "(Recordings and models stay machine-local)"
    echo ""
    echo "SuperWhisper data folder: $app_folder"
    echo ""

    if ! confirm "Apply SuperWhisper settings?" "y"; then
        echo "  Skipped. Run later: ~/.dotfiles/setup/superwhisper.sh"
        return 0
    fi

    echo ""

    local failed=0

    # Create app folder structure if needed
    if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would create: $app_folder/models"
        echo "  [dry-run] Would create: $app_folder/recordings"
    else
        mkdir -p "$app_folder/models" || { warn "Failed to create models/"; ((failed++)); }
        mkdir -p "$app_folder/recordings" || { warn "Failed to create recordings/"; ((failed++)); }
    fi

    # Symlink modes and settings
    if [[ "$has_modes" == "true" ]]; then
        symlink_dir "$SUPERWHISPER_CONFIG_SRC/modes" "$app_folder/modes" || ((failed++))
    fi
    
    if [[ "$has_settings" == "true" ]]; then
        symlink_dir "$SUPERWHISPER_CONFIG_SRC/settings" "$app_folder/settings" || ((failed++))
    fi

    if [[ $failed -gt 0 ]]; then
        warn "SuperWhisper configuration completed with $failed error(s)"
    else
        success "SuperWhisper configuration applied"
        echo ""
        echo "  Config synced from: $SUPERWHISPER_CONFIG_SRC"
        echo "  Data folder:        $app_folder"
        echo ""
        echo "  modes/    → symlinked (git tracked)"
        echo "  settings/ → symlinked (git tracked)"
        echo "  models/   → local (not in git)"
        echo "  recordings/ → local (not in git)"
    fi
    
    return $failed
}

# ============================================================================
# Entry Point
# ============================================================================

# Detect if being sourced: check ZSH_EVAL_CONTEXT or if _DOTFILES_SOURCING is set
_is_being_sourced() {
    # If parent script set this flag, we're being sourced
    [[ -n "$_DOTFILES_SOURCING" ]] && return 0
    # ZSH_EVAL_CONTEXT contains "file" when sourced
    [[ "$ZSH_EVAL_CONTEXT" == *:file:* ]] && return 0
    # Fallback for bash
    [[ -n "${BASH_SOURCE[0]}" ]] && [[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0
    return 1
}

if _is_being_sourced; then
    # Sourced by another script - just run the function
    setup_superwhisper
else
    # Executed directly - run and exit
    setup_superwhisper
    exit $?
fi
