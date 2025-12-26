# ~/.zshrc — Zsh configuration

###############################################################################
# Oh My Zsh
###############################################################################

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
    git
    macos
    docker
    # npm plugin removed - conflicts with nvm lazy loading
    python
    brew
    zoxide
)

source $ZSH/oh-my-zsh.sh

###############################################################################
# Homebrew
###############################################################################

if [[ $(uname -m) == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

###############################################################################
# Path
###############################################################################

source "$HOME/.dotfiles/zsh/path.zsh"

###############################################################################
# Aliases
###############################################################################

source "$HOME/.dotfiles/zsh/aliases.zsh"

###############################################################################
# API Keys (Secure Storage)
###############################################################################

source "$HOME/.dotfiles/zsh/api-keys.zsh"

###############################################################################
# Version Managers
###############################################################################

# Go
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Rust
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# pyenv - Initialize properly for both interactive and non-interactive shells
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv &>/dev/null; then
    eval "$(pyenv init -)"
fi

# nvm - Initialize properly for both interactive and non-interactive shells
export NVM_DIR="$HOME/.nvm"
if [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]; then
    source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
fi
# Bash completion only for interactive shells
if [ -n "$PS1" ] && [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ]; then
    source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
fi

# rbenv - Initialize properly for both interactive and non-interactive shells
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/bin:$PATH"
if command -v rbenv &>/dev/null; then
    eval "$(rbenv init - zsh)"
fi

###############################################################################
# Zsh Plugins (from Homebrew)
###############################################################################

# Syntax highlighting
if [[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Autosuggestions
if [[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Completions
if type brew &>/dev/null; then
    FPATH="$HOMEBREW_PREFIX/share/zsh-completions:$FPATH"
    FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$FPATH"
    autoload -Uz compinit
    compinit
fi

###############################################################################
# Tools
###############################################################################

# fzf (use new --zsh integration if available)
if command -v fzf &>/dev/null; then
    eval "$(fzf --zsh)"
fi

# zoxide (better cd)
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# Starship prompt (optional - uncomment to use instead of Oh My Zsh theme)
# eval "$(starship init zsh)"

###############################################################################
# Options
###############################################################################

setopt AUTO_CD              # cd by typing directory name
setopt CORRECT              # Spell correction
setopt HIST_IGNORE_DUPS     # Ignore duplicate history entries
setopt HIST_IGNORE_SPACE    # Ignore commands starting with space
setopt SHARE_HISTORY        # Share history across terminals
setopt APPEND_HISTORY       # Append to history file
setopt EXTENDED_HISTORY     # Add timestamps to history
setopt HIST_VERIFY          # Show command before executing from history

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

###############################################################################
# Key Bindings (must be after compinit and plugins)
###############################################################################

# Tab: accept autosuggestion if present, otherwise normal completion
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
# Performance Note
###############################################################################
# Version managers are initialized immediately for reliability.
# This adds ~100-200ms to shell startup but ensures compatibility with
# non-interactive shells (Claude Code, scripts, etc.)
# To profile startup time, run: time zsh -i -c exit

