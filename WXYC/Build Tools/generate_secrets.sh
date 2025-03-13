#!/bin/sh

# Xcode provides these environment variables:
# SCRIPT_INPUT_FILE_0 - your input secrets file (e.g., Secrets.txt)
# SCRIPT_OUTPUT_FILE_0 - your output Swift file (e.g., Secrets.swift)
SECRETS_FILE="$SRCROOT/../secrets/secrets.txt"
OUTPUT_FILE="$SRCROOT/WXYC/Shared/Secrets/Sources/Secrets/Secrets.swift"

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

# Begin generating the Swift file.
cat <<EOF > "$OUTPUT_FILE"
// This file is auto-generated. Do not edit.

import ObfuscateMacro
import Foundation

public struct Secrets {
EOF

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

    # Append the static property to the Swift file.
    echo "    public static let ${camelKey} = #ObfuscatedString(\"${value}\")" >> "$OUTPUT_FILE"
done < "$SECRETS_FILE"

# Close the struct declaration.
echo "}" >> "$OUTPUT_FILE"
