#!/bin/bash
#
# load-secrets-env.sh
#
# Reads secrets from a secrets.txt file and exports them as environment variables.
# This makes CI/CD integration easier - the build script can source this file.
#
# Usage:
#   source ./load-secrets-env.sh [path-to-secrets.txt]
#
# If no path is provided, defaults to looking for secrets.txt in standard locations.

set -e

log() {
    echo "[load-secrets-env] $1" >&2
}

error() {
    echo "[load-secrets-env] ERROR: $1" >&2
    return 1
}

# Find secrets file
SECRETS_FILE="${1:-}"

if [ -z "$SECRETS_FILE" ]; then
    # Try standard locations
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check relative to Shared/Secrets/Scripts
    if [ -f "$SCRIPT_DIR/../../../secrets/secrets.txt" ]; then
        SECRETS_FILE="$SCRIPT_DIR/../../../secrets/secrets.txt"
    # Check relative to project root
    elif [ -f "../secrets/secrets.txt" ]; then
        SECRETS_FILE="../secrets/secrets.txt"
    elif [ -f "secrets/secrets.txt" ]; then
        SECRETS_FILE="secrets/secrets.txt"
    else
        error "Could not find secrets.txt. Please provide path as argument."
    fi
fi

if [ ! -f "$SECRETS_FILE" ]; then
    error "Secrets file not found: $SECRETS_FILE"
fi

log "Loading secrets from $SECRETS_FILE"

# Function to trim leading/trailing whitespace
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Count for logging
count=0

# Process each line from the secrets file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines or lines without "="
    if [ -z "$line" ] || [ "${line#*=}" = "$line" ]; then
        continue
    fi

    # Skip comments
    if [[ "$line" == \#* ]]; then
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

    # Export the environment variable
    export "$key"="$value"
    count=$((count + 1))
    log "Exported: $key"
done < "$SECRETS_FILE"

log "Loaded $count secret(s) as environment variables"
