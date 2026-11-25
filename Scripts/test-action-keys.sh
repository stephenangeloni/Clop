#!/bin/bash
set -uo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d -t polc-action-keys)
trap 'rm -rf "$WORK"' EXIT
failures=0

swiftc -parse-as-library -o "$WORK/action-keys" "$SCRIPTS/action-keys.swift" "$SCRIPTS/../Polc/ActionKeys.swift" || exit 2

check() {
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

run() {
    "$WORK/action-keys" "$@" 2>&1
}

test_migration_keeps_todays_keys_and_switches() {
    check "migration: every action keeps its key and enabled ones stay on" \
        "[ \"\$(run migrate minus,c,a)\" = 'downscale=minus:on optimiseClipboard=c:on optimiseAggressively=a:on' ]"
    check "migration: an action whose key was not enabled is off" \
        "[ \"\$(run migrate c)\" = 'downscale=minus:off optimiseClipboard=c:on optimiseAggressively=a:off' ]"
    check "migration: no enabled keys turns every action off" \
        "[ \"\$(run migrate '')\" = 'downscale=minus:off optimiseClipboard=c:off optimiseAggressively=a:off' ]"
    check "migration: keys no action uses are ignored" \
        "[ \"\$(run migrate a,q,1)\" = 'downscale=minus:off optimiseClipboard=c:off optimiseAggressively=a:on' ]"
}

test_assigning_a_free_key_rebinds_only_that_action() {
    check "assign: a free key replaces the action's key and keeps its switch" \
        "[ \"\$(run assign c optimiseAggressively w)\" = 'downscale=minus:off optimiseClipboard=c:on optimiseAggressively=w:off' ]"
    check "assign: the action's own key is accepted unchanged" \
        "[ \"\$(run assign minus,c,a optimiseAggressively a)\" = 'downscale=minus:on optimiseClipboard=c:on optimiseAggressively=a:on' ]"
}

test_assigning_a_taken_key_is_refused() {
    check "assign: another action's key is refused and names that action" \
        "[ \"\$(run assign minus,c,a optimiseAggressively c)\" = 'taken by optimiseClipboard' ]"
    check "assign: a switched-off action's key is still refused" \
        "[ \"\$(run assign a optimiseAggressively c)\" = 'taken by optimiseClipboard' ]"
    check "assign: a resize number key is refused" \
        "[ \"\$(run assign minus,c,a optimiseAggressively 9)\" = 'taken by resize' ]"
}

test_pressing_a_key_finds_its_switched_on_action() {
    check "press: a switched-on action's key runs that action" "[ \"\$(run press minus,c,a c)\" = optimiseClipboard ]"
    check "press: a switched-off action's key runs nothing" "[ \"\$(run press minus,a c)\" = nothing ]"
    check "press: a key no action uses runs nothing" "[ \"\$(run press minus,c,a q)\" = nothing ]"
}

test_migration_keeps_todays_keys_and_switches
test_pressing_a_key_finds_its_switched_on_action
test_assigning_a_free_key_rebinds_only_that_action
test_assigning_a_taken_key_is_refused

[ $failures -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
