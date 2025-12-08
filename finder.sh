#!/usr/bin/env bash
# finder-customize.sh
#
# Purpose:
#   1) Set Finder Favorites to:
#        - Home (shows as your username, e.g., "moose")
#        - Applications
#        - Downloads
#        - iCloud Drive
#      This removes default "Recents" and "Shared" by replacing the Favorites list.
#   2) Set global default Finder view style to Column view.
#   3) Optionally clear per-folder view overrides in your home directory.
#
# Notes:
#   - Since macOS 13, Finder sidebar Favorites are stored in SharedFileList files under
#     ~/Library/Application Support/com.apple.sharedfilelist/, specifically FavoriteItems.sfl3. :contentReference[oaicite:0]{index=0}
#   - macOS 26 Tahoe replaces .sfl3 with .sfl4 but uses a very similar structure. :contentReference[oaicite:1]{index=1}
#   - sharedfilelistd maintains these lists; restarting it (and optionally Finder) reloads the sidebar. :contentReference[oaicite:2]{index=2}
#   - The default view style for folders without custom settings is controlled by
#     com.apple.finder FXPreferredViewStyle; Column view is "clmv". :contentReference[oaicite:3]{index=3}
#   - Per-folder view customizations are stored in .DS_Store; removing them resets folders
#     to defaults. :contentReference[oaicite:4]{index=4}
#   - iCloud Drive’s local path is typically:
#     ~/Library/Mobile Documents/com~apple~CloudDocs/ :contentReference[oaicite:5]{index=5}

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------- Configuration knobs --------
# If 1, delete .DS_Store files under $HOME to reduce per-folder overrides.
: "${RESET_DS_STORE:=1}"

# If 1, force reload by restarting Finder for immediate UI update.
: "${FINDER_FORCE_RELOAD:=1}"

# Optional override for where to install the Swift CLI:
#   export SIDEBARCTL_INSTALL_DIR="/some/bin"
: "${SIDEBARCTL_INSTALL_DIR:=}"
: "${SIDEBARCTL_SOURCE:="$DOTFILES_DIR/bin/sidebarctl.swift"}"

# -------- Internal helpers --------
log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

detect_install_dir() {
  if [[ -n "$SIDEBARCTL_INSTALL_DIR" ]]; then
    echo "$SIDEBARCTL_INSTALL_DIR"
    return 0
  fi

  # Prefer Homebrew prefixes if present
  if [[ -d "/opt/homebrew/bin" ]]; then
    if [[ -w "/opt/homebrew/bin" ]]; then
      echo "/opt/homebrew/bin"
      return 0
    fi
  fi

  if [[ -d "/usr/local/bin" ]]; then
    if [[ -w "/usr/local/bin" ]]; then
      echo "/usr/local/bin"
      return 0
    fi
  fi

  # Fallback user-local bin
  echo "$HOME/.local/bin"
}

install_sidebarctl() {
  command -v swift >/dev/null 2>&1 || {
    err "swift not found. Install Xcode Command Line Tools before running this.\n"
    return 2
  }

  local install_dir
  install_dir="$(detect_install_dir)"
  mkdir -p "$install_dir"

  local sidebarctl_path="$install_dir/sidebarctl"

  if [[ ! -f "$SIDEBARCTL_SOURCE" ]]; then
    err "sidebarctl source not found at $SIDEBARCTL_SOURCE"
    return 2
  fi

  # Update the script if source is newer or script doesn't exist
  if [[ ! -x "$sidebarctl_path" ]] || [[ "$SIDEBARCTL_SOURCE" -nt "$sidebarctl_path" ]]; then
    cp "$SIDEBARCTL_SOURCE" "$sidebarctl_path"
    chmod +x "$sidebarctl_path"
  fi

  # Ensure local bin is in PATH for current process if we used ~/.local/bin
  if [[ "$install_dir" == "$HOME/.local/bin" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi

  echo "$sidebarctl_path"
}

# -------- Sidebar Sections Installation --------
install_sidebarsections() {
  command -v swift >/dev/null 2>&1 || {
    err "swift not found. Install Xcode Command Line Tools before running this.\n"
    return 2
  }

  local source_path="$DOTFILES_DIR/bin/sidebarsections.swift"
  if [[ ! -f "$source_path" ]]; then
    err "sidebarsections source not found at $source_path"
    return 2
  fi

  local install_dir
  install_dir="$(detect_install_dir)"
  mkdir -p "$install_dir"

  local script_path="$install_dir/sidebarsections"

  # Update the script if source is newer or script doesn't exist
  if [[ ! -x "$script_path" ]] || [[ "$source_path" -nt "$script_path" ]]; then
    cp "$source_path" "$script_path"
    chmod +x "$script_path"
  fi

  # Ensure local bin is in PATH for current process if we used ~/.local/bin
  if [[ "$install_dir" == "$HOME/.local/bin" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi

  echo "$script_path"
}

# -------- User-facing functions --------
configure_finder_favorites() {
  local sidebarctl
  sidebarctl="$(install_sidebarctl)"

  local icloud_path="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  local paths=(
    "$HOME"            # Home (shows as your username)
    "/Applications"
    "$HOME/Downloads"
  )

  if [[ -d "$icloud_path" ]]; then
    paths+=("$icloud_path")   # iCloud Drive
  fi

  if ! "$sidebarctl" --set "${paths[@]}"; then
    local sfl_path
    sfl_path="$("$sidebarctl" --path 2>/dev/null || true)"
    err "⚠️  sidebarctl could not update Finder sidebar (macOS likely blocked access to the favorites list)."
    [[ -n "$sfl_path" ]] && err "    SFL path: $sfl_path"
    err "    Fix: System Settings → Privacy & Security → Full Disk Access → enable your terminal/SSH daemon (e.g., Terminal, iTerm2, Cursor, /usr/libexec/sshd-keygen-wrapper), then rerun: ~/.dotfiles/finder.sh"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" >/dev/null 2>&1 || true
  fi
}

configure_sidebar_sections() {
  local sidebarsections
  sidebarsections="$(install_sidebarsections)" || {
    err "⚠️  Skipping sidebar sections configuration (sidebarsections unavailable)."
    return 0
  }

  # Hide Recents and Shared sections, disable Bonjour computers
  if ! "$sidebarsections" --all-hidden; then
    err "⚠️  sidebarsections could not hide Recents/Shared (Full Disk Access may be required)."
  fi
}

configure_finder_column_defaults() {
  defaults write com.apple.finder "FXPreferredViewStyle" -string "clmv"
}

reset_home_ds_store() {
  [[ "$RESET_DS_STORE" == "1" ]] || return 0
  
  # Only clean specific directories to avoid slow recursive search of ~/Library
  local dirs_to_clean=(
    "$HOME/Desktop"
    "$HOME/Documents"
    "$HOME/Downloads"
  )
  
  for dir in "${dirs_to_clean[@]}"; do
    [[ -d "$dir" ]] && find "$dir" -name ".DS_Store" -delete 2>/dev/null || true
  done
}

reload_finder_ui() {
  local sidebarctl_path
  sidebarctl_path="$(command -v sidebarctl || true)"

  if [[ -n "$sidebarctl_path" ]]; then
    if [[ "$FINDER_FORCE_RELOAD" == "1" ]]; then
      "$sidebarctl_path" --reload --force
    else
      "$sidebarctl_path" --reload
    fi
  else
    killall Finder || true
  fi
}

apply_finder_customizations() {
  configure_finder_favorites
  configure_sidebar_sections
  configure_finder_column_defaults
  reset_home_ds_store
  reload_finder_ui
}

# -------- Entry point --------
# You can either:
#   1) execute this script directly, or
#   2) source it and call apply_finder_customizations from another script.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  apply_finder_customizations
fi
