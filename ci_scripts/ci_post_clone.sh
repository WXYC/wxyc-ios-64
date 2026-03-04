#!/bin/zsh

# Get the directory where this script is located and the repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔧 CI Post-Clone Script"
echo "   Script directory: $SCRIPT_DIR"
echo "   Repository root: $REPO_ROOT"

# Set up Swift macro trust for AnalyticsMacros and Lerpable
echo "📋 Setting up Swift macro trust..."
mkdir -p ~/Library/org.swift.swiftpm/security/
cp "$SCRIPT_DIR/macros.json" ~/Library/org.swift.swiftpm/security/
echo "   Copied macros.json to Swift security directory"

echo "✅ CI post-clone complete"
