#!/bin/zsh
# Script to validate an iOS app archive locally before App Store submission
# Usage: ./validate_archive.sh <path-to-archive> [app-specific-password]

set -e

ARCHIVE_PATH="$1"
APP_PASSWORD="$2"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "Usage: $0 <path-to-archive> [app-specific-password]"
    echo ""
    echo "Example:"
    echo "  $0 ~/Library/Developer/Xcode/Archives/2024-01-15/WXYC.xcarchive"
    echo ""
    echo "To get an app-specific password:"
    echo "  1. Go to https://appleid.apple.com"
    echo "  2. Sign in and go to 'Sign-In and Security'"
    echo "  3. Generate an app-specific password under 'App-Specific Passwords'"
    exit 1
fi

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Error: Archive not found at $ARCHIVE_PATH"
    exit 1
fi

# Export the archive to an IPA first
TEMP_DIR=$(mktemp -d)
EXPORT_PATH="$TEMP_DIR/WXYC.ipa"

echo "Exporting archive to IPA..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$TEMP_DIR" \
    -exportOptionsPlist <(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF
) || {
    echo "Error: Failed to export archive"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Find the exported IPA
EXPORTED_IPA=$(find "$TEMP_DIR" -name "*.ipa" | head -1)
if [ -z "$EXPORTED_IPA" ]; then
    echo "Error: Could not find exported IPA"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Validating IPA: $EXPORTED_IPA"

if [ -n "$APP_PASSWORD" ]; then
    # Validate with app-specific password
    xcrun altool --validate-app \
        --file "$EXPORTED_IPA" \
        --type ios \
        --apiKey "$(git config user.email)" \
        --apiIssuer "$APP_PASSWORD" || {
        echo ""
        echo "Note: If using API key, you need to set up App Store Connect API key"
        echo "Alternatively, use your Apple ID email and app-specific password:"
        echo "  xcrun altool --validate-app --file \"$EXPORTED_IPA\" --type ios --username YOUR_EMAIL --password YOUR_APP_SPECIFIC_PASSWORD"
        rm -rf "$TEMP_DIR"
        exit 1
    }
else
    echo ""
    echo "To validate with Apple's servers, run:"
    echo "  xcrun altool --validate-app --file \"$EXPORTED_IPA\" --type ios --username YOUR_EMAIL --password YOUR_APP_SPECIFIC_PASSWORD"
    echo ""
    echo "Or use the Xcode Organizer (Window > Organizer) to validate the archive."
    echo ""
    echo "Basic validation: Checking IPA structure..."
    
    # Basic validation: check if IPA is a valid zip and contains required files
    unzip -q -t "$EXPORTED_IPA" && echo "✓ IPA is a valid zip file" || {
        echo "✗ IPA is not a valid zip file"
        rm -rf "$TEMP_DIR"
        exit 1
    }
    
    # Check for .build directories (the issue you encountered)
    echo "Checking for .build directories in IPA..."
    if unzip -l "$EXPORTED_IPA" | grep -q "\.build/"; then
        echo "⚠ WARNING: Found .build directories in IPA!"
        unzip -l "$EXPORTED_IPA" | grep "\.build/"
        rm -rf "$TEMP_DIR"
        exit 1
    else
        echo "✓ No .build directories found in IPA"
    fi
    
    # Check for required app structure
    APP_NAME=$(basename "$EXPORTED_IPA" .ipa)
    if unzip -l "$EXPORTED_IPA" | grep -q "Payload/.*\.app/Info.plist"; then
        echo "✓ IPA contains valid app structure"
    else
        echo "✗ IPA does not contain valid app structure"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

echo ""
echo "✓ Validation passed!"
echo "IPA location: $EXPORTED_IPA"
echo ""
echo "To clean up temporary files, run:"
echo "  rm -rf $TEMP_DIR"

