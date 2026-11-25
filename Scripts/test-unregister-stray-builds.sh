#!/bin/bash
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/unregister-stray-builds.sh"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
WORK=$(cd "$(mktemp -d -t polc-stray-test)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
failures=0

make_bundle() {
    mkdir -p "$1/Contents"
    cat > "$1/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.stephenangeloni.Polc</string>
<key>CFBundleName</key><string>Polc</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
    "$LSREGISTER" -f "$1"
    for _ in $(seq 10); do
        is_registered "$1" && return 0
        sleep 0.5
    done
    echo "could not register $1"
    exit 2
}

is_registered() {
    local dump
    dump=$("$LSREGISTER" -dump) || { echo "lsregister -dump failed"; exit 2; }
    grep -qE "^path: +$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g') \(0x" <<< "$dump"
}

check() {
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

test_deleted_bundle_does_not_stop_cleanup() {
    local deleted="$WORK/a-deleted/Polc.app" stray="$WORK/b-stray/Polc.app"
    make_bundle "$deleted"
    make_bundle "$stray"
    rm -rf "$WORK/a-deleted"

    "$SCRIPT" > "$WORK/out.txt" 2>&1
    local status=$?

    check "deleted bundle: script succeeds" "[ $status -eq 0 ]"
    check "deleted bundle: other stray copy is unregistered" "! is_registered '$stray'"
    check "deleted bundle: installed app stays registered" "is_registered /Applications/Polc.app"
}

test_unreadable_app_list_fails() {
    local stub="$WORK/failing-lsregister"
    printf '#!/bin/bash\n[ "$1" = -dump ] && exit 1\nexit 0\n' > "$stub"
    chmod +x "$stub"

    LSREGISTER="$stub" "$SCRIPT" > "$WORK/out.txt" 2>&1
    local status=$?

    check "unreadable app list: script fails" "[ $status -ne 0 ]"
}

test_deleted_bundle_does_not_stop_cleanup
test_unreadable_app_list_fails

[ $failures -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
