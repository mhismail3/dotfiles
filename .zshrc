# ~/.zshrc

###############################################################################
# Homebrew
###############################################################################

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

###############################################################################
# PATH
###############################################################################

if [[ -n "$HOMEBREW_PREFIX" ]]; then
    [[ -d "$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin" ]] &&
        export PATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin" ]] &&
        export PATH="$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin" ]] &&
        export PATH="$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/grep/libexec/gnubin" ]] &&
        export PATH="$HOMEBREW_PREFIX/opt/grep/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin" ]] &&
        export PATH="$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin:$PATH"
fi

[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

###############################################################################
# Aliases
###############################################################################

alias ..="cd .."
alias ...="cd ../.."
alias dl="cd ~/Downloads"
alias dot="cd ~/Workspace/dotfiles"
alias ws="cd ~/Workspace"
alias reload="exec zsh"

alias json="jq ."

alias ip="curl -s ipinfo.io/ip"
alias localip="ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1"
alias ports="lsof -i -P -n | grep LISTEN"
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

alias brewup="brew update && brew upgrade && brew cleanup"
alias brewdiff="brew bundle cleanup --file=~/Workspace/dotfiles/Brewfile"

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

###############################################################################
# Languages
###############################################################################

if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/opt/rustup/bin" ]]; then
    export PATH="$HOMEBREW_PREFIX/opt/rustup/bin:$PATH"
fi
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && export PATH="$BUN_INSTALL/bin:$PATH"
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

export NVM_DIR="$HOME/.nvm"
if [[ -n "$HOMEBREW_PREFIX" && -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]]; then
    source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
fi

if command -v rbenv &>/dev/null; then
    eval "$(rbenv init - zsh)"
fi

export GOPATH="$HOME/go"
[[ -d "$GOPATH/bin" ]] && export PATH="$GOPATH/bin:$PATH"

###############################################################################
# Zsh Plugins
###############################################################################

if [[ -n "$HOMEBREW_PREFIX" && -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -n "$HOMEBREW_PREFIX" && -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

if type brew &>/dev/null && [[ -t 0 && -t 1 ]]; then
    FPATH="$HOME/.local/share/zsh/site-functions:$FPATH"
    FPATH="$HOMEBREW_PREFIX/share/zsh-completions:$FPATH"
    FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$FPATH"
    autoload -Uz compinit
    compinit
fi

###############################################################################
# Options
###############################################################################

setopt AUTO_CD
setopt CORRECT
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_VERIFY

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

###############################################################################
# Key Bindings
###############################################################################

autosuggest-accept-or-complete() {
    if [[ -n "$POSTDISPLAY" ]]; then
        zle autosuggest-accept
    else
        zle expand-or-complete
    fi
}
zle -N autosuggest-accept-or-complete
bindkey '^I' autosuggest-accept-or-complete

###############################################################################
# Prompt
###############################################################################

if [[ "$TERM" != "dumb" ]] && command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi
