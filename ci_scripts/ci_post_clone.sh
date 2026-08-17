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

# Tell the build phase it is on a runner. A marker file rather than $CI: see
# install-sentry-cli.sh's header on why anything a run-script phase nested
# inside xcodebuild has to read belongs on disk. .ci-tools/ is gitignored and
# the runner is ephemeral, so this costs a mkdir and a truncate.
mkdir -p "$REPO_ROOT/.ci-tools"
: > "$REPO_ROOT/.ci-tools/ci-runner"
echo "   Marked this checkout as a CI runner"

# Install sentry-cli and its credentials for the "Upload Debug Symbols to
# Sentry" build phase. Xcode Cloud runners ship neither. (#955)
#
# How much this run cares depends on what it is for:
#
#   An archive that cannot upload its dSYMs ships to TestFlight with no
#   server-side symbolication, so it dies here at minute zero rather than
#   twenty minutes on in the build phase. install-sentry-cli.sh prints its own
#   error: naming the fix, so there is nothing to add on the way out.
#
#   A test workflow never uploads at all — upload-debug-symbols.sh skips any CI
#   build that can't ship — so installing a 27 MiB binary it will never open is
#   pure tax on every test run. Skipped outright.
#
#   Anything else (a plain build, or an action this doesn't recognize) installs
#   and carries on if it can't: a Release build workflow does need the binary,
#   and killing an entire run over a transient sentry.io outage would be its
#   own kind of tax. upload-debug-symbols.sh is the backstop either way — it
#   errors in CI whenever an actual dSYM goes un-uploaded, including when
#   CI_XCODEBUILD_ACTION turns out not to be set this early in the run. The
#   fast-fail is an optimization on top of that guarantee, not the guarantee.
echo "📋 Installing sentry-cli..."
if [[ "${CI_XCODEBUILD_ACTION:-}" == "test" ]]; then
    echo "   Test workflow: skipping (this build won't ship, so the upload phase skips too)"
elif [[ "${CI_XCODEBUILD_ACTION:-}" == "archive" ]]; then
    "$SCRIPT_DIR/install-sentry-cli.sh" --require-auth || exit 1
elif ! "$SCRIPT_DIR/install-sentry-cli.sh"; then
    echo "warning: sentry-cli setup failed; a build that ships — an archive, or any non-Debug configuration — will fail in the upload build phase. A test workflow will not: it skips the upload."
fi

echo "✅ CI post-clone complete"
