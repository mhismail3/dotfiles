# ~/.zshrc

###############################################################################
# Homebrew
###############################################################################

if [[ $(uname -m) == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

###############################################################################
# Path & Aliases
###############################################################################

source "$HOME/.dotfiles/zsh/path.zsh"
source "$HOME/.dotfiles/zsh/aliases.zsh"

###############################################################################
# Languages (isolated — never touch system installs)
###############################################################################

# Rust
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# Bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# Node (nvm — lazy loaded for speed)
export NVM_DIR="$HOME/.nvm"
if [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]; then
    source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
fi

# Ruby (rbenv)
if command -v rbenv &>/dev/null; then
    eval "$(rbenv init - zsh)"
fi

# Go
export GOPATH="$HOME/go"
[ -d "$GOPATH/bin" ] && export PATH="$GOPATH/bin:$PATH"

###############################################################################
# Zsh Plugins
###############################################################################

if [[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

if type brew &>/dev/null; then
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

eval "$(starship init zsh)"
