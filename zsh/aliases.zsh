# aliases.zsh — Shell aliases

###############################################################################
# Navigation
###############################################################################

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ~="cd ~"
alias dl="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias dot="cd ~/.dotfiles"
alias proj="cd ~/projects"

###############################################################################
# Modern Replacements
###############################################################################

# ls → eza
if command -v eza &>/dev/null; then
    alias ls="eza"
    alias ll="eza -la"
    alias la="eza -a"
    alias lt="eza --tree --level=2"
    alias l="eza -l"
else
    alias ll="ls -la"
    alias la="ls -a"
fi

# cat → bat
if command -v bat &>/dev/null; then
    alias cat="bat --paging=never"
    alias catp="bat"
fi

# find → fd (only create alias for common use, keep find available as /usr/bin/find)
if command -v fd &>/dev/null; then
    alias fnd="fd"
    # Note: We don't alias find→fd because fd has different syntax
    # Use: fnd instead of find for the new behavior
fi

# grep → ripgrep (only create alias, keep grep available)
if command -v rg &>/dev/null; then
    alias rgrep="rg"
    # Note: We don't alias grep→rg because rg has different syntax
    # Use: rgrep instead of grep for the new behavior
fi

# top → btop/htop
if command -v btop &>/dev/null; then
    alias top="btop"
elif command -v htop &>/dev/null; then
    alias top="htop"
fi

# du → dust
if command -v dust &>/dev/null; then
    alias du="dust"
fi

# df → duf
if command -v duf &>/dev/null; then
    alias df="duf"
fi

# ps → procs
if command -v procs &>/dev/null; then
    alias ps="procs"
fi

###############################################################################
# Git
###############################################################################

alias g="git"
alias gs="git status"
alias ga="git add"
alias gaa="git add --all"
alias gc="git commit"
alias gcm="git commit -m"
alias gp="git push"
alias gpl="git pull"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gb="git branch"
alias gd="git diff"
alias gl="git log --oneline -20"
alias glog="git log --graph --oneline --decorate"

# Pull all repos in ~/projects/
pullall() {
    local projects_dir="${HOME}/projects"
    if [[ ! -d "$projects_dir" ]]; then
        echo "Projects directory not found: $projects_dir"
        return 1
    fi

    local count=0
    local failed=0

    for dir in "$projects_dir"/*/; do
        [[ -d "${dir}.git" ]] || continue
        local repo_name=$(basename "$dir")
        echo "→ Pulling $repo_name..."
        if git -C "$dir" pull --quiet 2>/dev/null; then
            ((count++))
        else
            echo "  ✗ Failed to pull $repo_name"
            ((failed++))
        fi
    done

    echo ""
    echo "Pulled $count repo(s)${failed:+, $failed failed}"
}

###############################################################################
# Shortcuts
###############################################################################

alias c="clear"
alias h="history"
alias q="exit"
alias v="nvim"
alias vim="nvim"

###############################################################################
# Homebrew
###############################################################################

alias brewup="brew update && brew upgrade && brew cleanup"
alias brewdump="brew bundle dump --file=~/.dotfiles/Brewfile --force"

###############################################################################
# System
###############################################################################

alias ip="curl -s ipinfo.io/ip"
alias localip="ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1"
alias ports="lsof -i -P -n | grep LISTEN"
alias cpu="top -l 1 | head -n 10"
alias mem="top -l 1 | head -n 10 | grep PhysMem"

# Empty trash safely
alias emptytrash="rm -rf ~/.Trash/*"

###############################################################################
# Development
###############################################################################

alias py="python3"
alias python="python3"
alias pip="pip3"
alias serve="python3 -m http.server 8000"
alias json="jq ."


###############################################################################
# Network
###############################################################################

alias ping="ping -c 5"
alias wget="wget -c"

###############################################################################
# macOS
###############################################################################

alias finder="open -a Finder"
alias preview="open -a Preview"

# Flush DNS cache
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

# Show/hide hidden files (Finder)
alias showfiles="defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder"
alias hidefiles="defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder"

# Lock screen / Start screensaver
alias afk="open -a ScreenSaverEngine"
alias lock="pmset displaysleepnow"

###############################################################################
# Safety nets (confirm before overwriting)
###############################################################################

alias cp="cp -iv"
alias mv="mv -iv"
alias rm="rm -iv"
alias mkdir="mkdir -pv"

###############################################################################
# Quick edits
###############################################################################

alias zshrc="${EDITOR:-nvim} ~/.zshrc"
alias reload="exec zsh"  # Better than source - starts fresh shell

