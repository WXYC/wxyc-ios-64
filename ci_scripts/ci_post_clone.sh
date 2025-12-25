#!/bin/zsh

# Set up Swift macro trust for ObfuscateMacro
mkdir -p ~/Library/org.swift.swiftpm/security/
cp macros.json ~/Library/org.swift.swiftpm/security/

# Build Secrets XCFramework from environment variables
# Expected environment variables:
#   POSTHOG_API_KEY
#   DISCOGS_API_KEY_V2_5
#   DISCOGS_API_SECRET_V2_5
#   SPOTIFY_CLIENT_ID
#   SPOTIFY_CLIENT_SECRET
#   REQUEST_O_MATIC

echo "Building Secrets XCFramework..."

# Check that required environment variables are set
missing_vars=()
[[ -z "$POSTHOG_API_KEY" ]] && missing_vars+=("POSTHOG_API_KEY")
[[ -z "$DISCOGS_API_KEY_V2_5" ]] && missing_vars+=("DISCOGS_API_KEY_V2_5")
[[ -z "$DISCOGS_API_SECRET_V2_5" ]] && missing_vars+=("DISCOGS_API_SECRET_V2_5")
[[ -z "$SPOTIFY_CLIENT_ID" ]] && missing_vars+=("SPOTIFY_CLIENT_ID")
[[ -z "$SPOTIFY_CLIENT_SECRET" ]] && missing_vars+=("SPOTIFY_CLIENT_SECRET")
[[ -z "$REQUEST_O_MATIC" ]] && missing_vars+=("REQUEST_O_MATIC")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "❌ ERROR: Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

# Build the XCFramework
./Shared/Secrets/Scripts/build-xcframework.sh

echo "✅ Built Secrets XCFramework successfully"
