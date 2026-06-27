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
    yq -r '.apps[] | select(((.manual // []) | length) > 0 and (.desired_state == "needs_login" or .desired_state == "needs_config" or .desired_state == "needs_permissions")) | [.priority, .id, .name, .desired_state] | @tsv' "$REGISTRY" |
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
    case "$app_id" in
        tailscale)
            verify_tailscale || verify_status=1
            ;;
        synology-drive)
            verify_synology_drive || verify_status=1
            ;;
        private-internet-access)
            verify_private_internet_access || verify_status=1
            ;;
    esac
    return "$verify_status"
}

verify_tailscale() {
    local expected_peer="mooses-macbook-server"
    local status_json

    echo "  Tailscale local status"
    if ! command -v tailscale >/dev/null 2>&1; then
        echo "    failed: missing tailscale CLI"
        return 1
    fi

    status_json="$(mktemp)"
    if ! tailscale status --json >"$status_json" 2>/dev/null; then
        rm -f "$status_json"
        echo "    failed: tailscale status is unavailable"
        return 1
    fi

    if ! python3 - "$expected_peer" "$status_json" <<'PY'
import json
import pathlib
import sys

expected_peer = sys.argv[1].casefold()
data = json.loads(pathlib.Path(sys.argv[2]).read_text())

if data.get("BackendState") != "Running":
    raise SystemExit("backend")

self_ips = data.get("Self", {}).get("TailscaleIPs") or []
if not self_ips:
    raise SystemExit("self-ip")

for peer in (data.get("Peer") or {}).values():
    names = [
        peer.get("HostName") or "",
        peer.get("DNSName") or "",
        peer.get("Name") or "",
    ]
    if any(expected_peer in name.casefold() for name in names):
        if peer.get("Online") is not True:
            raise SystemExit("peer-offline")
        if not peer.get("TailscaleIPs"):
            raise SystemExit("peer-ip")
        raise SystemExit(0)

raise SystemExit("missing-peer")
PY
    then
        rm -f "$status_json"
        echo "    failed: expected Tailscale running with online peer $expected_peer"
        return 1
    fi
    rm -f "$status_json"
    echo "    ok"

    echo "  Tailscale remote-control peer"
    if ! tailscale ping --c 1 --timeout=3s "$expected_peer" >/dev/null 2>&1; then
        echo "    failed: could not reach $expected_peer with tailscale ping"
        return 1
    fi
    echo "    ok"
}

verify_synology_drive() {
    local db_path="$HOME/Library/Application Support/SynologyDrive/data/db/sys.sqlite"
    local link_path="$HOME/SynologyDrive"
    local expected_target="$HOME/Library/CloudStorage/SynologyDrive-SynologyDrive"
    local link_target expected_count pref_count sql

    echo "  Synology Drive sync task"
    if [[ ! -f "$db_path" ]]; then
        echo "    failed: missing sync database"
        return 1
    fi
    if [[ ! -L "$link_path" ]]; then
        echo "    failed: missing SynologyDrive home symlink"
        return 1
    fi

    link_target="$(readlink "$link_path")"
    if [[ "$link_target" != "$expected_target" ]]; then
        echo "    failed: unexpected SynologyDrive symlink target"
        return 1
    fi

    sql="select count(*) from session_table where custom_session_name = 'SynologyDrive' and share_name = 'home' and remote_path = '/' and symbolic_link_path = '$link_path' and sync_folder = '$expected_target/' and is_mac_on_demand_sync_enable = 1 and is_mounted = 1 and status in (0, 1) and error = 0;"
    expected_count="$(sqlite3 "$db_path" "$sql")"
    if [[ "$expected_count" != "1" ]]; then
        echo "    failed: expected SynologyDrive task was not active and healthy"
        return 1
    fi

    echo "    ok"

    echo "  Synology Drive preferences"
    pref_count="$(sqlite3 "$db_path" "select count(*) from system_table where (key = 'enable_desktop_notification' and value = '0') or (key = 'use_black_white_icon' and value = '1');")"
    if [[ "$pref_count" != "2" ]]; then
        echo "    failed: expected file event notifications off and minimalist icon on"
        return 1
    fi

    echo "    ok"
}

verify_private_internet_access() {
    local settings_path="$HOME/Library/Preferences/com.privateinternetaccess.vpn/clientsettings.json"
    local protocol region allowlan requestportforward debuglogging

    echo "  Private Internet Access daemon preferences"
    if ! command -v piactl >/dev/null 2>&1; then
        echo "    failed: missing piactl"
        return 1
    fi

    protocol="$(piactl get protocol 2>/dev/null || true)"
    region="$(piactl get region 2>/dev/null || true)"
    allowlan="$(piactl get allowlan 2>/dev/null || true)"
    requestportforward="$(piactl get requestportforward 2>/dev/null || true)"
    debuglogging="$(piactl get debuglogging 2>/dev/null || true)"

    if [[ "$protocol" != "openvpn" || "$region" != "auto" || "$allowlan" != "true" || "$requestportforward" != "false" || "$debuglogging" != "false" ]]; then
        echo "    failed: expected openvpn, auto region, LAN allowed, no port forwarding, debug logging off"
        return 1
    fi
    echo "    ok"

    echo "  Private Internet Access client preferences"
    if [[ ! -f "$settings_path" ]]; then
        echo "    failed: missing clientsettings.json"
        return 1
    fi

    if ! python3 - "$settings_path" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {
    "connectOnLaunch": False,
    "dashboardFrame": "popup",
    "desktopNotifications": True,
    "iconSet": "auto",
    "regionSortKey": "latency",
    "themeName": "dark",
}

missing = {key: value for key, value in expected.items() if data.get(key) != value}
if missing:
    raise SystemExit(1)
PY
    then
        echo "    failed: expected no connect-on-launch, notifications on, system icon, dark theme, latency sort"
        return 1
    fi
    echo "    ok"
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
