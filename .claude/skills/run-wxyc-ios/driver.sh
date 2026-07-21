#!/bin/bash
#
# driver.sh
# WXYC
#
# Agent driver for building, launching, and observing the WXYC iOS app in the
# iOS simulator. Fully headless: it never opens Simulator.app or sends host
# mouse/keyboard events, so it never steals Jake's cursor or window focus.
# Screenshots are the only observation channel. There is no synthetic tap
# support — if a screen can only be reached by navigating through the app,
# ask Jake to drive it (or hand him the exact steps) rather than automating
# input.
#
# Usage:
#   driver.sh build                 # xcodebuild for the simulator
#   driver.sh launch                # boot sim headlessly, install, launch the app
#   driver.sh screenshot <out.png>  # capture the device screen
#   driver.sh quit                  # terminate the app
#
# Created by Jake Bromberg on 07/18/26.
# Copyright © 2026 WXYC. All rights reserved.
#

set -euo pipefail

# iPhone 17 (iOS 27 runtime) — the only sim resolvable by xcodebuild as of 2026-07.
UDID="B49BE311-B868-4E8B-AE14-85C159CAD776"
SCHEME="WXYC"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

app_path() {
    # Resolve THIS checkout's DerivedData by WorkspacePath. Many WXYC-<hash>
    # dirs coexist (one per worktree); a wildcard + head -1 once installed a
    # week-old build from another worktree, which cost an hour of debugging a
    # "regression" that was just a stale binary. Also: Debug-maccatalyst/
    # WXYC.app exists too and will NOT install on an iPhone simulator.
    for d in "$HOME"/Library/Developer/Xcode/DerivedData/WXYC-*; do
        if [ "$(defaults read "$d/info" WorkspacePath 2>/dev/null)" = "$PROJECT_DIR/WXYC.xcodeproj" ]; then
            ls -d "$d/Build/Products/Debug-iphonesimulator/WXYC.app" 2>/dev/null
            return
        fi
    done
}

bundle_id() {
    defaults read "$(app_path)/Info" CFBundleIdentifier  # org.wxyc.iphoneappdebug for Debug
}

case "${1:-}" in
build)
    # -skipMacroValidation is required: macro fingerprint changes otherwise
    # trigger validation errors.
    xcodebuild -project "$PROJECT_DIR/WXYC.xcodeproj" -scheme "$SCHEME" \
        -destination "id=$UDID" -skipMacroValidation build
    ;;

launch)
    # Headless boot — no `open -a Simulator`, so no window ever appears and
    # nothing steals foreground focus. `simctl boot` errors if already booted;
    # that's fine, fall through to bootstatus either way.
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b
    APP="$(app_path)"
    [ -n "$APP" ] || { echo "No Debug-iphonesimulator build; run: driver.sh build" >&2; exit 1; }
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch --terminate-running-process "$UDID" "$(bundle_id)"
    ;;

screenshot)
    OUT="${2:?usage: driver.sh screenshot <out.png>}"
    xcrun simctl io "$UDID" screenshot "$OUT"
    ;;

quit)
    xcrun simctl terminate "$UDID" "$(bundle_id)" 2>/dev/null || true
    ;;

*)
    grep '^#   driver.sh' "$0" | sed 's/^# *//'
    exit 1
    ;;
esac
