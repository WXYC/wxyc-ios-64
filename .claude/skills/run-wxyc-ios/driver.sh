#!/bin/bash
#
# driver.sh
# WXYC
#
# Agent driver for building, launching, and driving the WXYC iOS app in the
# iOS simulator. Screenshots are the observation channel; taps are injected
# as host-level mouse clicks mapped from device-pixel coordinates.
#
# Usage:
#   driver.sh build                 # xcodebuild for the simulator
#   driver.sh launch                # boot sim, install, launch the app
#   driver.sh screenshot <out.png>  # capture the device screen
#   driver.sh tap <x> <y>           # tap at DEVICE-PIXEL coords (as read off a screenshot)
#   driver.sh press <x> <y>         # 1s long-press (theme picker) at DEVICE-PIXEL coords
#   driver.sh swipe <x> <y> <x2> <y2>  # drag between DEVICE-PIXEL coords
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Device screen size in pixels (iPhone 17). Screenshots come out at this size,
# so tap coords are given in this space and mapped to host-screen points.
DEVICE_W=1206
DEVICE_H=2622
# Simulator window title-bar height in points (measured; see SKILL.md gotchas).
TITLEBAR=28

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
    xcrun simctl bootstatus "$UDID" -b
    open -a Simulator
    APP="$(app_path)"
    [ -n "$APP" ] || { echo "No Debug-iphonesimulator build; run: driver.sh build" >&2; exit 1; }
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch --terminate-running-process "$UDID" "$(bundle_id)"
    ;;

screenshot)
    OUT="${2:?usage: driver.sh screenshot <out.png>}"
    xcrun simctl io "$UDID" screenshot "$OUT"
    ;;

tap|press|swipe)
    X="${2:?usage: driver.sh tap|press|swipe <device-px-x> <device-px-y> [<x2> <y2>]}"
    Y="${3:?}"
    # Host window geometry {x, y, w, h} in screen points. Match the window by
    # device name: with several sims booted, "window 1" is whichever device was
    # focused last, and taps silently go to the wrong phone.
    # "iPhone 17 –" (en dash) so "iPhone 17 Pro Max – …" can never match.
    GEOM=$(osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of (first window whose name starts with "iPhone 17 –")' | tr -d ' ')
    IFS=',' read -r WX WY WW WH <<< "$GEOM"
    # The device view scales uniformly to fit the content height and is
    # centered horizontally, so map with one scale factor + a side margin.
    CONTENT_H=$((WH - TITLEBAR))
    SX=$(( WX + (WW - DEVICE_W * CONTENT_H / DEVICE_H) / 2 + X * CONTENT_H / DEVICE_H ))
    SY=$(( WY + TITLEBAR + Y * CONTENT_H / DEVICE_H ))
    osascript -e 'tell application "Simulator" to activate'
    sleep 0.3
    case "$1" in
    swipe)
        X2="${4:?}"; Y2="${5:?}"
        SX2=$(( WX + (WW - DEVICE_W * CONTENT_H / DEVICE_H) / 2 + X2 * CONTENT_H / DEVICE_H ))
        SY2=$(( WY + TITLEBAR + Y2 * CONTENT_H / DEVICE_H ))
        swift "$SCRIPT_DIR/click.swift" "$SX" "$SY" "$SX2" "$SY2"
        echo "swiped device ($X,$Y)->($X2,$Y2) as screen ($SX,$SY)->($SX2,$SY2)"
        ;;
    press)
        swift "$SCRIPT_DIR/click.swift" "$SX" "$SY" press
        echo "long-pressed device ($X,$Y) -> screen ($SX,$SY)"
        ;;
    *)
        swift "$SCRIPT_DIR/click.swift" "$SX" "$SY"
        echo "tapped device ($X,$Y) -> screen ($SX,$SY)"
        ;;
    esac
    ;;

quit)
    xcrun simctl terminate "$UDID" "$(bundle_id)" 2>/dev/null || true
    ;;

*)
    grep '^#   driver.sh' "$0" | sed 's/^# *//'
    exit 1
    ;;
esac
