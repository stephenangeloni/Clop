#!/bin/bash
set -uo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
WORK=$(cd "$(mktemp -d -t polc-folder-merge)" && pwd -P)
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT
failures=0

swiftc -parse-as-library -o "$WORK/merge-folders" "$SCRIPTS/merge-folders.swift" "$SCRIPTS/../Polc/FolderMerge.swift" || exit 2

check() {
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

merge() {
    "$WORK/merge-folders" "$1" "$2" > "$WORK/out.txt" 2>&1
}

test_vacant_destination_receives_whole_folder() {
    local dir="$WORK/vacant"
    mkdir -p "$dir/Clop/backups"
    echo clop > "$dir/Clop/backups/a.png"

    merge "$dir/Clop" "$dir/Polc"
    local status=$?

    check "vacant destination: merge succeeds" "[ $status -eq 0 ]"
    check "vacant destination: backup is in Polc" "[ \"\$(cat '$dir/Polc/backups/a.png')\" = clop ]"
    check "vacant destination: Clop folder is gone" "[ ! -e '$dir/Clop' ]"
}

test_existing_destination_receives_contents() {
    local dir="$WORK/existing"
    mkdir -p "$dir/Clop/backups" "$dir/Polc/backups"
    echo clop > "$dir/Clop/backups/a.png"
    echo clop > "$dir/Clop/same.txt"
    echo polc > "$dir/Polc/same.txt"
    echo polc > "$dir/Polc/backups/b.png"

    merge "$dir/Clop" "$dir/Polc"
    local status=$?

    check "existing destination: merge succeeds" "[ $status -eq 0 ]"
    check "existing destination: Clop backup is in Polc" "[ \"\$(cat '$dir/Polc/backups/a.png')\" = clop ]"
    check "existing destination: Polc backup is untouched" "[ \"\$(cat '$dir/Polc/backups/b.png')\" = polc ]"
    check "existing destination: Polc file is not overwritten" "[ \"\$(cat '$dir/Polc/same.txt')\" = polc ]"
    check "existing destination: clashing Clop file is kept" "[ \"\$(cat '$dir/Clop/same.txt')\" = clop ]"

    merge "$dir/Clop" "$dir/Polc"
    status=$?

    check "existing destination: second run succeeds" "[ $status -eq 0 ]"
    check "existing destination: second run changes nothing" "[ \"\$(cat '$dir/Clop/same.txt')\" = clop ] && [ \"\$(cat '$dir/Polc/same.txt')\" = polc ] && [ -f '$dir/Polc/backups/a.png' ]"
}

test_failed_move_is_reported() {
    local dir="$WORK/readonly"
    mkdir -p "$dir/Clop" "$dir/Polc"
    echo clop > "$dir/Clop/a.png"
    chmod 555 "$dir/Polc"

    merge "$dir/Clop" "$dir/Polc"
    local status=$?
    chmod 755 "$dir/Polc"

    check "failed move: merge fails" "[ $status -ne 0 ]"
    check "failed move: Clop file is kept" "[ \"\$(cat '$dir/Clop/a.png')\" = clop ]"
}

test_missing_source_is_a_no_op() {
    local dir="$WORK/missing"
    mkdir -p "$dir/Polc"

    merge "$dir/Clop" "$dir/Polc"
    local status=$?

    check "missing source: merge succeeds" "[ $status -eq 0 ]"
}

test_vacant_destination_receives_whole_folder
test_existing_destination_receives_contents
test_failed_move_is_reported
test_missing_source_is_a_no_op

[ $failures -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
