#!/bin/bash
set -euo pipefail

LSREGISTER=${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}
INSTALLED=/Applications/Polc.app
BUNDLE_IDS='com\.stephenangeloni\.(Polc|Clop)'

registered_app_paths() {
    awk -v ids="^identifier: +$BUNDLE_IDS\$" '
        /^-{20,}/ { path = "" }
        /^path: / { path = $0; sub(/^path: +/, "", path); sub(/ \(0x[0-9a-f]+\)$/, "", path) }
        $0 ~ ids && path != "" { print path; path = "" }
    ' <<< "$1" | sort -u
}

dump=$("$LSREGISTER" -dump)
while IFS= read -r app; do
    [ "$app" = "$INSTALLED" ] && continue
    echo "Unregistering $app"
    "$LSREGISTER" -u "$app"
done < <(registered_app_paths "$dump")

/System/Library/CoreServices/pbs -update
