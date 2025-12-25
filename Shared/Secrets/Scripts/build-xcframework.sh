#!/bin/bash
#
# build-xcframework.sh
#
# Builds the Secrets XCFramework for all required platforms.
# This pre-compiles the ObfuscateMacro/swift-syntax dependency to avoid
# rebuilding it on every app build.
#
# Usage:
#   ./build-xcframework.sh [path-to-secrets.txt]
#
# Environment variables can be set directly, or the script will source
# load-secrets-env.sh with the provided secrets file.
#
# Required environment variables:
#   POSTHOG_API_KEY
#   DISCOGS_API_KEY_V2_5
#   DISCOGS_API_SECRET_V2_5
#   SPOTIFY_CLIENT_ID
#   SPOTIFY_CLIENT_SECRET
#   REQUEST_O_MATIC

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$SECRETS_DIR"
XCFRAMEWORK_NAME="Secrets.xcframework"
BUILD_DIR="$SECRETS_DIR/.build-xcframework"
SECRETS_SWIFT="$SECRETS_DIR/Sources/Secrets/Secrets.swift"

log() {
    echo "[build-xcframework] $1"
}

error() {
    echo "[build-xcframework] ERROR: $1" >&2
    exit 1
}

cleanup() {
    log "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
}

# Load secrets from file if environment variables aren't already set
if [ -z "$POSTHOG_API_KEY" ] || [ -z "$DISCOGS_API_KEY_V2_5" ] || \
   [ -z "$DISCOGS_API_SECRET_V2_5" ] || [ -z "$SPOTIFY_CLIENT_ID" ] || \
   [ -z "$SPOTIFY_CLIENT_SECRET" ] || [ -z "$REQUEST_O_MATIC" ]; then
    SECRETS_FILE="${1:-}"
    if [ -n "$SECRETS_FILE" ] || [ -f "$SCRIPT_DIR/../../../secrets/secrets.txt" ]; then
        log "Loading secrets from file..."
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/load-secrets-env.sh" "$SECRETS_FILE"
    else
        error "Missing required environment variables and no secrets file found."
    fi
fi

# Verify required environment variables
missing_vars=()
[ -z "$POSTHOG_API_KEY" ] && missing_vars+=("POSTHOG_API_KEY")
[ -z "$DISCOGS_API_KEY_V2_5" ] && missing_vars+=("DISCOGS_API_KEY_V2_5")
[ -z "$DISCOGS_API_SECRET_V2_5" ] && missing_vars+=("DISCOGS_API_SECRET_V2_5")
[ -z "$SPOTIFY_CLIENT_ID" ] && missing_vars+=("SPOTIFY_CLIENT_ID")
[ -z "$SPOTIFY_CLIENT_SECRET" ] && missing_vars+=("SPOTIFY_CLIENT_SECRET")
[ -z "$REQUEST_O_MATIC" ] && missing_vars+=("REQUEST_O_MATIC")

if [ ${#missing_vars[@]} -gt 0 ]; then
    error "Missing required environment variables: ${missing_vars[*]}"
fi

# Generate Secrets.swift
log "Generating Secrets.swift..."
mkdir -p "$(dirname "$SECRETS_SWIFT")"
cat > "$SECRETS_SWIFT" << EOF
// This file is auto-generated. Do not edit.

import ObfuscateMacro
import Foundation

public struct Secrets {
    public static let posthogApiKey = #ObfuscatedString("${POSTHOG_API_KEY}")
    public static let discogsApiKeyV2_5 = #ObfuscatedString("${DISCOGS_API_KEY_V2_5}")
    public static let discogsApiSecretV2_5 = #ObfuscatedString("${DISCOGS_API_SECRET_V2_5}")
    public static let spotifyClientId = #ObfuscatedString("${SPOTIFY_CLIENT_ID}")
    public static let spotifyClientSecret = #ObfuscatedString("${SPOTIFY_CLIENT_SECRET}")
    public static let requestOMatic = #ObfuscatedString("${REQUEST_O_MATIC}")
}
EOF
log "Generated Secrets.swift"

# Clean previous builds
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_DIR/$XCFRAMEWORK_NAME"
mkdir -p "$BUILD_DIR"

cd "$SECRETS_DIR"

# Build for each platform using swift build
# Triples: ios-arm64, ios-arm64-simulator, watchos-arm64, watchos-arm64-simulator
PLATFORMS=(
    "arm64-apple-ios"
    "arm64-apple-ios-simulator"
    "arm64-apple-watchos"
    "arm64-apple-watchos-simulator"
)

FRAMEWORK_PATHS=()

log "Building for all platforms..."

for triple in "${PLATFORMS[@]}"; do
    log "Building for $triple..."

    swift build \
        --triple "$triple" \
        --configuration release \
        --build-path "$BUILD_DIR/$triple" \
        -Xswiftc -enable-library-evolution \
        -Xswiftc -emit-module-interface \
        2>&1 | grep -E "^(Build|Compiling|error:|warning:)" || true

    # Find the built framework
    FRAMEWORK_PATH="$BUILD_DIR/$triple/release/Secrets.framework"

    # For Swift packages, we need to construct the framework from the build products
    PRODUCTS_DIR="$BUILD_DIR/$triple/release"

    if [ -f "$PRODUCTS_DIR/libSecrets.a" ] || [ -f "$PRODUCTS_DIR/Secrets.o" ]; then
        log "Creating framework structure for $triple..."

        FRAMEWORK_DIR="$BUILD_DIR/frameworks/$triple/Secrets.framework"
        mkdir -p "$FRAMEWORK_DIR/Modules/Secrets.swiftmodule"

        # Copy the binary
        if [ -f "$PRODUCTS_DIR/libSecrets.a" ]; then
            cp "$PRODUCTS_DIR/libSecrets.a" "$FRAMEWORK_DIR/Secrets"
        elif [ -f "$PRODUCTS_DIR/Secrets.o" ]; then
            # Link into a static library if needed
            ar rcs "$FRAMEWORK_DIR/Secrets" "$PRODUCTS_DIR/Secrets.o"
        fi

        # Copy Swift module interface files
        if [ -d "$PRODUCTS_DIR/Secrets.build" ]; then
            find "$PRODUCTS_DIR/Secrets.build" -name "*.swiftinterface" -exec cp {} "$FRAMEWORK_DIR/Modules/Secrets.swiftmodule/" \;
            find "$PRODUCTS_DIR/Secrets.build" -name "*.swiftmodule" -exec cp {} "$FRAMEWORK_DIR/Modules/Secrets.swiftmodule/" \;
            find "$PRODUCTS_DIR/Secrets.build" -name "*.swiftdoc" -exec cp {} "$FRAMEWORK_DIR/Modules/Secrets.swiftmodule/" \;
        fi

        # Create module.modulemap
        cat > "$FRAMEWORK_DIR/Modules/module.modulemap" << 'MODULEMAP'
framework module Secrets {
    header "Secrets-Swift.h"
    requires objc
}
MODULEMAP

        # Create umbrella header
        cat > "$FRAMEWORK_DIR/Secrets-Swift.h" << 'HEADER'
// Secrets umbrella header
HEADER

        # Create Info.plist
        cat > "$FRAMEWORK_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Secrets</string>
    <key>CFBundleIdentifier</key>
    <string>org.wxyc.Secrets</string>
    <key>CFBundleName</key>
    <string>Secrets</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

        FRAMEWORK_PATHS+=("-framework" "$FRAMEWORK_DIR")
        log "Created framework for $triple"
    else
        log "Warning: Could not find build products for $triple"
        ls -la "$PRODUCTS_DIR" 2>/dev/null || true
    fi
done

# Check if we have any frameworks to bundle
if [ ${#FRAMEWORK_PATHS[@]} -eq 0 ]; then
    error "No frameworks were built successfully"
fi

# Create XCFramework
log "Creating XCFramework..."
xcodebuild -create-xcframework \
    "${FRAMEWORK_PATHS[@]}" \
    -output "$OUTPUT_DIR/$XCFRAMEWORK_NAME" 2>&1 || {
        log "XCFramework creation failed, checking what we have..."
        ls -laR "$BUILD_DIR/frameworks/" 2>/dev/null || true
        error "Failed to create XCFramework"
    }

if [ ! -d "$OUTPUT_DIR/$XCFRAMEWORK_NAME" ]; then
    error "Failed to create XCFramework"
fi

log "Created $XCFRAMEWORK_NAME successfully"

# Cleanup
cleanup

log "XCFramework build complete: $OUTPUT_DIR/$XCFRAMEWORK_NAME"
log ""
log "The Secrets package will now automatically use the XCFramework."
