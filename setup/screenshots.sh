#!/usr/bin/env zsh

# screenshots.sh — Configure macOS screenshot save location
# Run standalone: ~/.dotfiles/setup/screenshots.sh [options] [path]
#
# Options:
#   --show, -s     Show current screenshot location
#   --reset, -r    Reset to default (Desktop)
#   --force, -f    Skip confirmation prompts
#   --dry-run, -n  Show what would be done
#   --help, -h     Show help
#
# Arguments:
#   path           Custom screenshot save location (optional)

# ============================================================================
# Initialization
# ============================================================================

# Defaults
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
FORCE=false
DRY_RUN=false
ACTION="prompt"  # prompt, set, show, reset

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show|-s)
            ACTION="show"
            shift
            ;;
        --reset|-r)
            ACTION="reset"
            shift
            ;;
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
screenshots.sh — Configure macOS screenshot save location

USAGE:
  ./screenshots.sh [OPTIONS] [PATH]

OPTIONS:
  --show, -s     Show current screenshot location
  --reset, -r    Reset to default (Desktop)
  --force, -f    Skip confirmation prompts
  --dry-run, -n  Show what would be done
  --help, -h     Show this help

ARGUMENTS:
  PATH           Custom screenshot save location (optional)
                 If omitted, prompts interactively

EXAMPLES:
  ./screenshots.sh                              # Interactive prompt
  ./screenshots.sh ~/Dropbox/Screenshots        # Set to custom path
  ./screenshots.sh --show                       # Show current setting
  ./screenshots.sh --reset                      # Reset to Desktop

ENVIRONMENT VARIABLES:
  SCREENSHOT_DIR  Default path (default: ~/Pictures/Screenshots)

EOF
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            # Path argument
            SCREENSHOT_DIR="$1"
            ACTION="set"
            shift
            ;;
    esac
done

# Read from environment if set
FORCE="${DOTFILES_FORCE:-$FORCE}"
DRY_RUN="${DOTFILES_DRY_RUN:-$DRY_RUN}"

# ============================================================================
# Helper Functions
# ============================================================================

info() { printf "\n\033[1;34m→ %s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
err() { printf "\033[1;31m✗ %s\033[0m\n" "$1" >&2; }

can_prompt() {
    [[ -t 0 ]] || [[ -c /dev/tty ]]
}

expand_path() {
    local path="$1"
    # Expand ~ to $HOME
    if [[ "$path" == "~"* ]]; then
        path="${path/#\~/$HOME}"
    fi
    echo "$path"
}

read_screenshot_location() {
    local location
    location="$(defaults read com.apple.screencapture location 2>/dev/null || true)"
    
    if [[ -z "$location" ]]; then
        echo "Desktop (default)"
    else
        echo "$location"
    fi
}

# ============================================================================
# Actions
# ============================================================================

show_current_location() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 Screenshot Settings"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Current location: $(read_screenshot_location)"
    echo ""
}

reset_screenshot_location() {
    info "Resetting screenshot location..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would delete com.apple.screencapture location"
        echo "[dry-run] Would restart SystemUIServer"
        return 0
    fi
    
    defaults delete com.apple.screencapture location 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true
    
    success "Screenshot location reset to default (Desktop)"
}

configure_screenshot_location() {
    local target="$1"
    target="$(expand_path "$target")"
    
    info "Setting screenshot location..."
    echo "  Target: $target"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would create directory: $target"
        echo "[dry-run] Would set com.apple.screencapture location"
        echo "[dry-run] Would restart SystemUIServer"
        return 0
    fi
    
    # Create directory if it doesn't exist
    if [[ ! -d "$target" ]]; then
        mkdir -p "$target" || {
            err "Failed to create directory: $target"
            return 1
        }
        echo "  Created directory"
    fi
    
    # Verify directory is writable
    if [[ ! -w "$target" ]]; then
        err "Directory is not writable: $target"
        return 1
    fi
    
    # Set the screenshot location
    defaults write com.apple.screencapture location -string "$target" || {
        err "Failed to set screenshot location"
        return 1
    }
    
    # Apply immediately by restarting SystemUIServer
    killall SystemUIServer 2>/dev/null || true
    
    success "Screenshot location set to: $target"
}

prompt_for_path() {
    local current
    current="$(read_screenshot_location)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 Screenshot Location Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Current location: $current"
    echo "Default:          $SCREENSHOT_DIR"
    echo ""
    
    if [[ "$FORCE" == "true" ]] || ! can_prompt; then
        echo "Using default: $SCREENSHOT_DIR"
        configure_screenshot_location "$SCREENSHOT_DIR"
        return $?
    fi
    
    echo -n "Enter new location (or press Enter for default): "
    read -r user_path </dev/tty 2>/dev/null || user_path=""
    echo ""
    
    if [[ -z "$user_path" ]]; then
        configure_screenshot_location "$SCREENSHOT_DIR"
    else
        configure_screenshot_location "$user_path"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    case "$ACTION" in
        show)
            show_current_location
            ;;
        reset)
            reset_screenshot_location
            ;;
        set)
            configure_screenshot_location "$SCREENSHOT_DIR"
            ;;
        prompt)
            prompt_for_path
            ;;
    esac
}

# Run if executed directly
if [[ "${(%):-%N}" == "$0" ]] || [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main
    exit $?
fi
