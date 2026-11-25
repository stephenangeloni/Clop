#!/bin/bash
set -uo pipefail

APP=com.stephenangeloni.Polc
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d -t polc-settings-ui)
trap 'rm -rf "$WORK"' EXIT
failures=0

pgrep -qf "/Applications/Polc.app/Contents/MacOS/Polc" || { echo "Polc must be running from /Applications"; exit 2; }
swiftc -O -o "$WORK/recognise-text" "$SCRIPTS/recognise-text.swift" || exit 2

settings_window_id() {
    local windows
    windows=$(orca computer list-windows --app "$APP" --json) || { echo "orca could not list Polc's windows" >&2; exit 2; }
    python3 -I -c 'import json,sys; print(next((w["id"] for w in json.load(sys.stdin)["result"]["windows"] if w["title"] == "Settings"), ""))' <<< "$windows"
}

settings_text() {
    local state
    state=$(orca computer get-app-state --app "$APP" --window-id "$(settings_window_id)" --json) || return 1
    "$WORK/recognise-text" "$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["result"]["screenshot"]["path"])' <<< "$state")"
}

shows_within() {
    local seconds=$1 text=$2
    for _ in $(seq "$seconds"); do
        settings_text | grep -qF "$text" && return 0
        sleep 1
    done
    return 1
}

open_link() {
    open -g "$1"
    orca computer wait --app "$APP" --window-title Settings --timeout 10000 --json > /dev/null || { echo "Settings did not open for $1"; exit 2; }
}

close_settings() {
    local index
    index=$(orca computer get-app-state --app "$APP" --window-id "$(settings_window_id)" --query "close button" --no-screenshot --json |
        python3 -I -c 'import json,re,sys; print(re.search(r"(\d+) close button", json.load(sys.stdin)["result"]["snapshot"]["treeText"]).group(1))')
    orca computer click --app "$APP" --element-index "$index" --no-screenshot --json > /dev/null
    for _ in $(seq 5); do
        [ -z "$(settings_window_id)" ] && return 0
        sleep 1
    done
    echo "Settings did not close" >&2
    exit 2
}

check() {
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

test_sidebar_shows_full_names() {
    open_link "polc://settings/general"
    local text
    text=$(settings_text)
    check "sidebar shows Keyboard Shortcuts in full" "grep -qF 'Keyboard Shortcuts' <<< \"\$text\""
    check "sidebar shows Shortcuts & Automation in full" "grep -qF 'Shortcuts & Automation' <<< \"\$text\""
}

test_link_from_another_tab_scrolls_to_its_section() {
    close_settings
    open_link "polc://settings/results"
    check "Results tab opens before the link" "shows_within 5 'onto a global zone to optimise them'"
    open_link "polc://settings/automation"
    check "link from another tab scrolls to Automation" "shows_within 5 'Automatically run actions'"
}

test_sidebar_shows_full_names
test_link_from_another_tab_scrolls_to_its_section

[ $failures -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
