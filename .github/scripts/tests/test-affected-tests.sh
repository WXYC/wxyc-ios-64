#!/bin/zsh
#
# test-affected-tests.sh
#
# Black-box regression tests for .github/scripts/affected-tests.sh. Each test
# invokes the real script as a subprocess (or sources it, for the output()
# isolation cases) against a controlled BASE_REF/CHANGED_FILES/git-history
# fixture and asserts on stdout, $GITHUB_OUTPUT contents, and exit code.
#
# No test framework dependency (bats etc. aren't vendored here) — this mirrors
# the hand-rolled style of scripts/tests/test_wxyc_utils.rb: plain assertions,
# a pass/fail counter, a TAP-ish log, nonzero exit on any failure.
#
# Run directly:
#   zsh .github/scripts/tests/test-affected-tests.sh
#
# Covers:
#   - #362 item 2: whitespace-only CHANGED_FILES is treated as "no changed
#     files" (run-all with a clear reason), not silently threaded through as
#     if it named a real file.
#   - #362 item 3: the output() helper rejects a multi-line value instead of
#     letting it corrupt the KEY=VALUE $GITHUB_OUTPUT format that
#     scripts/test-affected.sh's parser assumes.

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
SCRIPT="${SCRIPT_DIR}/../affected-tests.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "Cannot find affected-tests.sh at $SCRIPT" >&2
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

expect_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$desc"
    else
        fail "$desc" "expected: $expected" "actual:   $actual"
    fi
}

# -----------------------------------------------------------------------
# run_script — invokes affected-tests.sh as a subprocess with the given
# BASE_REF / CHANGED_FILES (unset when CHANGED_FILES_SET=0) from CWD, and
# captures combined stdout+stderr, exit code, and $GITHUB_OUTPUT contents
# into LAST_OUT / LAST_EXIT / LAST_GH.
# -----------------------------------------------------------------------

typeset -g LAST_OUT LAST_EXIT LAST_GH

run_script() {
    local cwd="$1" base_ref="$2" changed_files_set="$3" changed_files_val="$4"
    local gh_output
    gh_output=$(mktemp)
    LAST_OUT=$(
        cd "$cwd" || exit 99
        export BASE_REF="$base_ref"
        if [[ "$changed_files_set" == "1" ]]; then
            export CHANGED_FILES="$changed_files_val"
        else
            unset CHANGED_FILES
        fi
        export GITHUB_OUTPUT="$gh_output"
        zsh "$SCRIPT" 2>&1
    )
    LAST_EXIT=$?
    LAST_GH=$(cat "$gh_output" 2>/dev/null)
    rm -f "$gh_output"
}

# =========================================================================
# Group 1 (#362 item 2) — whitespace-only CHANGED_FILES
# =========================================================================

echo "=== Group 1: whitespace-only CHANGED_FILES (#362) ==="

REPO_ROOT="${SCRIPT_DIR:h:h:h}"
BASE_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)

run_script "$REPO_ROOT" "$BASE_SHA" 1 "   "
expect_contains "spaces-only CHANGED_FILES: reason is 'no changed files'" "$LAST_OUT" "no changed files"
expect_contains "spaces-only CHANGED_FILES: run_all=true in \$GITHUB_OUTPUT" "$LAST_GH" $'run_all=true'
expect_contains "spaces-only CHANGED_FILES: xcb_required=true (fail-open)" "$LAST_GH" $'xcb_required=true'

run_script "$REPO_ROOT" "$BASE_SHA" 1 $'\n   \n\t\n'
expect_contains "blank-lines-only CHANGED_FILES: reason is 'no changed files'" "$LAST_OUT" "no changed files"
expect_contains "blank-lines-only CHANGED_FILES: run_all=true" "$LAST_GH" $'run_all=true'

run_script "$REPO_ROOT" "$BASE_SHA" 1 "Shared/Core/Foo.swift"
expect_contains "regression: a real single-file CHANGED_FILES still scopes normally (run_all=false)" "$LAST_GH" $'run_all=false'
expect_contains "regression: Core still shows up as a directly changed package" "$LAST_OUT" "Directly changed packages: Core"

run_script "$REPO_ROOT" "$BASE_SHA" 1 $'Shared/Core/Foo.swift\n\n\nShared/Playlist/Bar.swift'
expect_contains "regression: blank lines between real files don't eat the second file (Core)" "$LAST_OUT" "Core"
expect_contains "regression: blank lines between real files don't eat the second file (Playlist)" "$LAST_OUT" "Playlist"

# =========================================================================
# Group 2 (#362 item 3) — output() rejects multi-line values
# =========================================================================

echo ""
echo "=== Group 2: output() newline guard (#362) ==="

# The non-run_all path falls off the end of the script without calling
# exit, so sourcing it (with a plain Shared/ change that never hits a
# run_all_and_exit branch) leaves `output` defined and control returned to
# us afterward — no production refactor needed to test this in isolation.
# The guard itself does a hard `exit 1` (matching the rest of the script's
# set -e fail-fast style), so a single subprocess can only observe it in the
# subprocess's own exit code, not via a captured "$?" echoed after the call —
# that line would never run. Two separate subprocesses: good value, bad value.
gh_output=$(mktemp)
GOOD_TEST_OUT=$(
    zsh -c "
        set -uo pipefail
        cd '$REPO_ROOT' || exit 99
        export BASE_REF='$BASE_SHA'
        export CHANGED_FILES='Shared/Core/Foo.swift'
        export GITHUB_OUTPUT='$gh_output'
        source '$SCRIPT' > /dev/null 2>&1
        echo SOURCED_COMPLETED
        output good_key 'single line value'
        echo REACHED_AFTER_GOOD_VALUE
    " 2>&1
)
GOOD_EXIT=$?
rm -f "$gh_output"

gh_output=$(mktemp)
BAD_TEST_OUT=$(
    zsh -c "
        set -uo pipefail
        cd '$REPO_ROOT' || exit 99
        export BASE_REF='$BASE_SHA'
        export CHANGED_FILES='Shared/Core/Foo.swift'
        export GITHUB_OUTPUT='$gh_output'
        source '$SCRIPT' > /dev/null 2>&1
        echo SOURCED_COMPLETED
        output bad_key \$'line one\nline two'
        echo REACHED_AFTER_BAD_VALUE
    " 2>&1
)
BAD_EXIT=$?
rm -f "$gh_output"

expect_contains "sourcing the non-run_all path completes without exiting" "$GOOD_TEST_OUT" "SOURCED_COMPLETED"
expect_eq "single-line value: guard does not false-positive (subprocess exit 0)" "$GOOD_EXIT" "0"
expect_contains "single-line value: control returns after the call" "$GOOD_TEST_OUT" "REACHED_AFTER_GOOD_VALUE"
expect_not_contains "multi-line value: guard does not let control fall through" "$BAD_TEST_OUT" "REACHED_AFTER_BAD_VALUE"
expect_contains "multi-line value: guard prints a clear error to stderr" "$BAD_TEST_OUT" "contains a newline"
if [[ "$BAD_EXIT" != "0" ]]; then
    ok "multi-line value: guard fails loudly (subprocess exit $BAD_EXIT, nonzero)"
else
    fail "multi-line value: guard fails loudly (subprocess exit $BAD_EXIT, nonzero)" "expected nonzero, got 0"
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
