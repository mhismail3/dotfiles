# path.zsh — PATH modifications
# Note: Homebrew is already set up in .zshrc before this file is sourced

###############################################################################
# GNU Tools (use without 'g' prefix)
# These override the BSD versions that ship with macOS
###############################################################################

# Only add if Homebrew is available and tools are installed
if [[ -n "$HOMEBREW_PREFIX" ]]; then
    # GNU coreutils (ls, cp, mv, etc.)
    [[ -d "$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"

    # GNU findutils (find, xargs, locate)
    [[ -d "$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin:$PATH"

    # GNU sed
    [[ -d "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$PATH"

    # GNU grep
    [[ -d "$HOMEBREW_PREFIX/opt/grep/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/grep/libexec/gnubin:$PATH"

    # GNU awk
    [[ -d "$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin" ]] && \
        export PATH="$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin:$PATH"
fi

###############################################################################
# User binaries (highest priority - added last to be first in PATH)
###############################################################################

[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

# Note: Language-specific paths (Go, Rust, etc.) are set in .zshrc
# with lazy loading for version managers

