# Brewfile for moose-home-server
# Install: brew bundle --file=~/.dotfiles/Brewfile

###############################################################################
# Taps
###############################################################################

# Note: homebrew/bundle is built-in to Homebrew now (no tap needed)
# Note: homebrew/cask-fonts was deprecated in 2024 - fonts are now in main cask

###############################################################################
# CLI Tools - Core Utilities
###############################################################################

brew "coreutils"        # GNU core utilities (gls, gcp, etc.)
brew "findutils"        # GNU find, xargs, locate
brew "gnu-sed"          # GNU sed
brew "gawk"             # GNU awk
brew "grep"             # GNU grep
brew "wget"             # Download files
brew "curl"             # Transfer data (newer than system)
brew "openssh"          # SSH (newer than system)

###############################################################################
# CLI Tools - Modern Replacements
###############################################################################

brew "bat"              # Better cat with syntax highlighting
brew "eza"              # Better ls (successor to exa)
brew "fd"               # Better find
brew "ripgrep"          # Better grep (rg)
brew "sd"               # Better sed for find/replace
brew "zoxide"           # Better cd with frecency
brew "fzf"              # Fuzzy finder
brew "htop"             # Better top
brew "btop"             # Even better top with graphs
brew "ncdu"             # Disk usage analyzer
brew "dust"             # Better du
brew "duf"              # Better df
brew "procs"            # Better ps
brew "tldr"             # Simplified man pages

###############################################################################
# CLI Tools - Development & Productivity
###############################################################################

brew "git"              # Version control
brew "git-lfs"          # Git Large File Storage
brew "git-delta"        # Better git diff pager (used in .gitconfig)
brew "gh"               # GitHub CLI
brew "jq"               # JSON processor
brew "yq"               # YAML processor
brew "httpie"           # Better curl for APIs
brew "tree"             # Directory tree
brew "watch"            # Execute command periodically
brew "tmux"             # Terminal multiplexer
brew "neovim"           # Modern vim
brew "shellcheck"       # Shell script linter
brew "shfmt"            # Shell script formatter

###############################################################################
# CLI Tools - Networking & System
###############################################################################

brew "nmap"             # Network scanner
brew "mtr"              # Network diagnostic (traceroute + ping)
brew "iperf3"           # Network performance
brew "rsync"            # File sync (newer than system)
brew "ssh-copy-id"      # Copy SSH keys to servers
brew "mas"              # Mac App Store CLI

###############################################################################
# CLI Tools - Compression & Archives
###############################################################################

brew "p7zip"            # 7-Zip
brew "xz"               # XZ compression
brew "zstd"             # Zstandard compression
brew "pigz"             # Parallel gzip
# brew "unrar"            # RAR extraction - license issues, use unar or 7zip instead
brew "unar"             # Universal archive extractor (better than unrar)

###############################################################################
# Languages & Version Managers
# (Use version managers to avoid conflicts with system)
###############################################################################

# Python
brew "pyenv"            # Python version manager
brew "pyenv-virtualenv" # Virtualenv plugin for pyenv
brew "pipx"             # Install Python apps in isolated envs

# Node.js
brew "nvm"              # Node version manager
# Note: yarn is best installed via corepack (comes with Node.js) or npm
# brew "yarn"             # Package manager - prefer corepack enable && corepack prepare yarn@stable

# Ruby
brew "rbenv"            # Ruby version manager
brew "ruby-build"       # Install Ruby versions

# Go
brew "go"               # Go language

# Rust
brew "rustup-init"      # Rust toolchain installer

###############################################################################
# Shell Enhancements
###############################################################################

brew "zsh-syntax-highlighting"
brew "zsh-autosuggestions"
brew "zsh-completions"
brew "starship"         # Cross-shell prompt (optional)

###############################################################################
# Fonts
###############################################################################

cask "font-jetbrains-mono"
cask "font-jetbrains-mono-nerd-font"
cask "font-fira-code"
cask "font-fira-code-nerd-font"

###############################################################################
# Applications - Productivity
###############################################################################

cask "raycast"          # Spotlight replacement
cask "1password"        # Password manager
cask "arc"              # Browser

###############################################################################
# Applications - Development
###############################################################################

cask "cursor"           # AI code editor
cask "visual-studio-code"
cask "warp"             # Modern terminal

###############################################################################
# Applications - Cloud Storage
###############################################################################

cask "synology-drive"   # Synology NAS sync
cask "google-drive"     # Google Drive sync

###############################################################################
# Applications - Media & Utilities
###############################################################################

cask "vlc"              # Media player
cask "keka"             # Archive utility (better than The Unarchiver)
cask "qbittorrent"      # Torrent client (cleaner than uTorrent)
cask "hand-mirror"      # Quick camera check from menu bar

###############################################################################
# Applications - Privacy & Security
###############################################################################

cask "private-internet-access"  # VPN

###############################################################################
# Mac App Store Apps
###############################################################################

mas "Things 3", id: 904280696
# mas "Xcode", id: 497799835  # Uncomment if needed (large download)
# mas "Amphetamine", id: 937984704  # Keep Mac awake (optional for server)

