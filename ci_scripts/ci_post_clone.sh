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

# Nothing here sets up Sentry. A runner that builds something shipping needs
# sentry-cli and an auth token for the "Upload Debug Symbols to Sentry" build
# phase, and this script used to install both — but no runner builds anything
# shipping (both GitHub Actions workflows are -configuration Debug, which the
# upload phase skips), so that was ~490 lines standing ready for a caller that
# never came. Add it back against a real runner if one ever archives; see
# docs/configuration.md for what the phase expects.

echo "✅ CI post-clone complete"
