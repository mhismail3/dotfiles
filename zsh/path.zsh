# path.zsh — PATH modifications
# Homebrew is already set up in .zshrc before this file is sourced

# GNU tools (override BSD defaults)
if [[ -n "$HOMEBREW_PREFIX" ]]; then
    [[ -d "$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/grep/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/grep/libexec/gnubin:$PATH"
    [[ -d "$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin:$PATH"
fi

# User binaries (highest priority)
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"
