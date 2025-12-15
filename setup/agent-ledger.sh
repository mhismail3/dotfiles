#!/usr/bin/env zsh

# agent-ledger.sh — Set up agent ledger symlink for cross-project memory
# Run standalone: ~/.dotfiles/setup/agent-ledger.sh [options]
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
                echo "agent-ledger.sh — Set up agent ledger for cross-project memory"
                echo ""
                echo "Usage: ./agent-ledger.sh [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Skip confirmation prompts"
                echo "  --dry-run, -n  Show what would be done"
                echo ""
                echo "This creates a symlink from ~/.agent-ledger to ~/.dotfiles/agent-ledger"
                echo "so agents can access the shared memory ledger from any project."
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

LEDGER_SRC="$DOTFILES/agent-ledger"
LEDGER_DST="$HOME/.agent-ledger"

# ============================================================================
# Setup Function
# ============================================================================

setup_agent_ledger() {
    info "Agent ledger configuration..."

    # Check if ledger directory exists in dotfiles
    if [[ ! -d "$LEDGER_SRC" ]]; then
        warn "Agent ledger not found at $LEDGER_SRC"
        echo "  Run from dotfiles directory or ensure agent-ledger/ exists."
        return 1
    fi

    # Check for required files
    local required_files=0
    [[ -f "$LEDGER_SRC/AGENTS.md" ]] && ((required_files++))
    [[ -f "$LEDGER_SRC/ledger.jsonl" ]] && ((required_files++))

    if [[ $required_files -lt 2 ]]; then
        warn "Agent ledger is missing required files (AGENTS.md, ledger.jsonl)"
        return 1
    fi

    echo ""
    echo "Agent ledger directory found with required files."
    echo "This will create a symlink for global access:"
    echo "  ~/.agent-ledger → $LEDGER_SRC"
    echo ""

    if ! confirm "Set up agent ledger?" "y"; then
        echo "  Skipped. Run later: ~/.dotfiles/setup/agent-ledger.sh"
        return 0
    fi

    echo ""

    local failed=0

    # Ensure sessions directory exists
    if [[ "$DOTFILES_DRY_RUN" != "true" ]]; then
        mkdir -p "$LEDGER_SRC/sessions" || { warn "Failed to create sessions directory"; ((failed++)); }
    else
        echo "  [dry-run] Would ensure $LEDGER_SRC/sessions exists"
    fi

    # Create symlink
    symlink "$LEDGER_SRC" "$LEDGER_DST" || ((failed++))

    if [[ $failed -gt 0 ]]; then
        warn "Agent ledger setup completed with $failed error(s)"
    else
        success "Agent ledger configured"
        echo ""
        echo "  Ledger location: $LEDGER_SRC"
        echo "  Global symlink:  $LEDGER_DST"
        echo ""
        echo "  Agents can now access ~/.agent-ledger/ from any project."
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
    setup_agent_ledger
else
    setup_agent_ledger
    exit $?
fi

