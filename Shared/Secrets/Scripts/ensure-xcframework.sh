#!/bin/bash
#
# ensure-xcframework.sh
#
# Checks if Secrets.xcframework needs to be (re)built and builds it if necessary.
# Intended to be called from an Xcode build phase.
#
# Rebuilds if:
#   - Secrets.xcframework doesn't exist
#   - Any source file is newer than the xcframework
#   - Package.swift is newer than the xcframework
#
# Environment:
#   Secrets are loaded from secrets.txt if environment variables aren't set.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCFRAMEWORK="$SECRETS_DIR/Secrets.xcframework"
SOURCES_DIR="$SECRETS_DIR/Sources/Secrets"
PACKAGE_SWIFT="$SECRETS_DIR/Package.swift"

log() {
    echo "[ensure-xcframework] $1"
}

# Check if xcframework exists
if [ ! -d "$XCFRAMEWORK" ]; then
    log "Secrets.xcframework not found, building..."
    "$SCRIPT_DIR/build-xcframework.sh"
    exit 0
fi

# Get xcframework modification time (use Info.plist as reference)
XCFRAMEWORK_REF="$XCFRAMEWORK/Info.plist"
if [ ! -f "$XCFRAMEWORK_REF" ]; then
    log "Secrets.xcframework appears corrupted (no Info.plist), rebuilding..."
    "$SCRIPT_DIR/build-xcframework.sh"
    exit 0
fi

XCFRAMEWORK_MTIME=$(stat -f %m "$XCFRAMEWORK_REF" 2>/dev/null || echo "0")
NEEDS_REBUILD=false

# Check Package.swift
if [ -f "$PACKAGE_SWIFT" ]; then
    PACKAGE_MTIME=$(stat -f %m "$PACKAGE_SWIFT")
    if [ "$PACKAGE_MTIME" -gt "$XCFRAMEWORK_MTIME" ]; then
        log "Package.swift is newer than xcframework"
        NEEDS_REBUILD=true
    fi
fi

# Check source files (including generated Secrets.swift)
if [ "$NEEDS_REBUILD" = false ] && [ -d "$SOURCES_DIR" ]; then
    for file in "$SOURCES_DIR"/*.swift; do
        if [ -f "$file" ]; then
            FILE_MTIME=$(stat -f %m "$file")
            if [ "$FILE_MTIME" -gt "$XCFRAMEWORK_MTIME" ]; then
                log "$(basename "$file") is newer than xcframework"
                NEEDS_REBUILD=true
                break
            fi
        fi
    done
fi

# Check build script itself
BUILD_SCRIPT="$SCRIPT_DIR/build-xcframework.sh"
if [ "$NEEDS_REBUILD" = false ] && [ -f "$BUILD_SCRIPT" ]; then
    SCRIPT_MTIME=$(stat -f %m "$BUILD_SCRIPT")
    if [ "$SCRIPT_MTIME" -gt "$XCFRAMEWORK_MTIME" ]; then
        log "build-xcframework.sh is newer than xcframework"
        NEEDS_REBUILD=true
    fi
fi

if [ "$NEEDS_REBUILD" = true ]; then
    log "Rebuilding Secrets.xcframework..."
    "$SCRIPT_DIR/build-xcframework.sh"
else
    log "Secrets.xcframework is up to date"
fi



