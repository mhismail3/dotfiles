#!/usr/bin/env bash
# arc-extensions.sh - Install Arc browser extensions via External Extensions mechanism
#
# This script creates JSON files in Arc's External Extensions folder, which triggers
# Arc to automatically install extensions from the Chrome Web Store on next launch.
#
# Usage: ./arc-extensions.sh [--dry-run]

set -eo pipefail

# Extension IDs (from Chrome Web Store - Arc uses the same IDs)
# Format: "extension_id:Extension Name"
EXTENSIONS=(
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa:1Password"
    "ldgfbffkinooeloadekpmfoklnobpien:Raindrop.io"
)

# Arc's External Extensions folder
ARC_EXT_DIR="$HOME/Library/Application Support/Arc/User Data/External Extensions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
err()     { echo -e "${RED}✗${NC} $1" >&2; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check if Arc is installed
if [[ ! -d "/Applications/Arc.app" ]]; then
    err "Arc browser not installed. Skipping extension setup."
    exit 0
fi

# Check if Arc User Data exists (Arc has been launched at least once)
if [[ ! -d "$HOME/Library/Application Support/Arc/User Data" ]]; then
    warn "Arc hasn't been launched yet. Launch Arc first, then re-run this script."
    exit 0
fi

# Create External Extensions directory if needed
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would create: $ARC_EXT_DIR"
else
    mkdir -p "$ARC_EXT_DIR"
fi

echo "Installing Arc browser extensions..."

installed=0
skipped=0

for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%:*}"
    ext_name="${entry#*:}"
    ext_file="$ARC_EXT_DIR/$ext_id.json"

    if [[ -f "$ext_file" ]]; then
        warn "$ext_name already configured (skipping)"
        ((skipped++))
        continue
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would create: $ext_file"
    else
        cat > "$ext_file" << 'EOF'
{
  "external_update_url": "https://clients2.google.com/service/update2/crx"
}
EOF
        info "$ext_name extension configured"
    fi
    ((installed++))
done

echo ""
if [[ $installed -gt 0 ]]; then
    echo "Configured $installed extension(s)."

    # Check if Arc is running
    if pgrep -q "Arc"; then
        echo ""
        warn "Arc is running. Restart Arc to install extensions."
        echo "   Run: osascript -e 'quit app \"Arc\"' && open -a Arc"
    else
        echo ""
        info "Extensions will be installed when Arc is launched."
    fi
fi

[[ $skipped -gt 0 ]] && echo "Skipped $skipped already-configured extension(s)."

echo ""
echo "Note: Extensions are installed from Chrome Web Store on Arc launch."
echo "You may need to sign in to each extension after installation."
