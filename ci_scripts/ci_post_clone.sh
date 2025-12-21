#!/bin/zsh

# Set up Swift macro trust for ObfuscateMacro
mkdir -p ~/Library/org.swift.swiftpm/security/
cp macros.json ~/Library/org.swift.swiftpm/security/

# Generate Secrets.swift from environment variables
# Expected environment variables:
#   POSTHOG_API_KEY
#   DISCOGS_API_KEY_V2_5
#   DISCOGS_API_SECRET_V2_5
#   SLACK_WXYC_REQUESTS_WEBHOOK

SECRETS_FILE="Shared/Secrets/Sources/Secrets/Secrets.swift"

echo "Generating Secrets.swift from environment variables..."

mkdir -p "$(dirname "$SECRETS_FILE")"

# Check that required environment variables are set
missing_vars=()
[[ -z "$POSTHOG_API_KEY" ]] && missing_vars+=("POSTHOG_API_KEY")
[[ -z "$DISCOGS_API_KEY_V2_5" ]] && missing_vars+=("DISCOGS_API_KEY_V2_5")
[[ -z "$DISCOGS_API_SECRET_V2_5" ]] && missing_vars+=("DISCOGS_API_SECRET_V2_5")
[[ -z "$SLACK_WXYC_REQUESTS_WEBHOOK" ]] && missing_vars+=("SLACK_WXYC_REQUESTS_WEBHOOK")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "❌ ERROR: Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

cat > "$SECRETS_FILE" << EOF
// This file is auto-generated. Do not edit.

import ObfuscateMacro
import Foundation

public struct Secrets {
    public static let posthogApiKey = #ObfuscatedString("${POSTHOG_API_KEY}")
    public static let discogsApiKeyV2_5 = #ObfuscatedString("${DISCOGS_API_KEY_V2_5}")
    public static let discogsApiSecretV2_5 = #ObfuscatedString("${DISCOGS_API_SECRET_V2_5}")
    public static let slackWxycRequestsWebhook = #ObfuscatedString("${SLACK_WXYC_REQUESTS_WEBHOOK}")
}
EOF

echo "✅ Generated Secrets.swift with obfuscated values"
