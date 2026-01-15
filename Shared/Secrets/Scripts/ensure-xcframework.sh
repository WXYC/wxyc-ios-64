#!/bin/bash
#
# ensure-xcframework.sh
#
# Checks if Secrets.xcframework exists and is valid.
# Intended to be called from an Xcode build phase.
#
# Note: Due to Xcode's sandboxed build phases, this script cannot rebuild
# the xcframework automatically. If the xcframework is missing or invalid,
# run build-xcframework.sh manually from the terminal.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCFRAMEWORK="$SECRETS_DIR/Secrets.xcframework"

log() {
    echo "[ensure-xcframework] $1"
}

error() {
    echo "[ensure-xcframework] ERROR: $1" >&2
    exit 1
}

# Check if xcframework exists
if [ ! -d "$XCFRAMEWORK" ]; then
    error "Secrets.xcframework not found. Run 'Shared/Secrets/Scripts/build-xcframework.sh' manually."
fi

# Check if xcframework is valid (has Info.plist)
if [ ! -f "$XCFRAMEWORK/Info.plist" ]; then
    error "Secrets.xcframework appears corrupted (no Info.plist). Run 'Shared/Secrets/Scripts/build-xcframework.sh' manually."
fi

log "Secrets.xcframework is present"
