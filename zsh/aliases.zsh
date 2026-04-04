# aliases.zsh

# Python (always use uv-managed, never system)
alias py="python3"
alias python="python3"
alias pip="pip3"

# Dev
alias json="jq ."

# System diagnostics
alias ip="curl -s ipinfo.io/ip"
alias localip="ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1"
alias ports="lsof -i -P -n | grep LISTEN"

# Homebrew
alias brewup="brew update && brew upgrade && brew cleanup"
