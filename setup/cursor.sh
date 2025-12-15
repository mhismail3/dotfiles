#!/usr/bin/env zsh

# cursor.sh — Set up Cursor IDE configuration symlinks
# Run standalone: ~/.dotfiles/setup/cursor.sh [options]
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
                echo "cursor.sh — Set up Cursor IDE configuration"
                echo ""
                echo "Usage: ./cursor.sh [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Skip confirmation prompts"
                echo "  --dry-run, -n  Show what would be done"
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
    # Minimal fallback if _lib.sh not found
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
    symlink() {
        local src="$1" dst="$2"
        [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]] && { echo "  Already linked: $dst"; return 0; }
        [[ -e "$dst" ]] && mv "$dst" "$dst.backup.$(date +%Y%m%d%H%M%S)"
        ln -sf "$src" "$dst" && echo "  Linked: $dst → $src"
    }
fi

# ============================================================================
# Configuration
# ============================================================================

CURSOR_CONFIG_SRC="$DOTFILES/cursor"
CURSOR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
CURSOR_DATA_DIR="$HOME/.cursor"
CURSOR_EXTENSIONS_DIR="$CURSOR_DATA_DIR/extensions"

# ============================================================================
# Setup Function
# ============================================================================

setup_cursor() {
    info "Cursor configuration..."

    # Check if Cursor is installed
    if [[ ! -d "/Applications/Cursor.app" ]] && [[ ! -d "$HOME/Applications/Cursor.app" ]]; then
        echo "  Cursor not installed. Skipping."
        return 0
    fi

    # Check if config exists in dotfiles
    if [[ ! -d "$CURSOR_CONFIG_SRC" ]]; then
        warn "No Cursor config found at $CURSOR_CONFIG_SRC"
        return 0
    fi

    # Count available config files
    local config_files=0
    [[ -f "$CURSOR_CONFIG_SRC/settings.json" ]] && ((config_files++))
    [[ -f "$CURSOR_CONFIG_SRC/keybindings.json" ]] && ((config_files++))
    [[ -f "$CURSOR_CONFIG_SRC/mcp.json" ]] && ((config_files++))
    [[ -f "$CURSOR_CONFIG_SRC/extensions.json" ]] && ((config_files++))
    
    if [[ $config_files -eq 0 ]]; then
        warn "No config files found in $CURSOR_CONFIG_SRC"
        return 0
    fi

    echo ""
    echo "Cursor is installed and dotfiles config is available ($config_files files)."
    echo "This will symlink to:"
    echo "  - ~/Library/Application Support/Cursor/User/"
    echo "  - ~/.cursor/"
    echo ""

    if ! confirm "Apply Cursor settings?" "y"; then
        echo "  Skipped. Run later: ~/.dotfiles/setup/cursor.sh"
        return 0
    fi

    echo ""
    
    local failed=0

    # Create directories if needed
    if [[ "$DOTFILES_DRY_RUN" != "true" ]]; then
        mkdir -p "$CURSOR_USER_DIR" || { warn "Failed to create $CURSOR_USER_DIR"; ((failed++)); }
        mkdir -p "$CURSOR_EXTENSIONS_DIR" || { warn "Failed to create $CURSOR_EXTENSIONS_DIR"; ((failed++)); }
    fi

    # Symlink each config file
    [[ -f "$CURSOR_CONFIG_SRC/settings.json" ]] && \
        { symlink "$CURSOR_CONFIG_SRC/settings.json" "$CURSOR_USER_DIR/settings.json" || ((failed++)); }
    
    [[ -f "$CURSOR_CONFIG_SRC/keybindings.json" ]] && \
        { symlink "$CURSOR_CONFIG_SRC/keybindings.json" "$CURSOR_USER_DIR/keybindings.json" || ((failed++)); }

    [[ -f "$CURSOR_CONFIG_SRC/mcp.json" ]] && \
        { symlink "$CURSOR_CONFIG_SRC/mcp.json" "$CURSOR_DATA_DIR/mcp.json" || ((failed++)); }

    [[ -f "$CURSOR_CONFIG_SRC/extensions.json" ]] && \
        { symlink "$CURSOR_CONFIG_SRC/extensions.json" "$CURSOR_EXTENSIONS_DIR/extensions.json" || ((failed++)); }

    if [[ $failed -gt 0 ]]; then
        warn "Cursor configuration completed with $failed error(s)"
    else
        success "Cursor configuration applied"
    fi
    
    return $failed
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
    setup_cursor
else
    setup_cursor
    exit $?
fi
