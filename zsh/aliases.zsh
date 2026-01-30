# aliases.zsh — Minimal aliases for agent-focused machine

###############################################################################
# Python
###############################################################################

alias py="python3"
alias python="python3"
alias pip="pip3"

###############################################################################
# Development
###############################################################################

alias json="jq ."

###############################################################################
# System Diagnostics
###############################################################################

alias ip="curl -s ipinfo.io/ip"
alias localip="ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1"
alias ports="lsof -i -P -n | grep LISTEN"
alias cpu="top -l 1 | head -n 10"
alias mem="top -l 1 | head -n 10 | grep PhysMem"

###############################################################################
# Homebrew
###############################################################################

alias brewup="brew update && brew upgrade && brew cleanup"
