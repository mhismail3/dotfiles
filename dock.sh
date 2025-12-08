#!/usr/bin/env bash
# dock.sh
#
# Purpose:
#   Configure Dock layout using dockutil with timeout protection.
#   Can be sourced by .macos or run standalone.
#
# Notes:
#   - Requires dockutil from Homebrew (brew install dockutil)
#   - Uses timeout wrapper to prevent hangs on Sequoia
#   - All changes are applied with --no-restart, then Dock is restarted once

set -euo pipefail

# -------- Configuration --------
# Apps to add to Dock (left to right)
DOCK_APPS=(
    "/System/Applications/Calendar.app"
    "/Applications/Things3.app"
    "/System/Applications/Messages.app"
    "/Applications/Arc.app"
    "/Applications/Stremio.app"
    "/System/Applications/Photos.app"
    "/Applications/Cursor.app"
    "/System/Applications/Utilities/Terminal.app"
    "/Applications/Warp.app"
    "/System/Applications/Utilities/Screen Sharing.app"
    "/System/Applications/System Settings.app"
)

# Timeout settings
DOCKUTIL_TIMEOUT_CMD="$(command -v gtimeout || command -v timeout || true)"
: "${DOCKUTIL_TIMEOUT_SECS:=10}"
: "${DOCKUTIL_TRACE:=0}"

# -------- Internal helpers --------
log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# run_dockutil wraps each call with a hard timeout guard.
# Priority: gtimeout/timeout if present; otherwise a polling-based timeout.
run_dockutil() {
    if [[ -n "$DOCKUTIL_TIMEOUT_CMD" ]]; then
        "$DOCKUTIL_TIMEOUT_CMD" "$DOCKUTIL_TIMEOUT_SECS" "$@"
        return $?
    fi

    # Polling-based timeout (more reliable than background wait on macOS)
    local start pid status elapsed
    start=$(date +%s)

    "$@" &
    pid=$!

    # Poll for completion with timeout
    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start ))
        if (( elapsed >= DOCKUTIL_TIMEOUT_SECS )); then
            echo "WARN: dockutil timed out after ${elapsed}s; killing pid $pid ($*)" >&2
            kill -TERM "$pid" 2>/dev/null || true
            sleep 0.5
            kill -KILL "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null
            return 124  # timeout exit code
        fi
        sleep 0.2
    done

    wait "$pid"
    status=$?

    if [[ "$DOCKUTIL_TRACE" == "1" ]]; then
        elapsed=$(( $(date +%s) - start ))
        echo "INFO: dockutil finished in ${elapsed}s (exit ${status}): $*"
    fi
    return $status
}

# -------- User-facing functions --------
configure_dock_layout() {
    if ! command -v dockutil &>/dev/null; then
        err "⚠️  dockutil not found. Install via Brewfile to configure Dock layout."
        return 0
    fi

    log "Configuring Dock layout..."

    # Clear existing Dock items (with timeout guard to avoid hangs)
    run_dockutil dockutil --remove all --no-restart 2>/dev/null || true
    sleep 0.5

    # Add apps in order (with timeout guard to prevent hangs on stuck dockutil)
    for app in "${DOCK_APPS[@]}"; do
        if [[ -d "$app" ]]; then
            local app_name
            app_name=$(basename "$app" .app)
            run_dockutil dockutil --remove "$app_name" --no-restart 2>/dev/null || true
            run_dockutil dockutil --add "$app" --no-restart || err "⚠️  dockutil add may have stalled for $app_name; continuing."
        fi
    done

    # Restart Dock now to apply all changes and reset state
    # This prevents hangs in subsequent defaults write commands
    log "Restarting Dock to apply layout changes..."
    killall Dock 2>/dev/null || true
    sleep 1
}

# -------- Entry point --------
# You can either:
#   1) execute this script directly, or
#   2) source it and call configure_dock_layout from another script.

# Check if running directly (not sourced) - works in bash and zsh
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    [[ "${BASH_SOURCE[0]}" == "$0" ]] && configure_dock_layout
elif [[ "${ZSH_EVAL_CONTEXT:-}" != *":file:"* && "${ZSH_EVAL_CONTEXT:-}" != *":file" ]]; then
    configure_dock_layout
fi

