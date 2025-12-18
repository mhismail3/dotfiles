#!/usr/bin/env bash
# chrome-extensions.sh - Install Google Chrome extensions via External Extensions mechanism
#
# This script creates JSON files in Chrome's External Extensions folder, which triggers
# Chrome to automatically install extensions from the Chrome Web Store on next launch.
#
# Usage: ./chrome-extensions.sh [--dry-run]

set -eo pipefail

# Extension IDs (from Chrome Web Store)
# Format: "extension_id:Extension Name"
EXTENSIONS=(
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa:1Password"
    "ldgfbffkinooeloadekpmfoklnobpien:Raindrop.io"
    "fcoeoabgfenejglbffodgkkbkcdhcgfn:Claude"
)

# Chrome's External Extensions folder
CHROME_EXT_DIR="$HOME/Library/Application Support/Google/Chrome/External Extensions"

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

# Check if Chrome is installed
if [[ ! -d "/Applications/Google Chrome.app" ]]; then
    err "Google Chrome not installed. Skipping extension setup."
    exit 0
fi

# Check if Chrome User Data exists (Chrome has been launched at least once)
if [[ ! -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
    warn "Chrome hasn't been launched yet. Launch Chrome first, then re-run this script."
    exit 0
fi

# Create External Extensions directory if needed
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would create: $CHROME_EXT_DIR"
else
    mkdir -p "$CHROME_EXT_DIR"
fi

echo "Installing Google Chrome extensions..."

installed=0
skipped=0

for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%:*}"
    ext_name="${entry#*:}"
    ext_file="$CHROME_EXT_DIR/$ext_id.json"

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

    # Check if Chrome is running
    if pgrep -q "Google Chrome"; then
        echo ""
        warn "Chrome is running. Restart Chrome to install extensions."
        echo "   Run: osascript -e 'quit app \"Google Chrome\"' && open -a 'Google Chrome'"
    else
        echo ""
        info "Extensions will be installed when Chrome is launched."
    fi
fi

[[ $skipped -gt 0 ]] && echo "Skipped $skipped already-configured extension(s)."

echo ""
echo "Note: Extensions are installed from Chrome Web Store on Chrome launch."
echo "You may need to sign in to each extension after installation."
