# ~/.zshrc — test-host (minimal, non-interactive-friendly)

if [[ $(uname -m) == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

source "$HOME/.dotfiles/zsh/path.zsh"
source "$HOME/.dotfiles/zsh/aliases.zsh"

if type brew &>/dev/null; then
    FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$FPATH"
    autoload -Uz compinit
    compinit
fi

setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY EXTENDED_HISTORY
HISTSIZE=20000
SAVEHIST=20000
HISTFILE=~/.zsh_history

PROMPT='%F{cyan}%m%f:%F{blue}%~%f %# '
