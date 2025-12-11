#!/bin/bash
# Generate Xcode project with XcodeGen and apply post-processing
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Generating Xcode project..."
xcodegen -s project.yml

echo "Post-processing for synced folder exceptions..."
python3 "$SCRIPT_DIR/postprocess_xcodeproj.py" WXYC.xcodeproj/project.pbxproj

echo "Done!"

