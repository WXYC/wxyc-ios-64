#!/bin/zsh 

mkdir -p ~/Library/org.swift.swiftpm/security/
cp macros.json ~/Library/org.swift.swiftpm/security/

# Generate stub Secrets.swift if it doesn't exist (for CI builds)
SECRETS_FILE="Shared/Secrets/Sources/Secrets/Secrets.swift"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "Secrets.swift not found. Generating stub file for CI build..."
    
    mkdir -p "$(dirname "$SECRETS_FILE")"
    
    cat > "$SECRETS_FILE" << 'EOF'
/// Stub secrets for CI builds
/// These placeholder values allow the project to compile but won't work for actual API calls
public enum Secrets {
    public static let discogsApiKeyV2_5: String = ""
    public static let discogsApiSecretV2_5: String = ""
    public static let spotifyClientId: String = ""
    public static let spotifyClientSecret: String = ""
    public static let requestOMatic: String = "https://placeholder.local"
    public static let posthogApiKey: String = ""
}
EOF
    
    echo "✅ Generated stub Secrets.swift"
else
    echo "✅ Secrets.swift exists, using existing file"
fi
