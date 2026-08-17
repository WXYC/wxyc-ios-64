#!/bin/zsh
#
# test-upload-debug-symbols.sh
#
# Black-box regression test for scripts/upload-debug-symbols.sh — the script
# the "Upload Debug Symbols to Sentry" build phase runs.
#
# The behavior under test is the CI/local asymmetry (#955). Before that
# issue, the whole thing was four lines inlined in project.pbxproj and every
# failure path — no binary, no credentials, a rejected upload — degraded to a
# `warning:`. On a dev Mac that is right: a local Debug build must not fail
# because somebody hasn't installed sentry-cli. On an Xcode Cloud runner it is
# exactly wrong: the archive ships, the build stays green, and every Release
# event in Sentry loses its function names with no visible error anywhere.
#
# So the contract has two halves and both need pinning:
#   local (CI unset)  — every failure is a warning, exit 0, build continues
#   CI    (CI set)    — every failure is an error, exit 1, build stops
# plus one shared guard: a build that produced no dSYMs at all (any Debug
# build, where DEBUG_INFORMATION_FORMAT is plain `dwarf`) has nothing to
# upload and must not fail on either side.
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

typeset -g PASS=0
typeset -g FAIL=0

ok() {
    PASS=$((PASS + 1))
    echo "ok - $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL - $1"
    shift
    for line in "$@"; do
        echo "    $line"
    done
}

expect_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc" "expected to contain: $needle" "--- actual ---" "${(f)haystack}" "--------------"
    fi
}

expect_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc" "expected NOT to contain: $needle" "--- actual ---" "${(f)haystack}" "--------------"
    fi
}

expect_exit() {
    local desc="$1" actual="$2" expected="$3" out="$4"
    if [[ "$actual" == "$expected" ]]; then
        ok "$desc"
    else
        fail "$desc" "expected exit $expected, got $actual" "--- actual ---" "${(f)out}" "--------------"
    fi
}

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
    local stub_path="$1"
    mkdir -p "${stub_path:h}"
    cat > "$stub_path" <<'STUB'
#!/bin/sh
if [ "$1" = "--version" ]; then
    echo "sentry-cli 9.9.9"
    exit 0
fi
{
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

# Runs the real script in a hermetic environment. Every knob the script reads
# is passed explicitly; PATH is narrowed to the system directories so a real
# sentry-cli in /usr/local/bin can never satisfy a case that is meant to run
# without one.
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
    local -a build_settings=()
    [[ -n "${CASE_CONFIGURATION+set}" ]] && build_settings+=("CONFIGURATION=${CASE_CONFIGURATION}")
    [[ -n "${CASE_ACTION+set}" ]] && build_settings+=("ACTION=${CASE_ACTION}")

    env -i \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$1" \
        SRCROOT="$2" \
        DWARF_DSYM_FOLDER_PATH="$3" \
        CI="$4" \
        SENTRY_AUTH_TOKEN="$5" \
        "${build_settings[@]}" \
        STUB_LOG="${STUB_LOG:-}" \
        STUB_FAIL="${STUB_FAIL:-}" \
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
    CASE_CONFIGURATION="Release"
    CASE_ACTION="install"
}

# =========================================================================
# Case 1: no dSYMs.
#
# Locally, and on any CI build that cannot ship, this is unremarkable: there
# is nothing to upload, so there is nothing to say. On a CI build that *does*
# ship it is the opposite — every WXYC configuration sets
# DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an archive with an empty
# DWARF_DSYM_FOLDER_PATH means something upstream broke (a flipped build
# setting, a dsymutil failure, a moved path) and the archive is about to ship
# unsymbolicated. Skipping quietly there is the #955 failure mode wearing a
# different hat.
# =========================================================================

echo "=== Case 1: build produced no dSYMs ==="

new_case "no-dsyms-local"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$EMPTY_DSYM_DIR" "" ""); RC=$?
expect_exit "empty dSYM folder locally exits 0" "$RC" "0" "$OUT"
expect_not_contains "empty dSYM folder locally emits no error:" "$OUT" "error:"
expect_not_contains "empty dSYM folder locally emits no warning:" "$OUT" "warning:"

new_case "no-dsym-path-local"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "" "" ""); RC=$?
expect_exit "unset DWARF_DSYM_FOLDER_PATH locally exits 0" "$RC" "0" "$OUT"
expect_not_contains "unset DWARF_DSYM_FOLDER_PATH locally emits no error:" "$OUT" "error:"

new_case "no-dsyms-ci-nonshipping"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$EMPTY_DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "empty dSYM folder on a non-shipping CI build exits 0" "$RC" "0" "$OUT"
expect_not_contains "empty dSYM folder on a non-shipping CI build emits no error:" "$OUT" "error:"

new_case "no-dsyms-ci-archive"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$EMPTY_DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "an archive that produced no dSYMs fails the build" "$RC" "1" "$OUT"
expect_contains "an archive with no dSYMs is an error:" "$OUT" "error:"
expect_contains "the error names the folder it found empty" "$OUT" "$EMPTY_DSYM_DIR"

new_case "no-dsym-path-ci-archive"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "" "TRUE" "sntrys_fake"); RC=$?
expect_exit "an archive with no DWARF_DSYM_FOLDER_PATH at all fails the build" "$RC" "1" "$OUT"
expect_contains "the missing dSYM folder is an error:" "$OUT" "error:"

new_case "missing-dsym-dir-ci-archive"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$FIXTURE/does-not-exist" "TRUE" "sntrys_fake"); RC=$?
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
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "missing sentry-cli in CI fails the build" "$RC" "1" "$OUT"
expect_contains "missing sentry-cli in CI is an error:" "$OUT" "error:"
expect_contains "the error names sentry-cli" "$OUT" "sentry-cli"
expect_contains "the error points at the installer script" "$OUT" "ci_scripts/install-sentry-cli.sh"

new_case "no-cli-local"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" "sntrys_fake"); RC=$?
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
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "missing token in CI fails the build" "$RC" "1" "$OUT"
expect_contains "missing token in CI is an error:" "$OUT" "error:"
expect_contains "the error names the env var to set" "$OUT" "SENTRY_AUTH_TOKEN"
NOTOKEN_LOG=$(<"$STUB_LOG")
expect_not_contains "sentry-cli is not invoked at all without credentials" "$NOTOKEN_LOG" "debug-files"

new_case "no-token-local"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" ""); RC=$?
expect_exit "missing token locally still exits 0" "$RC" "0" "$OUT"
expect_contains "missing token locally is a warning:" "$OUT" "warning:"
expect_not_contains "missing token locally is not an error:" "$OUT" "error:"

# A repo-root .sentryclirc is how every dev Mac authenticates today. It must
# keep counting as credentials, with no SENTRY_AUTH_TOKEN in the environment.
new_case "sentryclirc-in-srcroot"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
printf '[auth]\ntoken=sntrys_from_srcroot\n' > "$CASE_SRCROOT/.sentryclirc"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a .sentryclirc in SRCROOT counts as credentials" "$RC" "0" "$OUT"
expect_contains "the upload runs on the strength of .sentryclirc alone" "$(<"$STUB_LOG")" "debug-files"

# ~/.sentryclirc is what ci_scripts/install-sentry-cli.sh materializes on the
# runner, and it has to be honored even when the token never reaches the
# xcodebuild environment.
new_case "sentryclirc-in-home"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
printf '[auth]\ntoken=sntrys_from_home\n' > "$CASE_HOME/.sentryclirc"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a ~/.sentryclirc counts as credentials" "$RC" "0" "$OUT"
expect_contains "the upload runs on the strength of ~/.sentryclirc alone" "$(<"$STUB_LOG")" "debug-files"

# =========================================================================
# Case 4: the happy path — what the upload is actually invoked with.
# =========================================================================

echo ""
echo "=== Case 4: successful upload ==="

new_case "upload-ok"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" "sntrys_supersecret"); RC=$?
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
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
STUB_FAIL=1
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" "sntrys_expired"); RC=$?
expect_exit "a rejected upload fails the CI build" "$RC" "1" "$OUT"
expect_contains "a rejected upload in CI is an error:" "$OUT" "error:"
expect_contains "sentry-cli's own message survives into the diagnostic" "$OUT" "org auth token is required"

new_case "upload-fails-local"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
STUB_FAIL=1
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" "sntrys_expired"); RC=$?
expect_exit "a rejected upload locally still exits 0" "$RC" "0" "$OUT"
expect_contains "a rejected upload locally is a warning:" "$OUT" "warning:"
expect_not_contains "a rejected upload locally is not an error:" "$OUT" "error:"

# =========================================================================
# Case 6: what counts as CI.
#
# Xcode Cloud sets CI=TRUE. GitHub Actions sets CI=true. Neither of those is
# a value anyone should be pattern-matching by hand, and a bare `[ -n "$CI" ]`
# would read the literal string "false" as CI — which some tools do set.
# =========================================================================

echo ""
echo "=== Case 6: CI detection ==="

for ci_value in TRUE true True 1 YES; do
    new_case "ci-truthy-$ci_value"
    OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "$ci_value" "sntrys_fake"); RC=$?
    expect_exit "CI=$ci_value is treated as CI (missing cli fails)" "$RC" "1" "$OUT"
done

for ci_value in "" false FALSE 0 NO; do
    new_case "ci-falsy-${ci_value:-empty}"
    OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "$ci_value" "sntrys_fake"); RC=$?
    expect_exit "CI='${ci_value}' is treated as local (missing cli warns)" "$RC" "0" "$OUT"
done

# =========================================================================
# Case 7: which CI builds are strict.
#
# The tempting rule — "CI plus a dSYM means fail" — is wrong for this project.
# WXYC builds Debug with DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so a
# plain `xcodebuild build` for the simulator populates DWARF_DSYM_FOLDER_PATH
# just like an archive does. Under that rule every Xcode Cloud test workflow
# would need a Sentry token or fail, which is a self-inflicted outage waiting
# for the day somebody adds a workflow and forgets.
#
# So strictness is scoped to builds that can actually ship — an archive
# (ACTION=install) or a configuration whose name does not begin with "Debug".
# A CI build that is neither skips the upload outright: those runners never
# report events to Sentry, so their dSYMs are pure noise in the debug-file
# list.
#
# The prefix, not equality, is the load-bearing part. This project has five
# configurations — Debug, "Debug TestFlight", TestFlight, Release, and
# "Release (Active Arch)" — and the shared scheme's TestAction builds
# "Debug TestFlight". An `xcodebuild test -scheme WXYC` with no explicit
# -configuration (what scripts/test-affected.sh runs, and what an Xcode Cloud
# test workflow runs) therefore lands on a configuration that is not literally
# "Debug" but is emphatically not shipping.
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
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI Debug build with dSYMs but no credentials still exits 0" "$RC" "0" "$OUT"
expect_not_contains "a CI Debug build does not error" "$OUT" "error:"
expect_not_contains "a CI Debug build does not warn either" "$OUT" "warning:"

new_case "ci-debug-build-skips-upload"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "a CI Debug build exits 0 even with everything available" "$RC" "0" "$OUT"
expect_not_contains "a CI Debug build uploads nothing" "$(<"$STUB_LOG")" "debug-files"

# The scheme's TestAction configuration. Getting this wrong turns every
# `xcodebuild test` on a runner into a build failure demanding a Sentry token.
new_case "ci-debug-testflight-test"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI 'Debug TestFlight' test build with no token still exits 0" "$RC" "0" "$OUT"
expect_not_contains "a CI 'Debug TestFlight' build does not error" "$OUT" "error:"

new_case "ci-debug-testflight-skips-upload"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" "sntrys_fake"); RC=$?
expect_exit "a CI 'Debug TestFlight' build exits 0 with everything available" "$RC" "0" "$OUT"
expect_not_contains "a CI 'Debug TestFlight' build uploads nothing" "$(<"$STUB_LOG")" "debug-files"

# TestFlight (no Debug prefix) is a distribution configuration and must stay
# strict — the prefix rule must not be read as "anything with TestFlight in
# the name".
new_case "ci-testflight-build"
CASE_CONFIGURATION="TestFlight"
CASE_ACTION="build"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI TestFlight build is strict" "$RC" "1" "$OUT"

new_case "ci-release-build"
CASE_CONFIGURATION="Release"
CASE_ACTION="build"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI Release build is strict even without the archive action" "$RC" "1" "$OUT"

new_case "ci-archive-debug-config"
CASE_CONFIGURATION="Debug"
CASE_ACTION="install"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI archive is strict even at the Debug configuration" "$RC" "1" "$OUT"

# xcodebuild always sets both, but a hand-run script or a future Xcode Cloud
# change might not. An unknown build is treated as shipping: a spurious CI
# failure is loud and gets fixed, a skipped upload is silent and does not.
new_case "ci-unset-build-settings"
unset CASE_CONFIGURATION
unset CASE_ACTION
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "TRUE" ""); RC=$?
expect_exit "a CI build with neither setting is treated as shipping" "$RC" "1" "$OUT"

new_case "local-debug-build"
CASE_CONFIGURATION="Debug"
CASE_ACTION="build"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "a local Debug build still exits 0" "$RC" "0" "$OUT"
expect_contains "a local Debug build still uploads, as it did before" "$(<"$STUB_LOG")" "debug-files"

# =========================================================================
# Case 8: the on-disk CI marker.
#
# Everything above turns on $CI reaching this script. That is the same
# assumption ci_scripts/install-sentry-cli.sh deliberately refuses to make
# about SENTRY_AUTH_TOKEN — Xcode Cloud documents its environment variables as
# reaching custom build scripts, not as surviving into a run-script phase
# nested inside xcodebuild. If $CI does not make that hop, every strict path
# above quietly reverts to `warning:` + exit 0 and the archive ships
# unsymbolicated with a green build: #955 again, this time with a test suite
# asserting it was fixed.
#
# So ci_post_clone.sh drops a marker file in the checkout, where nothing has
# to propagate for the build phase to find it.
# =========================================================================

echo ""
echo "=== Case 8: the .ci-tools/ci-runner marker ==="

new_case "marker-without-ci-env"
mkdir -p "$CASE_SRCROOT/.ci-tools"
: > "$CASE_SRCROOT/.ci-tools/ci-runner"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" "sntrys_fake"); RC=$?
expect_exit "the marker alone makes an archive strict, with CI unset" "$RC" "1" "$OUT"
expect_contains "the marker path produces an error:" "$OUT" "error:"

new_case "marker-with-ci-false"
mkdir -p "$CASE_SRCROOT/.ci-tools"
: > "$CASE_SRCROOT/.ci-tools/ci-runner"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "false" "sntrys_fake"); RC=$?
expect_exit "the marker outranks a CI=false that never got cleared" "$RC" "1" "$OUT"

# The marker must not make a non-shipping build strict either — it answers
# "where am I", not "does this build ship".
new_case "marker-debug-testflight"
CASE_CONFIGURATION="Debug TestFlight"
CASE_ACTION="build"
mkdir -p "$CASE_SRCROOT/.ci-tools"
: > "$CASE_SRCROOT/.ci-tools/ci-runner"
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" ""); RC=$?
expect_exit "the marker does not make a test build strict" "$RC" "0" "$OUT"
expect_not_contains "the marker does not error a test build" "$OUT" "error:"

# And a dev Mac that happens to have a .ci-tools/bin from running the
# installer by hand is not a CI runner.
new_case "vendored-cli-is-not-a-marker"
make_stub "$CASE_SRCROOT/.ci-tools/bin/sentry-cli"
STUB_FAIL=1
OUT=$(run_script "$CASE_HOME" "$CASE_SRCROOT" "$DSYM_DIR" "" "sntrys_expired"); RC=$?
expect_exit "a vendored sentry-cli by itself does not imply CI" "$RC" "0" "$OUT"
expect_contains "a local failure with a vendored cli is still a warning:" "$OUT" "warning:"

# =========================================================================
# Summary
# =========================================================================

echo ""
echo "=== $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
    exit 1
fi
exit 0
