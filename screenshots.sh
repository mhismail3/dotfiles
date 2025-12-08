#!/usr/bin/env bash
# screenshots.sh
#
# Purpose:
#   Configure the default screenshot save location on macOS.
#   Intended to be run standalone after SynologyDrive or other sync services are configured.
#
# Usage:
#   ./screenshots.sh                           # Interactive prompt for path
#   ./screenshots.sh /path/to/folder           # Use custom path directly
#   SCREENSHOT_DIR="~/Dropbox/Screenshots" ./screenshots.sh
#
# Notes:
#   - macOS stores screenshot settings in com.apple.screencapture.
#   - The folder must exist and remain available; if the target disappears,
#     macOS falls back to the Desktop.
#   - Restarting SystemUIServer applies changes immediately.

set -euo pipefail

# -------- Configuration knobs --------
# Default screenshot location (override via CLI arg or environment variable)
: "${SCREENSHOT_DIR:="$HOME/Pictures/Screenshots"}"

# -------- Internal helpers --------
log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

expand_path() {
  local path="$1"
  # Expand ~ to $HOME
  if [[ "$path" == "~"* ]]; then
    path="${path/#\~/$HOME}"
  fi
  echo "$path"
}

# -------- User-facing functions --------
configure_screenshot_location() {
  local target="${1:-$SCREENSHOT_DIR}"
  target="$(expand_path "$target")"

  # Create directory if it doesn't exist
  if [[ ! -d "$target" ]]; then
    log "Creating directory: $target"
    mkdir -p "$target"
  fi

  # Set the screenshot location
  defaults write com.apple.screencapture location -string "$target"

  # Apply immediately by restarting SystemUIServer
  killall SystemUIServer >/dev/null 2>&1 || true

  log "✅ Screenshot location set to: $target"
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

reset_screenshot_location() {
  defaults delete com.apple.screencapture location >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
  log "✅ Screenshot location reset to default (Desktop)."
}

show_current_location() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📸 Screenshot Settings"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Current location: $(read_screenshot_location)"
  echo ""
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
  echo ""
  echo -n "Enter new screenshot location (or press Enter for ~/Pictures/Screenshots): "
  read -r user_path </dev/tty || user_path=""
  echo ""
  
  if [[ -z "$user_path" ]]; then
    configure_screenshot_location "$SCREENSHOT_DIR"
  else
    configure_screenshot_location "$user_path"
  fi
}

show_help() {
  cat << 'EOF'
screenshots.sh — Configure macOS screenshot save location

USAGE:
  ./screenshots.sh [OPTIONS] [PATH]

ARGUMENTS:
  PATH                    Custom screenshot save location (optional)
                          If omitted, prompts interactively

OPTIONS:
  --show, -s              Show current screenshot location
  --reset, -r             Reset to default location (Desktop)
  --help, -h              Show this help message

EXAMPLES:
  ./screenshots.sh                              # Interactive prompt
  ./screenshots.sh ~/Dropbox/Screenshots        # Set to custom path directly
  ./screenshots.sh --show                       # Show current setting
  ./screenshots.sh --reset                      # Reset to Desktop

ENVIRONMENT VARIABLES:
  SCREENSHOT_DIR          Default path suggestion (default: ~/Pictures/Screenshots)

EOF
}

# -------- Entry point --------
main() {
  case "${1:-}" in
    --help|-h)
      show_help
      ;;
    --show|-s)
      show_current_location
      ;;
    --reset|-r)
      reset_screenshot_location
      ;;
    --*)
      err "Unknown option: $1"
      show_help
      exit 1
      ;;
    "")
      # No argument: prompt interactively
      prompt_for_path
      ;;
    *)
      # Path provided as argument
      configure_screenshot_location "$1"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

