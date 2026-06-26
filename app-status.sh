#!/usr/bin/env zsh

set -euo pipefail

DOTFILES="${0:A:h}"
REGISTRY="$DOTFILES/apps.yaml"

usage() {
    cat <<'EOF'
Usage: ./app-status.sh <command> [app-id]

Commands:
  summary          Show install and setup status for every tracked app
  next             Show manual setup queue, sorted by priority
  manual <app-id>  Show manual setup steps for one app
  verify <app-id>  Run repeatable verification commands for one app
  open <app-id>    Open an app by app_path
  ids              List tracked app ids
EOF
}

require_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        echo "Missing yq. Install packages first: brew bundle --file=Brewfile" >&2
        exit 1
    fi
}

yq_app() {
    local app_id="$1" expr="$2"
    APP_ID="$app_id" yq -r ".apps[] | select(.id == strenv(APP_ID)) | $expr" "$REGISTRY"
}

app_exists() {
    local app_id="$1"
    APP_ID="$app_id" yq -e '.apps[] | select(.id == strenv(APP_ID))' "$REGISTRY" >/dev/null
}

install_state() {
    local app_path="$1" command_name="$2"
    if [[ -n "$app_path" && "$app_path" != "null" ]]; then
        [[ -d "$app_path" ]] && print -r -- "installed" || print -r -- "missing"
        return
    fi
    if [[ -n "$command_name" && "$command_name" != "null" ]]; then
        command -v "$command_name" >/dev/null 2>&1 && print -r -- "installed" || print -r -- "missing"
        return
    fi
    print -r -- "unchecked"
}

summary() {
    local app_id priority name app_path command_name desired manual_count installed
    printf "%-4s %-24s %-12s %-16s %-8s %s\n" "prio" "app" "installed" "desired" "manual" "id"
    yq -r '.apps | sort_by(.priority)[] | .id' "$REGISTRY" |
        while IFS= read -r app_id; do
            priority="$(yq_app "$app_id" '.priority')"
            name="$(yq_app "$app_id" '.name')"
            app_path="$(yq_app "$app_id" '.app_path // ""')"
            command_name="$(yq_app "$app_id" '.command // ""')"
            desired="$(yq_app "$app_id" '.desired_state')"
            manual_count="$(yq_app "$app_id" '(.manual // []) | length')"
            installed="$(install_state "$app_path" "$command_name")"
            printf "%-4s %-24s %-12s %-16s %-8s %s\n" "$priority" "$name" "$installed" "$desired" "$manual_count" "$app_id"
        done
}

next_steps() {
    yq -r '.apps[] | select(((.manual // []) | length) > 0) | [.priority, .id, .name, .desired_state] | @tsv' "$REGISTRY" |
        sort -n |
        while IFS=$'\t' read -r priority app_id name desired; do
            printf "\n[%s] %s (%s)\n" "$priority" "$name" "$desired"
            APP_ID="$app_id" yq -r '.apps[] | select(.id == strenv(APP_ID)) | (.manual // [])[] | "  - " + .' "$REGISTRY"
        done
}

manual_steps() {
    local app_id="$1"
    app_exists "$app_id" || { echo "Unknown app id: $app_id" >&2; exit 1; }
    yq_app "$app_id" '.name' | sed 's/^/# /'
    yq_app "$app_id" '(.manual // [])[] | "- " + .'
}

verify_app() {
    local app_id="$1" cmd verify_status=0
    app_exists "$app_id" || { echo "Unknown app id: $app_id" >&2; exit 1; }
    yq_app "$app_id" '.name' | sed 's/^/Verifying /'
    while IFS= read -r cmd; do
        [[ -z "$cmd" || "$cmd" == "null" ]] && continue
        printf "  $ %s\n" "$cmd"
        if zsh -lc "$cmd"; then
            echo "    ok"
        else
            echo "    failed"
            verify_status=1
        fi
    done < <(yq_app "$app_id" '(.verify.commands // [])[]')
    return "$verify_status"
}

open_app() {
    local app_id="$1" app_path
    app_exists "$app_id" || { echo "Unknown app id: $app_id" >&2; exit 1; }
    app_path="$(yq_app "$app_id" '.app_path // ""')"
    if [[ -z "$app_path" || "$app_path" == "null" ]]; then
        echo "No app_path for $app_id" >&2
        exit 1
    fi
    open "$app_path"
}

ids() {
    yq -r '.apps[].id' "$REGISTRY"
}

main() {
    require_yq
    [[ -f "$REGISTRY" ]] || { echo "Missing registry: $REGISTRY" >&2; exit 1; }

    local command_name="${1:-summary}"
    case "$command_name" in
        summary) summary ;;
        next) next_steps ;;
        manual)
            [[ $# -eq 2 ]] || { usage; exit 2; }
            manual_steps "$2"
            ;;
        verify)
            [[ $# -eq 2 ]] || { usage; exit 2; }
            verify_app "$2"
            ;;
        open)
            [[ $# -eq 2 ]] || { usage; exit 2; }
            open_app "$2"
            ;;
        ids) ids ;;
        --help|-h|help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
