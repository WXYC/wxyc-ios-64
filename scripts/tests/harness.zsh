#!/bin/zsh
#
# harness.zsh
#
# Assertions shared by the zsh regression suites that
# .github/workflows/shell-script-tests.yml runs. Sourced, never executed.
#
# These helpers were copy-pasted verbatim into each suite as it was written —
# by the fifth one the same 43 lines existed five times, byte for byte, in two
# top-level directories. Nothing about them is suite-specific, and a fix to
# `fail`'s output format (or a sixth assertion worth having) had five places to
# land or, more likely, one.
#
# Output is TAP-ish on purpose rather than a framework: these suites test the
# CI scripts themselves, so they must run from a bare checkout with nothing
# installed, on a runner whose only job is to be cheap.
#
# Usage:
#
#     SCRIPT_DIR="${0:A:h}"
#     REPO_ROOT="${SCRIPT_DIR:h:h}"
#     source "${REPO_ROOT}/scripts/tests/harness.zsh"
#
#     expect_eq "the thing is the thing" "$actual" "expected"
#     ...
#     summarize
#
# summarize() exits, so it must be the last thing a suite calls.

typeset -g PASS=0
typeset -g FAIL=0

ok() {
    PASS=$((PASS + 1))
    echo "ok - $1"
}

# fail <desc> [detail lines...] — the details are indented under the failure,
# which is what makes a failing assertion legible in a CI log without having
# to re-run anything locally.
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

# expect_exit <desc> <actual> <expected> <captured output> — the fourth
# argument is dumped on failure, because an unexpected exit status is
# meaningless without the diagnostic the script printed on its way out.
expect_exit() {
    local desc="$1" actual="$2" expected="$3" out="$4"
    if [[ "$actual" == "$expected" ]]; then
        ok "$desc"
    else
        fail "$desc" "expected exit $expected, got $actual" "--- actual ---" "${(f)out}" "--------------"
    fi
}

# Prints the tally and exits: 1 if anything failed, 0 otherwise.
summarize() {
    echo ""
    echo "=== $PASS passed, $FAIL failed ==="
    if (( FAIL > 0 )); then
        exit 1
    fi
    exit 0
}
