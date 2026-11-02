# Brewfile — test-host (headless M4 Mac mini that runs builds and tests)
# Install: brew bundle --file=~/.dotfiles/Brewfile
#
# Deliberately small. Project toolchains (Node, xcodegen) are pinned and
# installed by each repo itself, e.g. tron's scripts/install-ci-tools.sh.

tap "cirruslabs/cli"

# Core CLI
brew "coreutils"
brew "git"
brew "git-lfs"
brew "gh"
brew "jq"
brew "tmux"
brew "uv"                     # Python interpreters/venvs for repo scripts

# Xcode + simulator runtimes, installed headlessly
brew "xcodes"
brew "aria2"                  # faster xcodes downloads

# Isolation for test runs
brew "cirruslabs/cli/tart"    # macOS/Linux VMs (Apple limits macOS guests to 2)

# Networking — open-source tailscaled runs as a boot daemon and is the
# macOS variant that supports Tailscale SSH server
brew "tailscale"
