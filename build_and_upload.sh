#!/bin/zsh
# build_and_upload.sh
# Builds an archive for the WXYC target and uploads it to App Store Connect
#
# Usage:
#   ./build_and_upload.sh                    # Build and upload using API key
#   ./build_and_upload.sh --archive-only     # Only build the archive
#   ./build_and_upload.sh --upload-only PATH # Upload an existing archive
#
# Authentication (choose one):
#   1. App Store Connect API Key (recommended):
#      - Set ASC_KEY_ID, ASC_ISSUER_ID environment variables
#      - Place AuthKey_<KEY_ID>.p8 in ~/.appstoreconnect/private_keys/
#
#   2. Apple ID with App-Specific Password:
#      - Set APPLE_ID and APP_SPECIFIC_PASSWORD environment variables
#      - Generate app-specific password at https://appleid.apple.com

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PROJECT_PATH="$SCRIPT_DIR/WXYC.xcodeproj"
SCHEME="WXYC"
CONFIGURATION="Release"
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives"
EXPORT_DIR="$SCRIPT_DIR/build/export"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --archive-only           Only build the archive, don't upload"
    echo "  --upload-only <path>     Upload an existing archive at <path>"
    echo "  --configuration <config> Build configuration (Debug/Release/TestFlight, default: Release)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Authentication (set environment variables):"
    echo ""
    echo "  Option 1 - App Store Connect API Key (recommended):"
    echo "    ASC_KEY_ID        Your API Key ID"
    echo "    ASC_ISSUER_ID     Your Issuer ID"
    echo "    ASC_KEY_PATH      Path to AuthKey_<KEY_ID>.p8 (optional, defaults to ~/.appstoreconnect/private_keys/)"
    echo ""
    echo "  Option 2 - Apple ID:"
    echo "    APPLE_ID                Your Apple ID email"
    echo "    APP_SPECIFIC_PASSWORD   App-specific password from appleid.apple.com"
    echo ""
    echo "Examples:"
    echo "  # Build and upload using API key"
    echo "  ASC_KEY_ID=ABC123 ASC_ISSUER_ID=xxx-yyy-zzz ./build_and_upload.sh"
    echo ""
    echo "  # Build archive only"
    echo "  ./build_and_upload.sh --archive-only"
    echo ""
    echo "  # Upload existing archive"
    echo "  ./build_and_upload.sh --upload-only ~/Library/Developer/Xcode/Archives/2024-01-15/WXYC.xcarchive"
}

create_export_options_plist() {
    local plist_path="$1"
    
    cat > "$plist_path" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
</dict>
</plist>
EOF
}

build_archive() {
    local archive_path="$1"
    
    print_header "Building Archive"
    print_info "Scheme: $SCHEME"
    print_info "Configuration: $CONFIGURATION"
    print_info "Archive path: $archive_path"
    
    # Clean derived data for a fresh build
    print_info "Cleaning derived data..."
    xcodebuild clean \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -quiet 2>&1 || true
    
    # Build the archive
    print_info "Building archive (this may take a few minutes)..."
    
    xcodebuild archive \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "generic/platform=iOS" \
        -archivePath "$archive_path" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        2>&1 | while IFS= read -r line; do
            # Show progress indicators
            if [[ "$line" == *"Compiling"* ]] || [[ "$line" == *"Linking"* ]]; then
                echo -ne "\r${YELLOW}→ ${line:0:70}...${NC}                    "
            elif [[ "$line" == *"error:"* ]]; then
                echo -e "\n${RED}$line${NC}"
            elif [[ "$line" == *"warning:"* ]]; then
                : # Suppress warnings for cleaner output
            fi
        done
    
    echo ""  # New line after progress
    
    if [[ -d "$archive_path" ]]; then
        print_success "Archive created successfully"
        return 0
    else
        print_error "Archive creation failed"
        return 1
    fi
}

export_archive() {
    local archive_path="$1"
    local export_path="$2"
    local export_options_plist="$export_path/ExportOptions.plist"
    
    print_header "Exporting Archive"
    
    mkdir -p "$export_path"
    create_export_options_plist "$export_options_plist"
    
    print_info "Export path: $export_path"
    
    local export_cmd=(
        xcodebuild -exportArchive
        -archivePath "$archive_path"
        -exportPath "$export_path"
        -exportOptionsPlist "$export_options_plist"
        -allowProvisioningUpdates
    )
    
    # Add API key authentication if available
    if [[ -n "$ASC_KEY_ID" ]] && [[ -n "$ASC_ISSUER_ID" ]]; then
        local key_path="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
        
        if [[ -f "$key_path" ]]; then
            print_info "Using App Store Connect API key for authentication"
            export_cmd+=(
                -authenticationKeyPath "$key_path"
                -authenticationKeyID "$ASC_KEY_ID"
                -authenticationKeyIssuerID "$ASC_ISSUER_ID"
            )
        else
            print_error "API key file not found at: $key_path"
            print_info "Expected path: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
            return 1
        fi
    fi
    
    print_info "Exporting and uploading to App Store Connect..."
    
    if "${export_cmd[@]}" 2>&1; then
        print_success "Export and upload completed successfully"
        return 0
    else
        print_error "Export/upload failed"
        return 1
    fi
}

upload_with_altool() {
    local ipa_path="$1"
    
    print_header "Uploading to App Store Connect"
    
    if [[ -n "$ASC_KEY_ID" ]] && [[ -n "$ASC_ISSUER_ID" ]]; then
        local key_path="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
        
        if [[ ! -f "$key_path" ]]; then
            print_error "API key file not found at: $key_path"
            return 1
        fi
        
        print_info "Uploading with App Store Connect API key..."
        
        xcrun altool --upload-app \
            --file "$ipa_path" \
            --type ios \
            --apiKey "$ASC_KEY_ID" \
            --apiIssuer "$ASC_ISSUER_ID"
            
    elif [[ -n "$APPLE_ID" ]] && [[ -n "$APP_SPECIFIC_PASSWORD" ]]; then
        print_info "Uploading with Apple ID..."
        
        xcrun altool --upload-app \
            --file "$ipa_path" \
            --type ios \
            --username "$APPLE_ID" \
            --password "$APP_SPECIFIC_PASSWORD"
    else
        print_error "No authentication credentials provided"
        print_info "Set either ASC_KEY_ID/ASC_ISSUER_ID or APPLE_ID/APP_SPECIFIC_PASSWORD"
        return 1
    fi
}

validate_archive() {
    local archive_path="$1"
    
    print_header "Validating Archive"
    
    if [[ ! -d "$archive_path" ]]; then
        print_error "Archive not found at: $archive_path"
        return 1
    fi
    
    # Check for .app inside the archive
    local app_path="$archive_path/Products/Applications"
    if [[ -d "$app_path" ]]; then
        local app_name=$(ls "$app_path" | head -1)
        print_success "Found app: $app_name"
    else
        print_error "No .app found in archive"
        return 1
    fi
    
    # Check for Info.plist
    local info_plist="$archive_path/Info.plist"
    if [[ -f "$info_plist" ]]; then
        local version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$info_plist" 2>/dev/null || echo "unknown")
        local build=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$info_plist" 2>/dev/null || echo "unknown")
        print_success "Version: $version ($build)"
    fi
    
    # Check for dSYMs
    local dsym_path="$archive_path/dSYMs"
    if [[ -d "$dsym_path" ]] && [[ -n "$(ls -A "$dsym_path" 2>/dev/null)" ]]; then
        local dsym_count=$(ls "$dsym_path" | wc -l | tr -d ' ')
        print_success "Found $dsym_count dSYM file(s)"
    else
        print_info "No dSYM files found (may be expected for some builds)"
    fi
    
    return 0
}

main() {
    local archive_only=false
    local upload_only=false
    local existing_archive=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --archive-only)
                archive_only=true
                shift
                ;;
            --upload-only)
                upload_only=true
                existing_archive="$2"
                shift 2
                ;;
            --configuration)
                CONFIGURATION="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_header "WXYC Build & Upload"
    
    # Validate project exists
    if [[ ! -d "$PROJECT_PATH" ]]; then
        print_error "Project not found at: $PROJECT_PATH"
        exit 1
    fi
    
    # Get version info
    local version=$(grep 'MARKETING_VERSION' "$SCRIPT_DIR/WXYC/Configuration/Shared.xcconfig" | cut -d'=' -f2 | tr -d ' ' || echo "unknown")
    print_info "Marketing version: $version"
    print_info "Configuration: $CONFIGURATION"
    
    local archive_path
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    
    if [[ "$upload_only" == true ]]; then
        # Upload existing archive
        if [[ -z "$existing_archive" ]] || [[ ! -d "$existing_archive" ]]; then
            print_error "Please provide a valid archive path with --upload-only"
            exit 1
        fi
        archive_path="$existing_archive"
        print_info "Using existing archive: $archive_path"
    else
        # Build new archive
        archive_path="$ARCHIVE_DIR/$(date +%Y-%m-%d)/WXYC_${version}_${timestamp}.xcarchive"
        mkdir -p "$(dirname "$archive_path")"
        
        if ! build_archive "$archive_path"; then
            print_error "Build failed"
            exit 1
        fi
    fi
    
    # Validate the archive
    if ! validate_archive "$archive_path"; then
        print_error "Archive validation failed"
        exit 1
    fi
    
    if [[ "$archive_only" == true ]]; then
        print_header "Archive Complete"
        print_success "Archive location: $archive_path"
        echo ""
        echo "To upload later, run:"
        echo "  $0 --upload-only \"$archive_path\""
        exit 0
    fi
    
    # Check for authentication
    if [[ -z "$ASC_KEY_ID" ]] && [[ -z "$APPLE_ID" ]]; then
        print_header "Authentication Required"
        print_info "Archive created but upload requires authentication."
        echo ""
        echo "Set one of the following:"
        echo ""
        echo "  Option 1 - App Store Connect API Key:"
        echo "    export ASC_KEY_ID=<your-key-id>"
        echo "    export ASC_ISSUER_ID=<your-issuer-id>"
        echo "    # Place AuthKey_<KEY_ID>.p8 in ~/.appstoreconnect/private_keys/"
        echo ""
        echo "  Option 2 - Apple ID:"
        echo "    export APPLE_ID=<your-apple-id>"
        echo "    export APP_SPECIFIC_PASSWORD=<app-specific-password>"
        echo ""
        echo "Then run:"
        echo "  $0 --upload-only \"$archive_path\""
        exit 0
    fi
    
    # Export and upload
    local export_path="$EXPORT_DIR/${timestamp}"
    
    if ! export_archive "$archive_path" "$export_path"; then
        print_error "Export/upload failed"
        exit 1
    fi
    
    print_header "Success!"
    print_success "Archive: $archive_path"
    print_success "Export: $export_path"
    echo ""
    echo "Your build has been uploaded to App Store Connect."
    echo "Check the status at: https://appstoreconnect.apple.com"
}

main "$@"
