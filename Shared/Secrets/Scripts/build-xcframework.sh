#!/bin/bash
#
# build-xcframework.sh
#
# Builds the Secrets XCFramework for all required platforms.
# Uses SecretsFramework.xcodeproj to avoid swift-algorithms library evolution
# compatibility issues with Swift 6.2.
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
SECRETS_SWIFT="$SECRETS_DIR/Sources/Secrets/Secrets.swift"
XCODEPROJ="$SECRETS_DIR/SecretsFramework.xcodeproj"

log() {
    echo "[build-xcframework] $1"
}

error() {
    echo "[build-xcframework] ERROR: $1" >&2
    exit 1
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

# Verify Xcode project exists
if [ ! -d "$XCODEPROJ" ]; then
    error "SecretsFramework.xcodeproj not found at $XCODEPROJ"
fi

# Generate Secrets.swift
log "Generating Secrets.swift..."
mkdir -p "$(dirname "$SECRETS_SWIFT")"
cat > "$SECRETS_SWIFT" << EOF
// This file is auto-generated. Do not edit.

@_implementationOnly import ObfuscateMacro
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

# Remove old xcframework
rm -rf "$OUTPUT_DIR/$XCFRAMEWORK_NAME"

# Define platforms to build
PLATFORMS=(
    "generic/platform=iOS"
    "generic/platform=iOS Simulator"
    "generic/platform=watchOS"
    "generic/platform=watchOS Simulator"
)

PLATFORM_DIRS=(
    "Release-iphoneos"
    "Release-iphonesimulator"
    "Release-watchos"
    "Release-watchsimulator"
)

log "Building for all platforms..."

cd "$SECRETS_DIR"

for i in "${!PLATFORMS[@]}"; do
    platform="${PLATFORMS[$i]}"
    log "Building for $platform..."

    xcodebuild -project "$XCODEPROJ" \
        -scheme Secrets \
        -destination "$platform" \
        -configuration Release \
        SKIP_INSTALL=NO \
        -quiet \
        2>&1 | grep -E "^(error:|warning:.*Secrets)" || true
done

log "All platforms built successfully"

# Find DerivedData path for this project
# xcodebuild uses ~/Library/Developer/Xcode/DerivedData/ProjectName-hash/
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
DERIVED_DATA=$(find "$DERIVED_DATA_BASE" -maxdepth 1 -name "SecretsFramework-*" -type d 2>/dev/null | head -1)

if [ -z "$DERIVED_DATA" ]; then
    error "Could not find SecretsFramework DerivedData directory"
fi

BUILD_PRODUCTS="$DERIVED_DATA/Build/Products"

if [ ! -d "$BUILD_PRODUCTS" ]; then
    error "Could not find build products at $BUILD_PRODUCTS"
fi

# Verify all frameworks exist
FRAMEWORK_ARGS=()
for dir in "${PLATFORM_DIRS[@]}"; do
    framework_path="$BUILD_PRODUCTS/$dir/Secrets.framework"
    if [ ! -d "$framework_path" ]; then
        error "Framework not found at $framework_path"
    fi
    FRAMEWORK_ARGS+=("-framework" "$framework_path")
done

# Create XCFramework
log "Creating XCFramework..."
xcodebuild -create-xcframework \
    "${FRAMEWORK_ARGS[@]}" \
    -output "$OUTPUT_DIR/$XCFRAMEWORK_NAME" 2>&1 || {
        error "Failed to create XCFramework"
    }

if [ ! -d "$OUTPUT_DIR/$XCFRAMEWORK_NAME" ]; then
    error "Failed to create XCFramework"
fi

log "Created $XCFRAMEWORK_NAME successfully"
log "XCFramework build complete: $OUTPUT_DIR/$XCFRAMEWORK_NAME"
