#!/usr/bin/env zsh

# ssh.sh — Generate SSH key and add to ssh-agent
# Usage: ./ssh.sh [email]

set -e

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
EMAIL="${1:-mhismail3@gmail.com}"

# Ensure .ssh directory exists with correct permissions
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 SSH Key Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -f "$SSH_KEY" ]]; then
    echo "SSH key already exists at $SSH_KEY"
    echo ""
    echo -n "Generate a new key? This will overwrite the existing one. (y/N) "
    read REPLY </dev/tty || REPLY="n"
    echo ""
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Keeping existing key."
        exit 0
    fi
fi

# Generate SSH key
echo "Generating SSH key..."
ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY"

# Start ssh-agent
eval "$(ssh-agent -s)"

# Add key to ssh-agent with Keychain integration
ssh-add --apple-use-keychain "$SSH_KEY"

# Create/update SSH config for Keychain
SSH_CONFIG="$SSH_DIR/config"
if [[ ! -f "$SSH_CONFIG" ]]; then
    cat > "$SSH_CONFIG" << 'EOF'
# Default settings for all hosts
Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
    chmod 600 "$SSH_CONFIG"
    echo "Created SSH config with macOS Keychain integration"
elif ! grep -q "AddKeysToAgent" "$SSH_CONFIG"; then
    # Append to existing config if AddKeysToAgent not present
    cat >> "$SSH_CONFIG" << 'EOF'

# Added by ssh.sh
Host *
    AddKeysToAgent yes
    UseKeychain yes
EOF
    echo "Updated SSH config with Keychain integration"
else
    echo "SSH config already configured"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SSH key generated!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Your public key:"
echo ""
cat "$SSH_KEY.pub"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. The public key has been copied to your clipboard"
echo "  2. Add to GitHub: https://github.com/settings/keys"
echo "  3. Add to other services as needed"
echo ""
echo "Test GitHub connection with: ssh -T git@github.com"
echo ""

# Copy to clipboard
if command -v pbcopy &>/dev/null; then
    pbcopy < "$SSH_KEY.pub"
    echo "📋 Public key copied to clipboard!"
fi

# Set correct permissions on key files
chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"

