#!/usr/bin/env bash
# arc-settings.sh - Configure Arc browser settings via Preferences JSON
#
# This script modifies Arc's Preferences file to apply custom content settings.
# Arc must NOT be running when this script executes (settings are overwritten on quit).
#
# Usage: ./arc-settings.sh [--dry-run]

set -eo pipefail

ARC_PREFS="$HOME/Library/Application Support/Arc/User Data/Default/Preferences"

# Sites to block from auto picture-in-picture
# Format: domain (will be stored as "domain,*" in preferences)
BLOCK_AUTO_PIP=(
    "music.youtube.com"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
err()     { echo -e "${RED}✗${NC} $1" >&2; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check if Arc is installed
if [[ ! -d "/Applications/Arc.app" ]]; then
    err "Arc browser not installed. Skipping settings configuration."
    exit 0
fi

# Check if Arc Preferences exist
if [[ ! -f "$ARC_PREFS" ]]; then
    warn "Arc Preferences not found. Launch Arc first, then re-run this script."
    exit 0
fi

# Check if Arc is running
if pgrep -q "Arc"; then
    err "Arc is currently running. Please quit Arc first."
    echo "   Run: osascript -e 'quit app \"Arc\"'"
    echo "   Then re-run this script."
    exit 1
fi

echo "Configuring Arc browser settings..."

# Use Python to safely modify JSON (handles nested structures properly)
/usr/bin/python3 << PYTHON
import json
import sys
import time

prefs_path = "$ARC_PREFS"
dry_run = "$DRY_RUN" == "true"
block_pip_sites = [$(printf '"%s",' "${BLOCK_AUTO_PIP[@]}" | sed 's/,$//')]

# Chrome timestamp: microseconds since 1601-01-01
# We'll use current time for last_modified
def chrome_timestamp():
    # Microseconds between 1601-01-01 and 1970-01-01
    epoch_diff = 11644473600000000
    return str(int(time.time() * 1000000) + epoch_diff)

try:
    with open(prefs_path, 'r') as f:
        prefs = json.load(f)
except json.JSONDecodeError as e:
    print(f"✗ Failed to parse Preferences JSON: {e}", file=sys.stderr)
    sys.exit(1)

# Ensure nested structure exists
if 'profile' not in prefs:
    prefs['profile'] = {}
if 'content_settings' not in prefs['profile']:
    prefs['profile']['content_settings'] = {}
if 'exceptions' not in prefs['profile']['content_settings']:
    prefs['profile']['content_settings']['exceptions'] = {}
if 'auto_picture_in_picture' not in prefs['profile']['content_settings']['exceptions']:
    prefs['profile']['content_settings']['exceptions']['auto_picture_in_picture'] = {}

pip_settings = prefs['profile']['content_settings']['exceptions']['auto_picture_in_picture']

modified = False
for site in block_pip_sites:
    key = f"{site},*"
    if key in pip_settings and pip_settings[key].get('setting') == 2:
        print(f"⚠ {site}: auto picture-in-picture already blocked (skipping)")
    else:
        if dry_run:
            print(f"[dry-run] Would block auto picture-in-picture for: {site}")
        else:
            pip_settings[key] = {
                "last_modified": chrome_timestamp(),
                "setting": 2  # 2 = block
            }
            print(f"✓ {site}: blocked auto picture-in-picture")
        modified = True

if modified and not dry_run:
    with open(prefs_path, 'w') as f:
        json.dump(prefs, f, separators=(',', ':'))
    print()
    print("✓ Arc Preferences updated successfully")

PYTHON

echo ""
info "Done. Launch Arc to apply settings."
