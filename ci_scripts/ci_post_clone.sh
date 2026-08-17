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

# Install sentry-cli and its credentials for the "Upload Debug Symbols to
# Sentry" build phase. Xcode Cloud runners ship neither. (#955)
#
# How hard a failure here is depends on what this build is for. An archive
# that cannot upload its dSYMs ships to TestFlight with no server-side
# symbolication, so it should die here at minute zero rather than twenty
# minutes later in the build phase — hence --require-auth and the exit. A
# build or test workflow uploads nothing (its dSYMs belong to a run that
# reports no events), and killing it over a transient sentry.io outage would
# be its own kind of tax, so there the failure is reported and the build
# carries on. Either way
# scripts/upload-debug-symbols.sh is the backstop: it errors in CI whenever
# an actual dSYM goes un-uploaded — which is also what happens if
# CI_XCODEBUILD_ACTION turns out not to be set this early in the run. The
# fast-fail is an optimization on top of the guarantee, not the guarantee.
echo "📋 Installing sentry-cli..."
if [[ "${CI_XCODEBUILD_ACTION:-}" == "archive" ]]; then
    if ! "$SCRIPT_DIR/install-sentry-cli.sh" --require-auth; then
        echo "error: sentry-cli setup failed and this is an archive build, which must upload dSYMs to Sentry"
        exit 1
    fi
elif ! "$SCRIPT_DIR/install-sentry-cli.sh"; then
    echo "warning: sentry-cli setup failed; a build that produces dSYMs will fail in the upload build phase"
fi

echo "✅ CI post-clone complete"
