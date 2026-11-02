# Brewfile — mac-mini (M4 Mac mini, headless server)
# Install: brew bundle --file=~/.dotfiles/Brewfile

###############################################################################
# Taps
###############################################################################

tap "mhismail3/tools"

###############################################################################
# CLI — Core
###############################################################################

brew "coreutils"
brew "findutils"
brew "gnu-sed"
brew "gawk"
brew "grep"
brew "curl"
brew "openssh"
brew "websocat"

###############################################################################
# CLI — Development
###############################################################################

brew "git"
brew "git-lfs"
brew "gh"
brew "jq"
brew "yq"
brew "tmux"
brew "ast-grep"
brew "mas"
brew "xcodegen"

###############################################################################
# CLI — Shell
###############################################################################

brew "starship"
brew "zsh-autosuggestions"
brew "zsh-completions"

###############################################################################
# Languages & Runtimes
###############################################################################

brew "uv"                   # Python (primary — manages interpreters + venvs)
brew "python@3.12"          # Python for Codex portable tooling (tomllib)
brew "rustup-init"          # Rust toolchain
brew "oven-sh/bun/bun"      # Bun (fast JS runtime)
brew "nvm"                  # Node version manager
brew "rbenv"                # Ruby version manager
brew "ruby-build"           # rbenv plugin to install Ruby versions

###############################################################################
# Apps — Development
###############################################################################

cask "cursor"
cask "ghostty"
cask "google-chrome"
cask "db-browser-for-sqlite"
cask "docker"
brew "container"           # Apple Linux containers (now a formula)

###############################################################################
# Apps — AI
###############################################################################

cask "claude-code"
cask "codex"
brew "agent-browser"       # now a formula
brew "ollama"

###############################################################################
# Apps — Remote Access & Networking
###############################################################################

cask "tailscale-app"
cask "rustdesk"
cask "private-internet-access"

###############################################################################
# Apps — Cloud Storage & Services
###############################################################################

cask "synology-drive"
cask "google-drive"
brew "googleworkspace-cli"
brew "mhismail3/tools/tron-twitter"
