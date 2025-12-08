#!/usr/bin/env bash
# keyboard.sh
#
# Purpose:
#   Configure keyboard remapping and custom shortcuts:
#   - Caps Lock → Command (via LaunchDaemon for persistence)
#   - Option+L for Lock Screen (via App Shortcuts)
#
# Notes:
#   - Caps Lock remap requires sudo (creates LaunchDaemon)
#   - Uses hidutil for hardware key remapping
#   - LaunchDaemon ensures remap persists across reboots

set -euo pipefail

# -------- Internal helpers --------
log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# -------- User-facing functions --------

# Configure Option+L as Lock Screen shortcut
configure_lock_screen_shortcut() {
    log "Configuring Option+L for Lock Screen..."
    defaults write -g NSUserKeyEquivalents -dict-add "Lock Screen" "~l"
}

# Configure Caps Lock → Command via LaunchDaemon
configure_caps_lock_remap() {
    log "Configuring Caps Lock → Command remap..."

    # Create hidutil LaunchDaemon for Caps Lock → Command remap
    # Caps Lock = 0x700000039, Left Command = 0x7000000E3
    local plist_path="/Library/LaunchDaemons/com.local.KeyRemapping.plist"

    sudo tee "$plist_path" > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.KeyRemapping</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E3}]}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

    sudo chown root:wheel "$plist_path"
    sudo chmod 644 "$plist_path"
    sudo launchctl bootstrap system "$plist_path" 2>/dev/null || true

    # Apply immediately for current session
    sudo hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E3}]}'
}

# Main entry point - configure all keyboard settings
configure_keyboard_remapping() {
    configure_lock_screen_shortcut
    configure_caps_lock_remap
}

# -------- Entry point --------
# You can either:
#   1) execute this script directly, or
#   2) source it and call configure_keyboard_remapping from another script.

# Check if running directly (not sourced) - works in bash and zsh
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    [[ "${BASH_SOURCE[0]}" == "$0" ]] && configure_keyboard_remapping
elif [[ "${ZSH_EVAL_CONTEXT:-}" != *":file:"* && "${ZSH_EVAL_CONTEXT:-}" != *":file" ]]; then
    configure_keyboard_remapping
fi

