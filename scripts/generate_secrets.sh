#!/bin/sh

# generate_secrets.sh
#
# Generates Secrets.swift from a local secrets file for development builds.
# For Xcode Cloud builds, see ci_scripts/ci_post_clone.sh instead.

set -e

# Skip in Xcode Cloud - ci_post_clone.sh handles secrets generation
if [ "$CI_XCODE_CLOUD" = "true" ]; then
    echo "[generate_secrets] Skipping - Xcode Cloud uses ci_post_clone.sh"
    exit 0
fi

SECRETS_FILE="$SRCROOT/../secrets/secrets.txt"
OUTPUT_FILE="$SRCROOT/Shared/Secrets/Sources/Secrets/Secrets.swift"

log() {
    echo "[generate_secrets] $1"
}

error() {
    echo "[generate_secrets] ERROR: $1" >&2
    exit 1
}

if [ ! -f "$SECRETS_FILE" ]; then
    error "Secrets file not found: $SECRETS_FILE"
fi

log "Reading secrets from $SECRETS_FILE"

# Use a temp file to avoid race conditions with the compiler
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Function to trim leading/trailing whitespace
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Function to convert SNAKE_CASE to camelCase
toCamelCase() {
    input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    echo "$input" | perl -pe 's/_([a-z])/\U$1/g'
}

# Begin generating the Swift file
cat <<EOF > "$TEMP_FILE"
// This file is auto-generated. Do not edit.

import ObfuscateMacro
import Foundation

public struct Secrets {
EOF

# Process each line from the secrets file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines or lines without "="
    if [ -z "$line" ] || [ "${line#*=}" = "$line" ]; then
        continue
    fi

    # Split the line into key and value
    key=$(echo "$line" | cut -d '=' -f 1)
    value=$(echo "$line" | cut -d '=' -f 2-)

    # Trim whitespace
    key=$(trim "$key")
    value=$(trim "$value")

    # Remove any surrounding quotes from the value
    value=$(echo "$value" | sed 's/^"//;s/"$//')

    # Convert the key from SNAKE_CASE to camelCase
    camelKey=$(toCamelCase "$key")

    echo "    public static let ${camelKey} = #ObfuscatedString(\"${value}\")" >> "$TEMP_FILE"
    log "Added secret: $camelKey"
done < "$SECRETS_FILE"

# Close the struct declaration
echo "}" >> "$TEMP_FILE"

# Atomic move to the final destination
mv "$TEMP_FILE" "$OUTPUT_FILE"
log "Generated $OUTPUT_FILE successfully"
