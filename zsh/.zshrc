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
# Version Managers (Lazy Loading for Fast Startup)
###############################################################################

# Go (lightweight, no lazy loading needed)
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Rust (lightweight, just add to PATH)
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# pyenv (lazy load to avoid ~100ms startup penalty)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

_pyenv_lazy_load() {
    unset -f pyenv python python3 pip pip3
    if command -v pyenv &>/dev/null; then
        eval "$(pyenv init -)"
        # Note: pyenv virtualenv-init is very slow, only enable if needed
        # eval "$(pyenv virtualenv-init -)"
    fi
}

pyenv()   { _pyenv_lazy_load; pyenv "$@"; }
python3() { _pyenv_lazy_load; python3 "$@"; }
pip3()    { _pyenv_lazy_load; pip3 "$@"; }

# nvm (lazy load to avoid ~200ms startup penalty)
export NVM_DIR="$HOME/.nvm"

_nvm_lazy_load() {
    unset -f node npm npx nvm yarn pnpm _nvm_lazy_load
    [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
    [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
}

node()  { _nvm_lazy_load && node "$@"; }
npm()   { _nvm_lazy_load && npm "$@"; }
npx()   { _nvm_lazy_load && npx "$@"; }
nvm()   { _nvm_lazy_load && nvm "$@"; }
yarn()  { _nvm_lazy_load && yarn "$@"; }
pnpm()  { _nvm_lazy_load && pnpm "$@"; }

# rbenv (lazy load)
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/bin:$PATH"

_rbenv_lazy_load() {
    unset -f rbenv ruby gem bundle
    if command -v rbenv &>/dev/null; then
        eval "$(rbenv init - zsh)"
    fi
}

rbenv()  { _rbenv_lazy_load; rbenv "$@"; }
ruby()   { _rbenv_lazy_load; ruby "$@"; }
gem()    { _rbenv_lazy_load; gem "$@"; }
bundle() { _rbenv_lazy_load; bundle "$@"; }

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
# Shell startup optimized with lazy loading of version managers.
# To profile startup time, run: time zsh -i -c exit
# Or use: zmodload zsh/zprof at top, then zprof at bottom

