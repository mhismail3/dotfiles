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
    local rows priority app_id name desired
    rows="$(yq -r '.apps[] | select(((.manual // []) | length) > 0 and (.desired_state == "needs_login" or .desired_state == "needs_config" or .desired_state == "needs_permissions")) | [.priority, .id, .name, .desired_state] | @tsv' "$REGISTRY" | sed '/^$/d' | sort -n)"

    if [[ -z "$rows" ]]; then
        echo "No active app setup steps."
        return 0
    fi

    printf "%s\n" "$rows" |
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
        docker)
            verify_docker || verify_status=1
            ;;
        private-internet-access)
            verify_private_internet_access || verify_status=1
            ;;
        logi-options-plus)
            verify_logi_options_plus || verify_status=1
            ;;
        folder-peek)
            verify_folder_peek || verify_status=1
            ;;
        qbittorrent)
            verify_qbittorrent || verify_status=1
            ;;
    esac
    return "$verify_status"
}

verify_tailscale() {
    local expected_peer="mooses-macbook-server"
    local display_name="Moose's MacBook Server"
    local screen_sharing_pref="$HOME/Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences/com.apple.ScreenSharing.plist"
    local screen_sharing_location="$HOME/Library/Containers/com.apple.ScreenSharing/Data/Library/Application Support/Screen Sharing/$display_name.vncloc"
    local screen_sharing_link="$HOME/.local/share/dotfiles/remote-control/Mooses MacBook Server.vncloc"
    local launcher="$HOME/.local/bin/screen-share-macbook-server"
    local taildrive_share_name="moose"
    local taildrive_share_path="$HOME"
    local taildrive_mount_point="$HOME/Taildrive"
    local taildrive_config="$HOME/.local/share/dotfiles/taildrive/config.json"
    local taildrive_opener="$HOME/.local/bin/open-taildrive"
    local taildrive_peer_opener="$HOME/.local/bin/open-taildrive-server"
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

    local peer_ip
    if ! peer_ip="$(python3 - "$expected_peer" "$status_json" <<'PY'
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
        ips = peer.get("TailscaleIPs") or []
        if not ips:
            raise SystemExit("peer-ip")
        print(ips[0])
        raise SystemExit(0)

raise SystemExit("missing-peer")
PY
)"; then
        rm -f "$status_json"
        echo "    failed: expected Tailscale running with online peer $expected_peer"
        return 1
    fi
    if [[ -z "$peer_ip" ]]; then
        rm -f "$status_json"
        echo "    failed: expected Tailscale IP for $expected_peer"
        return 1
    fi
    echo "    ok"

    echo "  Tailscale Taildrive capabilities"
    if ! python3 - "$status_json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
self_node = data.get("Self") or {}
caps = set(self_node.get("Capabilities") or [])
missing = {"drive:share", "drive:access"} - caps
if missing:
    raise SystemExit("missing-cap")
if self_node.get("NoFileSharingReason"):
    raise SystemExit("file-sharing-disabled")
PY
    then
        rm -f "$status_json"
        echo "    failed: expected drive:share and drive:access capabilities"
        return 1
    fi
    echo "    ok"
    rm -f "$status_json"

    echo "  Tailscale remote-control peer"
    if ! tailscale ping --c 1 --timeout=3s "$expected_peer" >/dev/null 2>&1; then
        echo "    failed: could not reach $expected_peer with tailscale ping"
        return 1
    fi
    echo "    ok"

    echo "  Tailscale Screen Sharing port"
    if ! nc -vz -G 3 "$expected_peer" 5900 >/dev/null 2>&1; then
        echo "    failed: Screen Sharing port 5900 is not reachable on $expected_peer"
        return 1
    fi
    echo "    ok"

    echo "  Screen Sharing native connection"
    if [[ ! -f "$screen_sharing_pref" ]]; then
        echo "    failed: missing $screen_sharing_pref"
        return 1
    fi
    if ! python3 - "$screen_sharing_pref" "$expected_peer" "$display_name" <<'PY'
import pathlib
import plistlib
import sys

pref_path = pathlib.Path(sys.argv[1])
expected_peer = sys.argv[2]
display_name = sys.argv[3]
expected_url = f"vnc://{expected_peer}"

prefs = plistlib.loads(pref_path.read_bytes())

def decode(value):
    if isinstance(value, bytes):
        return plistlib.loads(value)
    return value

store = decode(prefs.get("connectionsStore"))
if not isinstance(store, dict):
    raise SystemExit("missing-store")

found_id = None
for connection_id, detail in (store.get("connectionDetails") or {}).items():
    params = detail.get("connectionParameters") or {}
    network = ((params.get("networkAddress") or {}).get("_0")) or {}
    if (
        network.get("address") == expected_peer
        and network.get("port") == 5900
        and network.get("displayName") == display_name
    ):
        found_id = connection_id
        break

if not found_id:
    raise SystemExit("missing-connection")

recent_ids = decode(prefs.get("recentConnectionIDs"))
if not isinstance(recent_ids, list) or found_id not in recent_ids:
    raise SystemExit("missing-recent")

session_state = ((store.get("sessionMetadatas") or {}).get(found_id) or {}).get("sessionState") or {}
restoration = session_state.get("restorationAttributes") or {}
if session_state.get("URL") != expected_url and restoration.get("targetAddress") != expected_url:
    raise SystemExit("missing-session-url")
PY
    then
        echo "    failed: expected native Screen Sharing connection for $expected_peer"
        return 1
    fi
    echo "    ok"

    echo "  Screen Sharing location and launcher"
    if [[ ! -f "$screen_sharing_location" ]]; then
        echo "    failed: missing $screen_sharing_location"
        return 1
    fi
    if ! python3 - "$screen_sharing_location" "vnc://$expected_peer" <<'PY'
import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
expected_url = sys.argv[2]
data = plistlib.loads(path.read_bytes())
if data.get("URL") != expected_url:
    raise SystemExit(1)
PY
    then
        echo "    failed: Screen Sharing location does not target vnc://$expected_peer"
        return 1
    fi
    if [[ ! -L "$screen_sharing_link" || "$(readlink "$screen_sharing_link")" != "$screen_sharing_location" ]]; then
        echo "    failed: derived Screen Sharing symlink is missing or stale"
        return 1
    fi
    if [[ ! -x "$launcher" ]]; then
        echo "    failed: missing executable $launcher"
        return 1
    fi
    echo "    ok"

    echo "  Tailscale app preferences"
    if [[ "$(defaults read io.tailscale.ipn.macsys TailscaleStartOnLogin 2>/dev/null || true)" != "1" ]]; then
        echo "    failed: expected Launch Tailscale at login enabled"
        return 1
    fi
    if [[ "$(defaults read io.tailscale.ipn.macsys HideDockIcon 2>/dev/null || true)" != "1" ]]; then
        echo "    failed: expected Hide Dock Icon enabled"
        return 1
    fi
    if ! osascript -e 'tell application "System Events" to get exists login item "Tailscale"' 2>/dev/null | grep -q true; then
        echo "    failed: expected Tailscale login item"
        return 1
    fi
    echo "    ok"

    echo "  Taildrive user-folder share"
    if [[ "$(defaults read io.tailscale.ipn.macsys FileSharingConfiguration 2>/dev/null || true)" != "show" ]]; then
        echo "    failed: expected Tailscale File Sharing UI enabled"
        return 1
    fi
    local shares_json
    if ! shares_json="$(tailscale debug localapi GET /localapi/v0/drive/shares 2>/dev/null)"; then
        echo "    failed: could not read Taildrive shares from Tailscale LocalAPI"
        return 1
    fi
    if ! python3 - "$taildrive_share_name" "$taildrive_share_path" "$shares_json" <<'PY'
import json
import pathlib
import base64
import sys

expected_name = sys.argv[1]
expected_path = str(pathlib.Path(sys.argv[2]))
shares = json.loads(sys.argv[3] or "[]") or []

for share in shares:
    if share.get("name") == expected_name and str(pathlib.Path(share.get("path", ""))) == expected_path:
        bookmark = share.get("bookmarkData")
        if not isinstance(bookmark, str) or not bookmark:
            raise SystemExit(1)
        base64.b64decode(bookmark)
        raise SystemExit(0)

raise SystemExit(1)
PY
    then
        echo "    failed: missing app-visible Taildrive share $taildrive_share_name -> $taildrive_share_path"
        return 1
    fi
    echo "    ok"

    echo "  Taildrive Finder access"
    if [[ ! -d "$taildrive_mount_point" ]]; then
        echo "    failed: missing Taildrive mount point $taildrive_mount_point"
        return 1
    fi
    if [[ ! -x "$taildrive_opener" || ! -x "$taildrive_peer_opener" ]]; then
        echo "    failed: missing open-taildrive launchers"
        return 1
    fi
    if [[ ! -f "$taildrive_config" ]]; then
        echo "    failed: missing Taildrive Finder config"
        return 1
    fi
    if ! python3 - "$taildrive_config" "$expected_peer" <<'PY'
import json
import pathlib
import sys
import urllib.request
import xml.etree.ElementTree as ET

config = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected_peer = sys.argv[2].casefold()
base_url = config.get("base_url")
if base_url != "http://100.100.100.100:8080/":
    raise SystemExit("base-url")
if not config.get("mount_point"):
    raise SystemExit("mount-point")

request = urllib.request.Request(base_url, method="PROPFIND", headers={"Depth": "1"})
with urllib.request.urlopen(request, timeout=5) as response:
    ET.fromstring(response.read())

peer_href = config.get("peer_href") or ""
if expected_peer not in peer_href.casefold():
    raise SystemExit("peer")
PY
    then
        echo "    failed: expected Taildrive WebDAV root and home-server path"
        return 1
    fi
    if mount | grep -F " on $taildrive_mount_point (" | grep -F "webdav" >/dev/null; then
        echo "    ok: mounted"
    else
        echo "    ok: launchers configured; not currently mounted"
    fi
}

verify_docker() {
    local settings_path="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
    local preferences_domain="com.electron.dockerdesktop"
    local status_item_visible

    echo "  Docker Desktop settings store"
    if [[ ! -f "$settings_path" ]]; then
        echo "    failed: missing settings-store.json"
        return 1
    fi

    if ! python3 - "$settings_path" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {
    "AutoStart": False,
    "UseContainerdSnapshotter": True,
}
if any(data.get(key) != value for key, value in expected.items()):
    raise SystemExit(1)
PY
    then
        echo "    failed: expected AutoStart=false and UseContainerdSnapshotter=true"
        return 1
    fi
    echo "    ok"

    echo "  Docker Desktop menu bar status item"
    status_item_visible="$(defaults read "$preferences_domain" "NSStatusItem Visible Item-0" 2>/dev/null || true)"
    if [[ "$status_item_visible" != "0" ]]; then
        echo "    failed: expected NSStatusItem Visible Item-0=false in $preferences_domain"
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

verify_logi_options_plus() {
    local app_support="$HOME/Library/Application Support/LogiOptionsPlus"
    local permissions_path="$app_support/permissions.json"
    local config_path="$app_support/config.json"
    local settings_path="$app_support/settings.db"

    echo "  Logi Options+ onboarding and privacy baseline"
    if [[ ! -f "$permissions_path" || ! -f "$config_path" || ! -f "$settings_path" ]]; then
        echo "    failed: missing Logi Options+ app support files"
        return 1
    fi

    if ! python3 - "$permissions_path" "$config_path" "$settings_path" <<'PY'
import json
import pathlib
import sqlite3
import sys

permissions_path, config_path, settings_path = map(pathlib.Path, sys.argv[1:])

permissions = json.loads(permissions_path.read_text())
if permissions.get("macOSPermissionsGranted") is not True:
    raise SystemExit("permissions")

config = json.loads(config_path.read_text()).get("settings") or {}
expected_config = {
    "appOnboardingOpened": True,
    "permissionScreenStatus": "permissionSuccess",
    "isSentryEnabled": False,
}
if any(config.get(key) != value for key, value in expected_config.items()):
    raise SystemExit("config")

with sqlite3.connect(settings_path) as con:
    row = con.execute("select file from data order by _id desc limit 1").fetchone()
if not row:
    raise SystemExit("settings-missing")

settings = json.loads(row[0])
expected_settings = {
    "device_recommendation_enabled": False,
    "star_rating_notification": False,
    "low_battery_notifications_enabled": True,
    "use_system_theme": True,
    "first_time_run": False,
}
if any(settings.get(key) != value for key, value in expected_settings.items()):
    raise SystemExit("settings")
PY
    then
        echo "    failed: expected onboarding complete, permissions granted, analytics quiet, recommendations off, star-rating prompts off"
        return 1
    fi

    echo "    ok"
}

verify_folder_peek() {
    local expected_folder="$HOME/Library/CloudStorage/SynologyDrive-SynologyDrive/[Photos]/Screenshots"
    local pref_path="$HOME/Library/Containers/com.sindresorhus.Folder-Peek/Data/Library/Preferences/com.sindresorhus.Folder-Peek.plist"

    echo "  Folder Peek login item and folder bookmark"
    if [[ ! -d "$expected_folder" ]]; then
        echo "    failed: missing expected Screenshots folder"
        return 1
    fi
    if [[ ! -f "$pref_path" ]]; then
        echo "    failed: missing Folder Peek preferences"
        return 1
    fi
    if ! osascript -e 'tell application "System Events" to exists login item "Folder Peek"' 2>/dev/null | grep -qx "true"; then
        echo "    failed: Folder Peek login item is not enabled"
        return 1
    fi

    if ! python3 - "$pref_path" <<'PY'
import base64
import json
import pathlib
import plistlib
import sys

data = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
folders = data.get("folders") or []
expected_components = [
    b"SynologyDrive-SynologyDrive",
    b"[Photos]",
    b"Screenshots",
]

for raw_folder in folders:
    folder = json.loads(raw_folder)
    bookmark = base64.b64decode(folder.get("urlBookmark") or "")
    if (
        folder.get("isVisible") is True
        and folder.get("showFolderContents") is True
        and folder.get("keepFoldersOnTop") is True
        and all(component in bookmark for component in expected_components)
    ):
        raise SystemExit(0)

raise SystemExit(1)
PY
    then
        echo "    failed: expected visible Synology [Photos]/Screenshots folder bookmark"
        return 1
    fi

    echo "    ok"
}

verify_qbittorrent() {
    local config_path="$HOME/.config/qBittorrent/qBittorrent.ini"
    local download_dir="$HOME/Downloads/qBittorrent"
    local incomplete_dir="$download_dir/incomplete"

    echo "  qBittorrent preferences"
    if [[ ! -f "$config_path" ]]; then
        echo "    failed: missing qBittorrent.ini"
        return 1
    fi
    if [[ ! -d "$download_dir" || ! -d "$incomplete_dir" ]]; then
        echo "    failed: missing qBittorrent download directories"
        return 1
    fi
    if osascript -e 'tell application "System Events" to exists login item "qBittorrent"' 2>/dev/null | grep -qx "true"; then
        echo "    failed: qBittorrent should not be a login item"
        return 1
    fi

    if ! python3 - "$config_path" "$download_dir" "$incomplete_dir" <<'PY'
import configparser
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
download_dir = str(pathlib.Path(sys.argv[2]))
incomplete_dir = str(pathlib.Path(sys.argv[3]))

config = configparser.RawConfigParser(delimiters=("=",), strict=False)
config.optionxform = str
config.read(config_path)

expected = {
    ("BitTorrent", r"Session\AddExtensionToIncompleteFiles"): "true",
    ("BitTorrent", r"Session\AddTorrentStopped"): "true",
    ("BitTorrent", r"Session\AnonymousModeEnabled"): "true",
    ("BitTorrent", r"Session\DefaultSavePath"): download_dir,
    ("BitTorrent", r"Session\LSDEnabled"): "false",
    ("BitTorrent", r"Session\TempPath"): incomplete_dir,
    ("BitTorrent", r"Session\TempPathEnabled"): "true",
    ("Core", "AutoDeleteAddedTorrentFile"): "Never",
    ("Network", "PortForwardingEnabled"): "false",
    ("Network", r"Proxy\Type"): "None",
    ("Preferences", r"Advanced\AnonymousMode"): "true",
    ("Preferences", r"Advanced\trackerPortForwarding"): "false",
    ("Preferences", r"Connection\UPnP"): "false",
    ("Preferences", r"Downloads\SavePath"): download_dir,
    ("Preferences", r"Downloads\TempPath"): incomplete_dir,
    ("Preferences", r"Downloads\TempPathEnabled"): "true",
    ("Preferences", r"MailNotification\enabled"): "false",
    ("Preferences", r"WebUI\Enabled"): "false",
    ("Preferences", r"WebUI\UseUPnP"): "false",
}

for (section, key), value in expected.items():
    if not config.has_option(section, key):
        raise SystemExit(f"missing {section}.{key}")
    if config.get(section, key) != value:
        raise SystemExit(f"unexpected {section}.{key}")

if config.get("LegalNotice", "Accepted", fallback="false") != "true":
    raise SystemExit("legal-notice")
PY
    then
        echo "    failed: expected local downloads, torrents added stopped, anonymous mode on, UPnP/WebUI off, legal notice accepted"
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
