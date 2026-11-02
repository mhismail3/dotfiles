# aliases.zsh — test-host

alias ports="lsof -i -P -n | grep LISTEN"
alias brewup="brew update && brew upgrade && brew cleanup"
alias brewdiff="brew bundle cleanup --file=~/.dotfiles/Brewfile"

# Housekeeping for a build box
alias simclean="xcrun simctl shutdown all; xcrun simctl delete unavailable"
alias ddclean="rm -rf ~/Library/Developer/Xcode/DerivedData/*"
alias diskfree="df -h / | tail -1"
