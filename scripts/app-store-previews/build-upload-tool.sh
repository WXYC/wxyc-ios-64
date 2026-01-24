#!/bin/zsh
#
#  build-upload-tool.sh
#  WXYC
#
#  Compiles the App Store Connect upload tool.
#
#  Created by Jake on 01/22/26.
#  Copyright © 2026 WXYC. All rights reserved.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
SOURCE="${SCRIPT_DIR}/upload-preview.swift"
OUTPUT="${SCRIPT_DIR}/upload-preview"

echo "🔨 Compiling upload-preview..."

swiftc \
    -O \
    -whole-module-optimization \
    -o "$OUTPUT" \
    "$SOURCE"

echo "✅ Built: $OUTPUT"
echo ""
echo "Usage:"
echo "  $OUTPUT --help"
