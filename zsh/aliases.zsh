# aliases.zsh

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias dl="cd ~/Downloads"
alias dot="cd ~/.dotfiles"
alias ws="cd ~/Workspace"
alias reload="exec zsh"

# Dev
alias json="jq ."

# System
alias ip="curl -s ipinfo.io/ip"
alias localip="ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1"
alias ports="lsof -i -P -n | grep LISTEN"
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

# Homebrew
alias brewup="brew update && brew upgrade && brew cleanup"
alias brewdiff="brew bundle cleanup --file=~/.dotfiles/Brewfile"

# Guardrails — keep the system clean
pip() {
    echo "Use 'uv pip install' or 'uv add' instead (keeps system clean)."
    echo "Override with command pip \$@"
}
pip3() { pip "$@"; }

npm() {
    if [[ "$1" == "install" && "$*" == *"-g"* ]] || [[ "$1" == "install" && "$*" == *"--global"* ]]; then
        echo "Global npm install detected. This pollutes the system."
        echo "Consider a project-local install instead."
        echo "Override with: command npm $*"
        return 1
    fi
    command npm "$@"
}
