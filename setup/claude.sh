#!/usr/bin/env zsh

# claude.sh — Set up Claude Code configuration symlinks
# Run standalone: ~/.dotfiles/setup/claude.sh [options]
# Or sourced by start.sh during bootstrap
#
# Symlinks these files to ~/.claude/:
#   - CLAUDE.md (global agent instructions)
#   - settings.json (permissions, model preferences, settings)
#   - commands/ (custom slash commands)
#   - skills/ (custom skills)
#   - plans/ (agent plan files)
#   - agents/ (custom agents)
#   - plugins/installed_plugins.json (plugin manifest)
#   - plugins/known_marketplaces.json (marketplace registry)
#   - LEDGER.jsonl (cross-session memory)
#
# Also syncs plugins: reinstalls any plugins listed in the manifest
# that are missing from the local cache (for cross-machine sync).
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
                echo "claude.sh — Set up Claude Code configuration"
                echo ""
                echo "Usage: ./claude.sh [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Skip confirmation prompts"
                echo "  --dry-run, -n  Show what would be done"
                echo ""
                echo "This script symlinks Claude Code configuration files:"
                echo "  - CLAUDE.md       (global agent instructions)"
                echo "  - settings.json   (permissions, model, settings)"
                echo "  - commands/       (custom slash commands)"
                echo "  - skills/         (custom skills)"
                echo "  - plans/          (agent plan files)"
                echo "  - agents/         (custom agents)"
                echo "  - plugins/*.json  (plugin & marketplace manifests)"
                echo "  - LEDGER.jsonl    (cross-session memory)"
                echo ""
                echo "Also syncs plugins from manifest on new machines."
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
    symlink_dir() {
        local src="$1" dst="$2"
        [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]] && { echo "  Already linked: $(basename "$dst")"; return 0; }
        [[ -d "$dst" ]] && [[ -n "$(ls -A "$dst" 2>/dev/null)" ]] && mv "$dst" "$dst.backup.$(date +%Y%m%d%H%M%S)"
        [[ -d "$dst" ]] && rm -rf "$dst"
        ln -sf "$src" "$dst" && echo "  Linked: $(basename "$dst") → $src"
    }
fi

# ============================================================================
# Configuration
# ============================================================================

CLAUDE_CONFIG_SRC="$DOTFILES/claude"
CLAUDE_HOME="$HOME/.claude"

# ============================================================================
# Plugin Sync Function
# ============================================================================

sync_claude_plugins() {
    local manifest="$CLAUDE_HOME/plugins/installed_plugins.json"
    [[ ! -f "$manifest" ]] && return 0

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        echo "  jq not installed, skipping plugin sync"
        return 0
    fi

    echo ""
    echo "  Syncing plugins from manifest..."

    local plugins
    plugins=$(jq -r '.plugins | keys[]' "$manifest" 2>/dev/null)
    [[ -z "$plugins" ]] && { echo "  No plugins in manifest"; return 0; }

    local installed=0 failed=0

    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && continue

        # Extract plugin name and marketplace from "name@marketplace" format
        local name="${plugin%@*}"
        local marketplace="${plugin#*@}"

        # Check if plugin cache exists
        local cache_path="$CLAUDE_HOME/plugins/cache/$marketplace/$name"
        if [[ -d "$cache_path" ]]; then
            continue  # Already installed
        fi

        echo "  Installing: $plugin"
        if [[ "$DOTFILES_DRY_RUN" == "true" ]]; then
            echo "    (dry-run) would install $plugin"
            ((installed++))
        elif claude plugin install "$plugin" &>/dev/null; then
            ((installed++))
        else
            echo "    Failed to install $plugin"
            ((failed++))
        fi
    done <<< "$plugins"

    if [[ $installed -gt 0 ]] || [[ $failed -gt 0 ]]; then
        echo "  Plugins: $installed installed, $failed failed"
    else
        echo "  All plugins already installed"
    fi
}

# ============================================================================
# Setup Function
# ============================================================================

setup_claude() {
    info "Claude Code configuration..."

    # Check if Claude Code is installed
    if ! command -v claude &>/dev/null; then
        echo "  Claude Code CLI not installed."
        echo "  Install via: npm install -g @anthropic-ai/claude-code"
        echo "  Skipping."
        return 0
    fi

    # Check if config exists in dotfiles
    if [[ ! -d "$CLAUDE_CONFIG_SRC" ]]; then
        warn "No Claude config found at $CLAUDE_CONFIG_SRC"
        return 0
    fi

    # Count available config files
    local config_items=0
    [[ -f "$CLAUDE_CONFIG_SRC/CLAUDE.md" ]] && ((config_items++))
    [[ -f "$CLAUDE_CONFIG_SRC/settings.json" ]] && ((config_items++))
    [[ -d "$CLAUDE_CONFIG_SRC/commands" ]] && ((config_items++))
    [[ -d "$CLAUDE_CONFIG_SRC/skills" ]] && ((config_items++))
    [[ -d "$CLAUDE_CONFIG_SRC/plans" ]] && ((config_items++))
    [[ -d "$CLAUDE_CONFIG_SRC/agents" ]] && ((config_items++))
    [[ -d "$CLAUDE_CONFIG_SRC/plugins" ]] && ((config_items++))
    [[ -f "$CLAUDE_CONFIG_SRC/LEDGER.jsonl" ]] && ((config_items++))

    if [[ $config_items -eq 0 ]]; then
        warn "No config files found in $CLAUDE_CONFIG_SRC"
        return 0
    fi

    echo ""
    echo "Claude Code is installed and dotfiles config is available ($config_items items)."
    echo "This will symlink to ~/.claude/:"
    [[ -f "$CLAUDE_CONFIG_SRC/CLAUDE.md" ]] && echo "  - CLAUDE.md (global agent instructions)"
    [[ -f "$CLAUDE_CONFIG_SRC/settings.json" ]] && echo "  - settings.json (permissions, model preferences)"
    [[ -d "$CLAUDE_CONFIG_SRC/commands" ]] && echo "  - commands/ (custom slash commands)"
    [[ -d "$CLAUDE_CONFIG_SRC/skills" ]] && echo "  - skills/ (custom skills)"
    [[ -d "$CLAUDE_CONFIG_SRC/plans" ]] && echo "  - plans/ (agent plan files)"
    [[ -d "$CLAUDE_CONFIG_SRC/agents" ]] && echo "  - agents/ (custom agents)"
    [[ -d "$CLAUDE_CONFIG_SRC/plugins" ]] && echo "  - plugins/*.json (plugin manifests + auto-sync)"
    [[ -f "$CLAUDE_CONFIG_SRC/LEDGER.jsonl" ]] && echo "  - LEDGER.jsonl (cross-session memory)"
    echo ""

    if ! confirm "Apply Claude Code settings?" "y"; then
        echo "  Skipped. Run later: ~/.dotfiles/setup/claude.sh"
        return 0
    fi

    echo ""

    local failed=0

    # Create ~/.claude directory if needed
    if [[ "$DOTFILES_DRY_RUN" != "true" ]]; then
        mkdir -p "$CLAUDE_HOME" || { warn "Failed to create $CLAUDE_HOME"; ((failed++)); }
    fi

    # Symlink CLAUDE.md
    if [[ -f "$CLAUDE_CONFIG_SRC/CLAUDE.md" ]]; then
        symlink "$CLAUDE_CONFIG_SRC/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" || ((failed++))
    fi

    # Symlink settings.json
    if [[ -f "$CLAUDE_CONFIG_SRC/settings.json" ]]; then
        symlink "$CLAUDE_CONFIG_SRC/settings.json" "$CLAUDE_HOME/settings.json" || ((failed++))
    fi

    # Symlink commands/ directory
    if [[ -d "$CLAUDE_CONFIG_SRC/commands" ]]; then
        symlink_dir "$CLAUDE_CONFIG_SRC/commands" "$CLAUDE_HOME/commands" || ((failed++))
    fi

    # Symlink skills/ directory
    if [[ -d "$CLAUDE_CONFIG_SRC/skills" ]]; then
        symlink_dir "$CLAUDE_CONFIG_SRC/skills" "$CLAUDE_HOME/skills" || ((failed++))
    fi

    # Symlink plans/ directory
    if [[ -d "$CLAUDE_CONFIG_SRC/plans" ]]; then
        symlink_dir "$CLAUDE_CONFIG_SRC/plans" "$CLAUDE_HOME/plans" || ((failed++))
    fi

    # Symlink agents/ directory
    if [[ -d "$CLAUDE_CONFIG_SRC/agents" ]]; then
        symlink_dir "$CLAUDE_CONFIG_SRC/agents" "$CLAUDE_HOME/agents" || ((failed++))
    fi

    # Symlink LEDGER.jsonl (cross-session memory)
    if [[ -f "$CLAUDE_CONFIG_SRC/LEDGER.jsonl" ]]; then
        symlink "$CLAUDE_CONFIG_SRC/LEDGER.jsonl" "$CLAUDE_HOME/LEDGER.jsonl" || ((failed++))
    fi

    # Symlink plugin manifests (not cache - it's regenerable)
    if [[ -d "$CLAUDE_CONFIG_SRC/plugins" ]]; then
        mkdir -p "$CLAUDE_HOME/plugins"
        if [[ -f "$CLAUDE_CONFIG_SRC/plugins/installed_plugins.json" ]]; then
            symlink "$CLAUDE_CONFIG_SRC/plugins/installed_plugins.json" "$CLAUDE_HOME/plugins/installed_plugins.json" || ((failed++))
        fi
        if [[ -f "$CLAUDE_CONFIG_SRC/plugins/known_marketplaces.json" ]]; then
            symlink "$CLAUDE_CONFIG_SRC/plugins/known_marketplaces.json" "$CLAUDE_HOME/plugins/known_marketplaces.json" || ((failed++))
        fi
        # Sync plugins from manifest
        sync_claude_plugins
    fi

    if [[ $failed -gt 0 ]]; then
        warn "Claude Code configuration completed with $failed error(s)"
    else
        success "Claude Code configuration applied"
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
    setup_claude
else
    setup_claude
    exit $?
fi
