#!/bin/sh

# Xcode provides these environment variables:
# SCRIPT_INPUT_FILE_0 - your input secrets file (e.g., Secrets.txt)
# SCRIPT_OUTPUT_FILE_0 - your output Swift file (e.g., Secrets.swift)
SECRETS_FILE="$SRCROOT/../secrets/secrets.txt"
OUTPUT_FILE="$SRCROOT/WXYC/Shared/Secrets/Sources/Secrets/Secrets.swift"

# Use a temp file to avoid race conditions with the compiler
TEMP_FILE=$(mktemp)

# Function to trim leading/trailing whitespace.
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Function to convert SNAKE_CASE to camelCase using perl.
toCamelCase() {
    input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    # Use perl to uppercase the character following an underscore.
    echo "$input" | perl -pe 's/_([a-z])/\U$1/g'
}

# Begin generating the Swift file to temp file.
cat <<EOF > "$TEMP_FILE"
// This file is auto-generated. Do not edit.

import ObfuscateMacro
import Foundation

public struct Secrets {
EOF

if [[ "$CI_XCODE_CLOUD" != "true" ]]; then
    # Process each line from the secrets file.
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or lines without "=".
        if [ -z "$line" ] || [[ "$line" != *"="* ]]; then
            continue
        fi

        # Split the line into key and value.
        key=$(echo "$line" | cut -d '=' -f 1)
        value=$(echo "$line" | cut -d '=' -f 2-)

        # Trim whitespace.
        key=$(trim "$key")
        value=$(trim "$value")

        # Remove any surrounding quotes from the value.
        value=$(echo "$value" | sed 's/^"//;s/"$//')

        # Convert the key from SNAKE_CASE to camelCase.
        camelKey=$(toCamelCase "$key")

        # Append the static property to the temp file.
        echo "    public static let ${camelKey} = #ObfuscatedString(\"${value}\")" >> "$TEMP_FILE"
    done < "$SECRETS_FILE"
else
    echo "    public static let posthogApiKey = \"posthogApiKey\"" >> "$TEMP_FILE"
    echo "    public static let discogsApiKeyV2_5 = \"discogsApiKeyV2_5\"" >> "$TEMP_FILE"
    echo "    public static let discogsApiSecretV2_5 = \"discogsApiSecretV2_5\"" >> "$TEMP_FILE"
    echo "    public static let slackWxycRequestsWebhook = \"slackWxycRequestsWebhook\"" >> "$TEMP_FILE"
fi

# Close the struct declaration.
echo "}" >> "$TEMP_FILE"

# Atomic move to the final destination
mv "$TEMP_FILE" "$OUTPUT_FILE"
