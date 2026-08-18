#!/bin/zsh
#
# test-upload-debug-symbols.sh
#
# Black-box regression test for scripts/upload-debug-symbols.sh — the script
# the "Upload Debug Symbols to Sentry" build phase runs.
#
# The behavior under test is which builds a missed upload is allowed to stop
# (#955). Before that issue, the whole thing was four lines inlined in
# project.pbxproj and every failure path — no binary, no credentials, a
# rejected upload — degraded to a `warning:`. For an everyday build that is
# right: nobody debugging a layout bug should be blocked because they never
# installed sentry-cli. For a build that ships it is exactly wrong: the archive
# is made, the build stays green, and every Release event in Sentry loses its
# function names with no visible error anywhere.
#
# So the contract has four branches and all of them need pinning:
#   an archive (ACTION=install), anywhere — every failure is an error, exit 1,
#       and the archive does not get made. WXYC ships from Product > Archive on
#       a dev Mac, so this is the branch guarding the real shipping path.
#   any other local build — every failure is a warning, exit 0, build
#       continues. A plain local Release build is in this branch: people build
#       Release to check optimized behavior, and that is not a ship.
#   a shipping build on CI — an error too, on the fail-safe reasoning in
#       is_shipping_build().
#   a non-shipping CI build — skipped outright, nothing uploaded.
#
# The stub sentry-cli records its argv and the Sentry-relevant environment so
# the tests can assert the upload is invoked against the right org/project
# without touching the network or needing a real auth token.
#
# Run directly:
#   zsh scripts/tests/test-upload-debug-symbols.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
REAL_SCRIPT="${REPO_ROOT}/scripts/upload-debug-symbols.sh"

if [[ ! -f "$REAL_SCRIPT" ]]; then
    echo "Cannot find scripts/upload-debug-symbols.sh at $REAL_SCRIPT" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

# -----------------------------------------------------------------------
# Fixture
#
# Each case gets a throwaway SRCROOT and HOME. HOME matters: sentry-cli
# reads ~/.sentryclirc, and so does the credential precheck, so a developer
# running this suite on a machine with a real token must not have their own
# config decide the outcome of the "no credentials" cases.
# -----------------------------------------------------------------------

FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# A dSYM folder shaped like the one an archive produces.
DSYM_DIR="$FIXTURE/dsyms"
mkdir -p "$DSYM_DIR/WXYC.app.dSYM/Contents/Resources/DWARF"
echo "not really mach-o" > "$DSYM_DIR/WXYC.app.dSYM/Contents/Resources/DWARF/WXYC"

# A dSYM folder path that the build setting names but that no build populated
# — what a Debug build leaves behind.
EMPTY_DSYM_DIR="$FIXTURE/dsyms-empty"
mkdir -p "$EMPTY_DSYM_DIR"

# Stub sentry-cli. Writes its argv and the Sentry environment it was handed
# to $STUB_LOG, and fails when $STUB_FAIL is set so the failure paths can be
# exercised without a network.
make_stub() {
    # Not `local path` — zsh ties the lowercase `path` array to PATH, so a
    # local of that name blanks the command search path inside the function.
    # Defaults to the vendored location resolve_sentry_cli searches, which is
    # the point of installing it there; Case 10 passes a directory instead, to
    # stand in for a Homebrew prefix that is on no PATH the phase inherits.
    local stub_dir="${1:-$CASE_SRCROOT/.ci-tools/bin}"
    local stub_path="$stub_dir/sentry-cli"
    mkdir -p "$stub_dir"
    cat > "$stub_path" <<'STUB'
#!/bin/sh
if [ "$1" = "--version" ]; then
    echo "sentry-cli 9.9.9"
    exit 0
fi
{
    echo "self: $0"
    echo "argv: $*"
    echo "SENTRY_ORG=${SENTRY_ORG:-}"
    echo "SENTRY_PROJECT=${SENTRY_PROJECT:-}"
    echo "SENTRY_AUTH_TOKEN=${SENTRY_AUTH_TOKEN:-}"
} >> "$STUB_LOG"
if [ -n "${STUB_FAIL:-}" ]; then
    echo "an org auth token is required for this command" >&2
    echo "some chatter on stdout"
    exit 1
fi
echo "Uploaded 1 debug information file"
exit 0
STUB
    chmod +x "$stub_path"
}

# Exactly what ci_post_clone.sh drops into the checkout on a runner. Naming it
# documents the coupling these cases exist to pin.
mark_ci_runner() {
    mkdir -p "$CASE_SRCROOT/.ci-tools"
    : > "$CASE_SRCROOT/.ci-tools/ci-runner"
}

# Runs the real script in a hermetic environment. Every knob the script reads
# is passed explicitly; PATH is narrowed to the system directories so a real
# sentry-cli in /usr/local/bin can never satisfy a case that is meant to run
# without one. SENTRY_CLI_SEARCH_DIRS is emptied for the same reason and needs
# the same care: the list the script ships with names /usr/local/bin outright,
# so leaving it at its default would hand every "no sentry-cli" case a working
# binary on the maintainer's Mac and pass for the wrong reason.
#
# CONFIGURATION and ACTION default to an archive's values (Release/install),
# because that is the build the strict behavior is about. Cases that want a
# Debug or plain-build environment set CASE_CONFIGURATION / CASE_ACTION; a case
# that unsets them gets a child environment with those variables genuinely
# absent, which is a distinct branch in the script and needs a distinct
# fixture. Building the assignments into an array is the only way to express
# that through `env -i`: a `CONFIGURATION="${CASE_CONFIGURATION-Release}"`
# argument substitutes the default *precisely when the variable is unset*, so
# the absent case would silently test the same thing as the default one.
run_script() {
    # usage: run_script <dsym-folder> <CI value> <token>. HOME and SRCROOT come
    # from whichever case new_case just set up — every call site passed them
    # straight back, which buried the two arguments that actually vary.
    local dsym_folder="$1" ci="$2" token="$3"
    local -a build_settings=()
    [[ -n "${CASE_CONFIGURATION+set}" ]] && build_settings+=("CONFIGURATION=${CASE_CONFIGURATION}")
    [[ -n "${CASE_ACTION+set}" ]] && build_settings+=("ACTION=${CASE_ACTION}")

    env -i \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$CASE_HOME" \
        SRCROOT="$CASE_SRCROOT" \
        DWARF_DSYM_FOLDER_PATH="$dsym_folder" \
        CI="$ci" \
        SENTRY_AUTH_TOKEN="$token" \
        "${build_settings[@]}" \
        SENTRY_CLI_SEARCH_DIRS="$CASE_SEARCH_DIRS" \
        STUB_LOG="$STUB_LOG" \
        STUB_FAIL="$STUB_FAIL" \
        /bin/zsh "$REAL_SCRIPT" 2>&1
}

new_case() {
    local name="$1"
    CASE_HOME="$FIXTURE/$name/home"
    CASE_SRCROOT="$FIXTURE/$name/srcroot"
    mkdir -p "$CASE_HOME" "$CASE_SRCROOT"
    STUB_LOG="$FIXTURE/$name/stub.log"
    : > "$STUB_LOG"
    STUB_FAIL=""
    CASE_SEARCH_DIRS=""
    CASE_CONFIGURATION="Release"
    CASE_ACTION="install"
}

# The opposite fixture: an ordinary build rather than an archive. Cases that
# assert leniency need this, because an archive is strict everywhere and so can
# no longer stand in for "an ordinary local build" the way it could when CI-ness
# was the only thing strictness turned on.
#
# Release rather than Debug on purpose: a Debug build on CI skips the upload
# outright, so a Debug fixture cannot tell "lenient" apart from "skipped".
ordinary_build() {
    CASE_CONFIGURATION="Release"
    CASE_ACTION="build"
}

# =========================================================================
# Case 1: no dSYMs.
#
# On an ordinary build, and on any CI build that cannot ship, this is
# unremarkable: there is nothing to upload, so there is nothing to say. On a
# build that *does* ship it is the opposite — every WXYC configuration sets
# DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an archive with an empty
# DWARF_DSYM_FOLDER_PATH means something upstream broke (a flipped build
# setting, a dsymutil failure, a moved path) and the archive is about to ship
# unsymbolicated. Skipping quietly there is the #955 failure mode wearing a
# different hat.
# =========================================================================

echo "=== Case 1: build produced no dSYMs ==="

new_case "no-dsyms-local"
ordinary_build
OUT=$(run_script "$EMPTY_DSYM_DIR" "" ""); RC=$?
expect_exit "empty dSYM folder locally exits 0" "$RC" "0" "$OUT"
expect_not_contains "empty dSYM folder locally emits no error:" "$OUT" "error:"
expect_not_contains "empty dSYM folder locally emits no warning:" "$OUT" "warning:"

new_case "no-dsym-path-local"
ordinary_build
OUT=$(run_script "" "" ""); RC=$?
expect_exit "unset DWARF_DSYM_FOLDER_PATH locally exits 0" "$RC" "0" "$OUT"
expect_not_contains "unset DWARF_DSYM_FOLDER_PATH locally emits no error:" "$OUT" "error:"

new_case "no-dsyms-ci-nonshipping"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
OUT=$(run_script "$EMPTY_DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "empty dSYM folder on a non-shipping CI build exits 0" "$RC" "0" "$OUT"
expect_not_contains "empty dSYM folder on a non-shipping CI build emits no error:" "$OUT" "error:"

new_case "no-dsyms-ci-archive"
OUT=$(run_script "$EMPTY_DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "an archive that produced no dSYMs fails the build" "$RC" "1" "$OUT"
expect_contains "an archive with no dSYMs is an error:" "$OUT" "error:"
expect_contains "the error names the folder it found empty" "$OUT" "$EMPTY_DSYM_DIR"

new_case "no-dsym-path-ci-archive"
OUT=$(run_script "" "TRUE" "sntrys_fake"); RC=$?
expect_exit "an archive with no DWARF_DSYM_FOLDER_PATH at all fails the build" "$RC" "1" "$OUT"
expect_contains "the missing dSYM folder is an error:" "$OUT" "error:"

new_case "missing-dsym-dir-ci-archive"
OUT=$(run_script "$FIXTURE/does-not-exist" "TRUE" "sntrys_fake"); RC=$?
expect_exit "an archive whose dSYM folder does not exist fails the build" "$RC" "1" "$OUT"

# =========================================================================
# Case 2: dSYMs exist but sentry-cli does not.
#
# This is the Xcode Cloud failure mode from #955 — the runner ships no
# sentry-cli and ci_scripts never installed one, so the phase printed
# "warning: sentry-cli not installed" and the archive shipped unsymbolicated.
# =========================================================================

echo ""
echo "=== Case 2: dSYMs present, sentry-cli absent ==="

new_case "no-cli-ci"
OUT=$(run_script "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "missing sentry-cli in CI fails the build" "$RC" "1" "$OUT"
expect_contains "missing sentry-cli in CI is an error:" "$OUT" "error:"
expect_contains "the error names sentry-cli" "$OUT" "sentry-cli"
expect_contains "the error points at the installer script" "$OUT" "ci_scripts/install-sentry-cli.sh"
expect_not_contains "the CI diagnostic does not tell a runner to run Homebrew" "$OUT" "brew"
# A runner whose CI variable did arrive has nothing stale to clean up, so the
# marker advice would be noise on the one line Xcode shows.
expect_not_contains "a genuine CI build is not told to delete a marker" "$OUT" ".ci-tools/ci-runner"

new_case "no-cli-local"
ordinary_build
OUT=$(run_script "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "missing sentry-cli locally still exits 0" "$RC" "0" "$OUT"
expect_contains "missing sentry-cli locally is a warning:" "$OUT" "warning:"
expect_not_contains "missing sentry-cli locally is not an error:" "$OUT" "error:"

# =========================================================================
# Case 3: sentry-cli present but no credentials.
#
# The second independent way the old phase went quiet: .sentryclirc is
# gitignored, so a clean checkout has no token and `debug-files upload` had
# nothing to authenticate with.
# =========================================================================

echo ""
echo "=== Case 3: dSYMs present, sentry-cli present, no credentials ==="

new_case "no-token-ci"
make_stub
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "missing token in CI fails the build" "$RC" "1" "$OUT"
expect_contains "missing token in CI is an error:" "$OUT" "error:"
expect_contains "the error names the env var to set" "$OUT" "SENTRY_AUTH_TOKEN"
expect_contains "the CI credential diagnostic names where to set it" "$OUT" "Xcode Cloud"
NOTOKEN_LOG=$(<"$STUB_LOG")
expect_not_contains "sentry-cli is not invoked at all without credentials" "$NOTOKEN_LOG" "debug-files"

new_case "no-token-local"
ordinary_build
make_stub
OUT=$(run_script "$DSYM_DIR" "" ""); RC=$?
expect_exit "missing token locally still exits 0" "$RC" "0" "$OUT"
expect_contains "missing token locally is a warning:" "$OUT" "warning:"
expect_not_contains "missing token locally is not an error:" "$OUT" "error:"

# A repo-root .sentryclirc is how every dev Mac authenticates today. It must
# keep counting as credentials, with no SENTRY_AUTH_TOKEN in the environment.
new_case "sentryclirc-in-srcroot"
make_stub
printf '[auth]\ntoken=sntrys_from_srcroot\n' > "$CASE_SRCROOT/.sentryclirc"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a .sentryclirc in SRCROOT counts as credentials" "$RC" "0" "$OUT"
expect_contains "the upload runs on the strength of .sentryclirc alone" "$(<"$STUB_LOG")" "debug-files"

# ~/.sentryclirc is what ci_scripts/install-sentry-cli.sh materializes on the
# runner, and it has to be honored even when the token never reaches the
# xcodebuild environment.
new_case "sentryclirc-in-home"
make_stub
printf '[auth]\ntoken=sntrys_from_home\n' > "$CASE_HOME/.sentryclirc"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a ~/.sentryclirc counts as credentials" "$RC" "0" "$OUT"
expect_contains "the upload runs on the strength of ~/.sentryclirc alone" "$(<"$STUB_LOG")" "debug-files"

# The file existing is not the same claim as a credential existing — the same
# test install-sentry-cli.sh applies before it calls an existing rc file good
# enough. Without it, this build reaches the upload and dies with sentry-cli's
# generic "an org auth token is required" instead of the line naming the fix.
new_case "sentryclirc-without-token"
make_stub
printf '[defaults]\norg=wxyc\n' > "$CASE_SRCROOT/.sentryclirc"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a token-less .sentryclirc does not count as credentials" "$RC" "1" "$OUT"
expect_contains "the token-less rc file still names the variable to set" "$OUT" "SENTRY_AUTH_TOKEN"
expect_not_contains "sentry-cli is never invoked against a token-less rc file" "$(<"$STUB_LOG")" "debug-files"

# =========================================================================
# Case 4: the happy path — what the upload is actually invoked with.
# =========================================================================

echo ""
echo "=== Case 4: successful upload ==="

new_case "upload-ok"
make_stub
OUT=$(run_script "$DSYM_DIR" "TRUE" "sntrys_supersecret"); RC=$?
LOG=$(<"$STUB_LOG")
expect_exit "a successful upload exits 0" "$RC" "0" "$OUT"
expect_contains "sentry-cli is resolved from SRCROOT/.ci-tools/bin without PATH" "$LOG" "argv:"
expect_contains "the subcommand is debug-files upload" "$LOG" "debug-files upload"
expect_contains "sources are included so Sentry can show source context" "$LOG" "--include-sources"
expect_contains "the dSYM folder is passed through" "$LOG" "$DSYM_DIR"
expect_contains "the org is wxyc" "$LOG" "SENTRY_ORG=wxyc"
expect_contains "the project is ios" "$LOG" "SENTRY_PROJECT=ios"
expect_contains "the token reaches sentry-cli" "$LOG" "SENTRY_AUTH_TOKEN=sntrys_supersecret"
# A build log is an artifact other people read. The token must never be in it.
expect_not_contains "the token is never echoed into the build log" "$OUT" "sntrys_supersecret"

# =========================================================================
# Case 5: sentry-cli runs and rejects the upload.
#
# The third silent path: a token that is expired, revoked, or scoped wrong
# produces a nonzero exit from a binary that is present, and the old phase
# folded that into a warning too.
# =========================================================================

echo ""
echo "=== Case 5: sentry-cli itself fails ==="

new_case "upload-fails-ci"
make_stub
STUB_FAIL=1
OUT=$(run_script "$DSYM_DIR" "TRUE" "sntrys_expired"); RC=$?
expect_exit "a rejected upload fails the CI build" "$RC" "1" "$OUT"
expect_contains "a rejected upload in CI is an error:" "$OUT" "error:"
expect_contains "sentry-cli's own message survives into the diagnostic" "$OUT" "org auth token is required"

new_case "upload-fails-local"
ordinary_build
make_stub
STUB_FAIL=1
OUT=$(run_script "$DSYM_DIR" "" "sntrys_expired"); RC=$?
expect_exit "a rejected upload locally still exits 0" "$RC" "0" "$OUT"
expect_contains "a rejected upload locally is a warning:" "$OUT" "warning:"
expect_not_contains "a rejected upload locally is not an error:" "$OUT" "error:"

# =========================================================================
# Case 6: what counts as CI.
#
# Xcode Cloud sets CI=TRUE. GitHub Actions sets CI=true. Neither of those is
# a value anyone should be pattern-matching by hand, and a bare `[ -n "$CI" ]`
# would read the literal string "false" as CI — which some tools do set.
#
# The fixture is a Release *build*, not an archive: an archive is strict
# wherever it runs, so it cannot tell the two answers apart. A non-archive
# shipping configuration is exactly the input whose outcome is decided by this
# question and nothing else.
# =========================================================================

echo ""
echo "=== Case 6: CI detection ==="

for ci_value in TRUE true True 1 YES; do
    new_case "ci-truthy-$ci_value"
    ordinary_build
    OUT=$(run_script "$DSYM_DIR" "$ci_value" "sntrys_fake"); RC=$?
    expect_exit "CI=$ci_value is treated as CI (missing cli fails)" "$RC" "1" "$OUT"
done

for ci_value in "" false FALSE 0 NO; do
    new_case "ci-falsy-${ci_value:-empty}"
    ordinary_build
    OUT=$(run_script "$DSYM_DIR" "$ci_value" "sntrys_fake"); RC=$?
    expect_exit "CI='${ci_value}' is treated as local (missing cli warns)" "$RC" "0" "$OUT"
done

# =========================================================================
# Case 7: which CI builds are strict. See is_shipping_build() for the rule and
# why it is a "Debug" prefix rather than an equality — the short version is
# that the scheme's TestAction builds "Debug TestFlight", so equality would
# make every test run strict and demand a token no test workflow has.
#
# Local builds are unaffected either way. A developer's Debug dSYMs are worth
# uploading — Sentry symbolicates simulator events from dev machines — and
# that behavior predates this script.
# =========================================================================

echo ""
echo "=== Case 7: strictness is scoped to shipping builds ==="

new_case "ci-debug-build"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI Debug build with dSYMs but no credentials still exits 0" "$RC" "0" "$OUT"
expect_not_contains "a CI Debug build does not error" "$OUT" "error:"
expect_not_contains "a CI Debug build does not warn either" "$OUT" "warning:"

new_case "ci-debug-build-skips-upload"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
make_stub
OUT=$(run_script "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "a CI Debug build exits 0 even with everything available" "$RC" "0" "$OUT"
expect_not_contains "a CI Debug build uploads nothing" "$(<"$STUB_LOG")" "debug-files"

# The scheme's TestAction configuration. Getting this wrong turns every
# `xcodebuild test` on a runner into a build failure demanding a Sentry token.
new_case "ci-debug-testflight-test"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI 'Debug TestFlight' test build with no token still exits 0" "$RC" "0" "$OUT"
expect_not_contains "a CI 'Debug TestFlight' build does not error" "$OUT" "error:"

new_case "ci-debug-testflight-skips-upload"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
make_stub
OUT=$(run_script "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "a CI 'Debug TestFlight' build exits 0 with everything available" "$RC" "0" "$OUT"
expect_not_contains "a CI 'Debug TestFlight' build uploads nothing" "$(<"$STUB_LOG")" "debug-files"

# TestFlight (no Debug prefix) is a distribution configuration and must stay
# strict — the prefix rule must not be read as "anything with TestFlight in
# the name".
new_case "ci-testflight-build"
CASE_CONFIGURATION="TestFlight"
CASE_ACTION="build"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI TestFlight build is strict" "$RC" "1" "$OUT"

new_case "ci-release-build"
CASE_CONFIGURATION="Release"
CASE_ACTION="build"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI Release build is strict even without the archive action" "$RC" "1" "$OUT"

new_case "ci-archive-debug-config"
CASE_CONFIGURATION="Debug"
CASE_ACTION="install"
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI archive is strict even at the Debug configuration" "$RC" "1" "$OUT"

# xcodebuild always sets both, but a hand-run script or a future Xcode Cloud
# change might not. An unknown build is treated as shipping: a spurious CI
# failure is loud and gets fixed, a skipped upload is silent and does not.
new_case "ci-unset-build-settings"
unset CASE_CONFIGURATION
unset CASE_ACTION
OUT=$(run_script "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI build with neither setting is treated as shipping" "$RC" "1" "$OUT"

new_case "local-debug-build"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
make_stub
OUT=$(run_script "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "a local Debug build still exits 0" "$RC" "0" "$OUT"
expect_contains "a local Debug build still uploads, as it did before" "$(<"$STUB_LOG")" "debug-files"

# =========================================================================
# Case 8: the on-disk CI marker.
#
# Everything above turns on $CI reaching this script, and a run-script phase
# nested inside xcodebuild is exactly the hop install-sentry-cli.sh refuses to
# bet the token on (its header makes the argument). So ci_post_clone.sh drops a
# marker file in the checkout, and these cases pin strictness to the file
# independently of $CI.
#
# As in Case 6 the fixture is a Release build rather than an archive, so that
# the marker is the only thing deciding the outcome.
# =========================================================================

echo ""
echo "=== Case 8: the .ci-tools/ci-runner marker ==="

new_case "marker-without-ci-env"
ordinary_build
mark_ci_runner
OUT=$(run_script "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "the marker alone makes a shipping build strict, with CI unset" "$RC" "1" "$OUT"
expect_contains "the marker path produces an error:" "$OUT" "error:"
# This input has a second reading, and it is the likelier one on a laptop:
# ci_post_clone.sh writes the marker before it does anything else and nothing
# ever removes it, so a developer who ran that script once to install
# macros.json answers is_ci forever — and then a plain local Release build
# fails, citing Xcode Cloud. Naming the file is the difference between a
# one-command fix and a mystery, and the issue navigator shows only this line.
expect_contains "a marker with no CI in the environment says which file to delete" "$OUT" ".ci-tools/ci-runner"

new_case "marker-with-ci-false"
ordinary_build
mark_ci_runner
OUT=$(run_script "$DSYM_DIR" "false" "sntrys_fake"); RC=$?
expect_exit "the marker outranks a CI=false that never got cleared" "$RC" "1" "$OUT"

# The marker must not make a non-shipping build strict either — it answers
# "where am I", not "does this build ship".
new_case "marker-debug-testflight"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
mark_ci_runner
OUT=$(run_script "$DSYM_DIR" "" ""); RC=$?
expect_exit "the marker does not make a test build strict" "$RC" "0" "$OUT"
expect_not_contains "the marker does not error a test build" "$OUT" "error:"

# And a dev Mac that happens to have a .ci-tools/bin from running the
# installer by hand is not a CI runner.
new_case "vendored-cli-is-not-a-marker"
ordinary_build
make_stub
STUB_FAIL=1
OUT=$(run_script "$DSYM_DIR" "" "sntrys_expired"); RC=$?
expect_exit "a vendored sentry-cli by itself does not imply CI" "$RC" "0" "$OUT"
expect_contains "a local failure with a vendored cli is still a warning:" "$OUT" "warning:"

# =========================================================================
# Case 9: a local archive is strict.
#
# Everything above this case was written for a project that archives on a
# runner. WXYC does not: archives are made from Product > Archive on a dev Mac,
# and the manifest of the 2026-08-11 archive shows the phase ran with
# ACTION=install, CONFIGURATION=Release and no CI in the environment — so it
# took the lenient path, and every failure #955 set out to make loud was a
# `warning:` on the one build that actually ships.
#
# So strictness follows the archive, not the runner. The upload has to work for
# an archive to be made, wherever it is made.
#
# The diagnostics split too. Xcode's issue navigator shows one line; a dev Mac
# told to "check that ci_post_clone ran" has been handed a dead end, and a
# runner told to run Homebrew has as well.
# =========================================================================

echo ""
echo "=== Case 9: a local archive is strict ==="

new_case "local-archive-no-cli"
OUT=$(run_script "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "a local archive with no sentry-cli fails the build" "$RC" "1" "$OUT"
expect_contains "a local archive with no sentry-cli is an error:" "$OUT" "error:"
expect_contains "the local diagnostic names the local fix" "$OUT" "brew install getsentry/tools/sentry-cli"
expect_not_contains "the local diagnostic does not send a dev Mac to ci_post_clone" "$OUT" "ci_post_clone"
# The archive is strict on its own account here. There is no marker to blame,
# so mentioning one would send the reader after a file that isn't there.
expect_not_contains "an archive strict on its own account mentions no marker" "$OUT" ".ci-tools/ci-runner"

new_case "local-archive-no-token"
make_stub
OUT=$(run_script "$DSYM_DIR" "" ""); RC=$?
expect_exit "a local archive with no credentials fails the build" "$RC" "1" "$OUT"
expect_contains "a local archive with no credentials is an error:" "$OUT" "error:"
expect_contains "the local credential diagnostic names .sentryclirc" "$OUT" ".sentryclirc"
expect_not_contains "the local credential diagnostic does not send a dev Mac to Xcode Cloud" "$OUT" "Xcode Cloud"
# The build this message is written for is Product > Archive, and Xcode.app
# launched from the Dock inherits launchd's environment rather than a login
# shell's — so "just export SENTRY_AUTH_TOKEN", offered without that caveat, is
# advice that does nothing for the reader most likely to be reading it.
expect_contains "the local credential diagnostic flags that a shell export misses Xcode.app" "$OUT" "Xcode.app"
expect_not_contains "no upload is attempted without credentials" "$(<"$STUB_LOG")" "debug-files"

new_case "local-archive-no-dsyms"
OUT=$(run_script "$EMPTY_DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "a local archive that produced no dSYMs fails the build" "$RC" "1" "$OUT"
expect_contains "an empty dSYM folder on a local archive is an error:" "$OUT" "error:"

new_case "local-archive-upload-fails"
make_stub
STUB_FAIL=1
OUT=$(run_script "$DSYM_DIR" "" "sntrys_expired"); RC=$?
expect_exit "a rejected upload fails a local archive" "$RC" "1" "$OUT"
expect_contains "a rejected upload on a local archive is an error:" "$OUT" "error:"
expect_contains "sentry-cli's own message survives into the local diagnostic" "$OUT" "org auth token is required"

new_case "local-archive-ok"
make_stub
OUT=$(run_script "$DSYM_DIR" "" "sntrys_local"); RC=$?
expect_exit "a local archive that uploads cleanly exits 0" "$RC" "0" "$OUT"
expect_contains "a local archive uploads the dSYMs" "$(<"$STUB_LOG")" "debug-files upload"
expect_contains "a local archive says so in the build log" "$OUT" "note: uploaded debug symbols"

# Only the archive. Everything else a developer builds stays lenient, which is
# the constraint #955 was given: the phase runs on every build, and it must not
# break a local build on a machine without sentry-cli. "Release (Active Arch)"
# is a developer-local fast-build variant of Release, and a plain Release build
# is something people do to check optimized behavior — neither is a ship.
for config in "Release" "Release (Active Arch)" "TestFlight" "Debug" "Debug TestFlight"; do
    new_case "local-build-${config// /-}"
    CASE_CONFIGURATION="$config"
    CASE_ACTION="build"
    OUT=$(run_script "$DSYM_DIR" "" ""); RC=$?
    expect_exit "a local '$config' build with no credentials still exits 0" "$RC" "0" "$OUT"
    expect_not_contains "a local '$config' build does not error" "$OUT" "error:"
    # Exit 0 alone cannot tell leniency apart from skipping the upload
    # altogether, and those are different behaviors: a local build is supposed
    # to still try, because a developer's simulator crashes reach Sentry too.
    # No stub on PATH here, so reaching the sentry-cli check is the proof.
    expect_contains "a local '$config' build still evaluates the upload" "$OUT" "warning: sentry-cli not installed"
done

# The unknown-build case points the other way locally than it does on CI (Case
# 7): a build with no ACTION is not an archive, and the reason to treat an
# unknown CI build as shipping — a spurious failure is loud and gets fixed —
# does not apply to a developer's machine, where the same guess would fail
# builds nobody can explain.
new_case "local-unset-build-settings"
unset CASE_CONFIGURATION
unset CASE_ACTION
OUT=$(run_script "$DSYM_DIR" "" ""); RC=$?
expect_exit "a local build with neither setting still exits 0" "$RC" "0" "$OUT"
expect_not_contains "a local build with neither setting does not error" "$OUT" "error:"

# =========================================================================
# Case 10: a sentry-cli that PATH cannot see.
#
# The build this whole strictness rule exists for starts in Xcode.app, which
# inherits launchd's environment and not a login shell's. The manifest of the
# 2026-08-11 archive records what the phase's PATH actually was: the Xcode
# toolchain directories, then /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin.
# Homebrew on Apple Silicon installs into /opt/homebrew/bin, which is not on
# that list.
#
# So `command -v` alone would fail to find a sentry-cli installed by the exact
# command this script's own diagnostic recommends, and the developer who
# followed it would get the same error: again — install the tool you just
# installed — with no archive and no way out of the loop. The upload has to
# look in the prefixes the GUI's PATH omits.
# =========================================================================

echo ""
echo "=== Case 10: sentry-cli outside the build phase's PATH ==="

new_case "cli-outside-path"
BREW_PREFIX_BIN="$CASE_SRCROOT/../opt-homebrew-bin"
mkdir -p "$BREW_PREFIX_BIN"
make_stub "$BREW_PREFIX_BIN"
CASE_SEARCH_DIRS="$BREW_PREFIX_BIN"
OUT=$(run_script "$DSYM_DIR" "" "sntrys_local"); RC=$?
expect_exit "a local archive finds a sentry-cli that is on no PATH it inherits" "$RC" "0" "$OUT"
expect_contains "and uploads with it" "$(<"$STUB_LOG")" "debug-files upload"
expect_contains "the binary it ran is the one outside PATH" "$(<"$STUB_LOG")" "$BREW_PREFIX_BIN/sentry-cli"

# Precedence, not just reachability. A runner has both: the pinned copy
# install-sentry-cli.sh vendored into the checkout, and whatever the image
# happens to carry. The pinned one has to win, or the version this project
# controls is decided by the image.
new_case "vendored-cli-outranks-search-dirs"
BREW_PREFIX_BIN="$CASE_SRCROOT/../opt-homebrew-bin"
mkdir -p "$BREW_PREFIX_BIN"
make_stub "$BREW_PREFIX_BIN"
make_stub
CASE_SEARCH_DIRS="$BREW_PREFIX_BIN"
OUT=$(run_script "$DSYM_DIR" "" "sntrys_local"); RC=$?
expect_contains "the vendored copy is the one that runs" "$(<"$STUB_LOG")" "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
expect_not_contains "the searched prefix is not consulted when a vendored copy exists" "$(<"$STUB_LOG")" "$BREW_PREFIX_BIN/sentry-cli"

# The cases above prove the mechanism against a fixture directory, which is the
# only way they can stay hermetic. What they cannot check is the list the script
# actually ships with — and that list is the entire fix, since a search path
# without the Apple Silicon Homebrew prefix in it resolves nothing new.
expect_contains "the shipped search list carries the Apple Silicon Homebrew prefix" "$(<"$REAL_SCRIPT")" "/opt/homebrew/bin"

summarize
