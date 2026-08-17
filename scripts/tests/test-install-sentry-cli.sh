#!/bin/zsh
#
# test-install-sentry-cli.sh
#
# Black-box regression test for ci_scripts/install-sentry-cli.sh — the script
# that puts a sentry-cli on an Xcode Cloud runner and gives it something to
# authenticate with, so the "Upload Debug Symbols to Sentry" build phase has
# both halves it needs (#955).
#
# The download itself is stubbed. The script takes SENTRY_CLI_INSTALLER as a
# path to the installer to run, defaulting to a fresh copy of
# https://sentry.io/get-cli/; the tests hand it a fake that writes a stub
# binary. That keeps the suite hermetic (no network, no 15MB download, no
# real auth token) while still exercising the parts that can actually break:
# version pinning, idempotency, where the binary lands, and the credential
# file's contents and mode.
#
# HOME is redirected into the fixture for every case. The script writes
# ~/.sentryclirc, and a test suite that clobbers a developer's real Sentry
# token would be worse than no test at all.
#
# Run directly:
#   zsh scripts/tests/test-install-sentry-cli.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
REAL_SCRIPT="${REPO_ROOT}/ci_scripts/install-sentry-cli.sh"

if [[ ! -f "$REAL_SCRIPT" ]]; then
    echo "Cannot find ci_scripts/install-sentry-cli.sh at $REAL_SCRIPT" >&2
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

expect_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$desc"
    else
        fail "$desc" "expected: $expected" "actual:   $actual"
    fi
}

FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Fake installer standing in for https://sentry.io/get-cli/. Honors the same
# two env vars the real one does — SENTRY_CLI_VERSION and INSTALL_DIR — and
# writes a stub that reports whichever version it was asked for, so a
# version-pin mismatch can be simulated by asking it to lie.
FAKE_INSTALLER="$FIXTURE/fake-get-cli.sh"
cat > "$FAKE_INSTALLER" <<'INSTALLER'
#!/bin/sh
set -eu
: "${INSTALL_DIR:?fake installer requires INSTALL_DIR}"
: "${SENTRY_CLI_VERSION:?fake installer requires SENTRY_CLI_VERSION}"
# The real installer refuses to overwrite an existing binary; mirror that so
# the idempotency path is tested against the same constraint.
if [ -f "$INSTALL_DIR/sentry-cli" ]; then
    echo "error: sentry-cli is already installed."
    exit 1
fi
mkdir -p "$INSTALL_DIR"
REPORTED="${FAKE_REPORTED_VERSION:-$SENTRY_CLI_VERSION}"
cat > "$INSTALL_DIR/sentry-cli" <<STUB
#!/bin/sh
if [ "\$1" = "--version" ]; then echo "sentry-cli $REPORTED"; exit 0; fi
exit 0
STUB
chmod +x "$INSTALL_DIR/sentry-cli"
echo "fake installer: wrote sentry-cli $REPORTED to $INSTALL_DIR"
INSTALLER
chmod +x "$FAKE_INSTALLER"

# An installer that fails outright — the network-down / release-yanked case.
FAILING_INSTALLER="$FIXTURE/failing-get-cli.sh"
cat > "$FAILING_INSTALLER" <<'INSTALLER'
#!/bin/sh
echo "error: your platform and architecture is unsupported." >&2
exit 1
INSTALLER
chmod +x "$FAILING_INSTALLER"

PIN="4.2.1"

run_install() {
    # usage: run_install <home> <repo-root> <token> [extra args...]
    local home="$1" root="$2" token="$3"
    shift 3
    env -i \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$home" \
        SENTRY_CLI_VERSION="$PIN" \
        SENTRY_CLI_INSTALLER="${INSTALLER_OVERRIDE:-$FAKE_INSTALLER}" \
        SENTRY_CLI_INSTALL_DIR="$root/.ci-tools/bin" \
        SENTRY_AUTH_TOKEN="$token" \
        FAKE_REPORTED_VERSION="${FAKE_REPORTED_VERSION:-}" \
        /bin/zsh "$REAL_SCRIPT" "$@" 2>&1
}

new_case() {
    local name="$1"
    CASE_HOME="$FIXTURE/$name/home"
    CASE_ROOT="$FIXTURE/$name/repo"
    mkdir -p "$CASE_HOME" "$CASE_ROOT"
    INSTALLER_OVERRIDE=""
    FAKE_REPORTED_VERSION=""
}

# =========================================================================
# Case 1: a clean runner. Binary lands where the build phase looks for it,
# and the token becomes a config file sentry-cli will read.
# =========================================================================

echo "=== Case 1: clean install with a token ==="

new_case "clean"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_supersecret"); RC=$?
expect_exit "a clean install succeeds" "$RC" "0" "$OUT"

if [[ -x "$CASE_ROOT/.ci-tools/bin/sentry-cli" ]]; then
    ok "sentry-cli is installed at .ci-tools/bin/sentry-cli, executable"
else
    fail "sentry-cli is installed at .ci-tools/bin/sentry-cli, executable" "${(f)OUT}"
fi

expect_contains "the pinned version is passed to the installer" "$OUT" "$PIN"

# The auth token has to survive into something sentry-cli reads. Xcode Cloud
# environment variables are not guaranteed to reach a build phase inside
# xcodebuild, so ~/.sentryclirc is the path that does not depend on that.
RC_FILE="$CASE_HOME/.sentryclirc"
if [[ -f "$RC_FILE" ]]; then
    ok "~/.sentryclirc is written"
    expect_contains "the rc file carries the [auth] section" "$(<"$RC_FILE")" "[auth]"
    expect_contains "the rc file carries the token" "$(<"$RC_FILE")" "token=sntrys_supersecret"
    MODE=$(stat -f "%Lp" "$RC_FILE")
    expect_eq "the rc file is mode 600" "$MODE" "600"
else
    fail "~/.sentryclirc is written" "${(f)OUT}"
fi

# The build log of an Xcode Cloud run is visible to everyone with App Store
# Connect access. Xcode Cloud redacts values it knows are secret, but a
# script that prints its own token is not something to rely on redaction for.
expect_not_contains "the token is never echoed" "$OUT" "sntrys_supersecret"

# =========================================================================
# Case 2: idempotency. ci_post_clone.sh can run more than once against the
# same checkout, and the upstream installer hard-errors on an existing
# binary — so a second run must recognize the pinned version and stop.
# =========================================================================

echo ""
echo "=== Case 2: second run over an existing install ==="

new_case "idempotent"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_a"); RC=$?
expect_exit "first run succeeds" "$RC" "0" "$OUT"
OUT2=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_a"); RC2=$?
expect_exit "second run succeeds instead of tripping over the existing binary" "$RC2" "0" "$OUT2"
expect_not_contains "the second run does not report an installer error" "$OUT2" "already installed."

# An existing binary at the wrong version is a stale runner cache, not a
# reason to skip: the pin is the point.
new_case "stale-version"
FAKE_REPORTED_VERSION="1.0.0"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_a"); RC=$?
expect_exit "an install that reports the wrong version fails loudly" "$RC" "1" "$OUT"
expect_contains "the version mismatch is an error:" "$OUT" "error:"
expect_contains "the mismatch names the version it got" "$OUT" "1.0.0"

# =========================================================================
# Case 3: an existing ~/.sentryclirc is never clobbered. The script is
# runnable on a dev Mac (that is how you reproduce a CI failure locally) and
# a developer's own token must survive it.
# =========================================================================

echo ""
echo "=== Case 3: pre-existing ~/.sentryclirc ==="

new_case "existing-rc"
printf '[auth]\ntoken=sntrys_mine\n' > "$CASE_HOME/.sentryclirc"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_from_env"); RC=$?
expect_exit "the run succeeds with an existing rc file" "$RC" "0" "$OUT"
expect_contains "the developer's own token is left in place" "$(<"$CASE_HOME/.sentryclirc")" "sntrys_mine"
expect_not_contains "the environment token did not overwrite it" "$(<"$CASE_HOME/.sentryclirc")" "sntrys_from_env"

# =========================================================================
# Case 4: no token.
#
# Default is a warning: most Xcode Cloud workflows only build and test, and
# killing those over a missing upload credential would be its own silent-tax.
# --require-auth is what an archive workflow passes to turn it into a hard
# failure at minute zero rather than twenty minutes later in the build phase.
# =========================================================================

echo ""
echo "=== Case 4: missing SENTRY_AUTH_TOKEN ==="

new_case "no-token"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" ""); RC=$?
expect_exit "a missing token is not fatal by default" "$RC" "0" "$OUT"
expect_contains "a missing token warns" "$OUT" "warning:"
if [[ -f "$CASE_HOME/.sentryclirc" ]]; then
    fail "no rc file is written without a token" "found $CASE_HOME/.sentryclirc"
else
    ok "no rc file is written without a token"
fi

new_case "no-token-required"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "" --require-auth); RC=$?
expect_exit "--require-auth turns a missing token into a failure" "$RC" "1" "$OUT"
expect_contains "the missing token is an error: under --require-auth" "$OUT" "error:"
expect_contains "the error names the variable to set" "$OUT" "SENTRY_AUTH_TOKEN"

# --require-auth is about credentials, not about breaking a working install.
new_case "token-required-present"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_present" --require-auth); RC=$?
expect_exit "--require-auth with a token present succeeds" "$RC" "0" "$OUT"

# =========================================================================
# Case 5: the download fails. Nothing usable must be left behind claiming to
# be sentry-cli, and the exit status has to say so.
# =========================================================================

echo ""
echo "=== Case 5: the installer itself fails ==="

new_case "installer-fails"
INSTALLER_OVERRIDE="$FAILING_INSTALLER"
OUT=$(run_install "$CASE_HOME" "$CASE_ROOT" "sntrys_a"); RC=$?
expect_exit "a failed download exits nonzero" "$RC" "1" "$OUT"
expect_contains "a failed download is an error:" "$OUT" "error:"
if [[ -e "$CASE_ROOT/.ci-tools/bin/sentry-cli" ]]; then
    fail "no half-installed binary is left behind" "found $CASE_ROOT/.ci-tools/bin/sentry-cli"
else
    ok "no half-installed binary is left behind"
fi

# =========================================================================
# Summary
# =========================================================================

echo ""
echo "=== $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
    exit 1
fi
exit 0
