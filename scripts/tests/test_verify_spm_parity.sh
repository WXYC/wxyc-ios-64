#!/bin/zsh
#
#  test_verify_spm_parity.sh
#  scripts
#
#  Unit tests for verify-spm-parity.sh's crash-detection guard and its
#  build-artifact paths. Mocks swift/xcodebuild/xcrun on PATH so no real
#  build or test run happens — these tests exercise the count-parsing and
#  verdict logic only, feeding it canned xcresult JSON and host output.
#
#  Created by Jake on 08/11/26.
#  Copyright © 2026 WXYC. All rights reserved.
#

set -euo pipefail

# ============================================================================
# Test Framework
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PARITY_SCRIPT="${PROJECT_DIR}/verify-spm-parity.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TEST_TMP_DIR=""
MOCK_BIN=""

set_up() {
    TEST_TMP_DIR=$(mktemp -d)
    MOCK_BIN="${TEST_TMP_DIR}/bin"
    mkdir -p "$MOCK_BIN"
    write_mocks
}

tear_down() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo ""
        echo "    Expected to contain: '$needle'"
        echo "    Actual: '${haystack:0:400}...'"
        [[ -n "$message" ]] && echo "    Message: $message"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo ""
        echo "    Expected NOT to contain: '$needle'"
        [[ -n "$message" ]] && echo "    Message: $message"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo ""
        echo "    Expected exit code: $expected"
        echo "    Actual exit code:   $actual"
        [[ -n "$message" ]] && echo "    Message: $message"
        return 1
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Testing: $test_name ... "

    set_up

    local failure_output
    if failure_output=$($test_func 2>&1); then
        echo "${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "${RED}FAILED${NC}"
        echo "$failure_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    tear_down
}

# ============================================================================
# Mocks
#
# swift/xcodebuild/xcrun are all stubbed on PATH so the script under test
# never invokes a real build. Behavior is driven entirely by env vars set
# per test:
#   MOCK_HOST_TOTAL       — count printed via a "Test run with N tests in
#                           1 suite passed" line from the `swift` mock.
#   MOCK_XCRESULT_JSON     — raw JSON the `xcrun xcresulttool` mock prints
#                           for `get test-results summary`.
#   MOCK_XCODEBUILD_EXIT   — exit code the `xcodebuild` mock returns for a
#                           `test` invocation (a real xcodebuild returns 65
#                           for ANY test failure, crash or assertion alike,
#                           so this alone can never distinguish the two —
#                           that's why the fix reads xcresult content
#                           instead of trusting this).
# ============================================================================

write_mocks() {
    cat > "${MOCK_BIN}/swift" << 'MOCK'
#!/bin/zsh
if [[ "$1" == "test" ]]; then
    echo "Test run with ${MOCK_HOST_TOTAL:-0} tests in 1 suite passed."
    exit 0
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/swift"

    cat > "${MOCK_BIN}/xcodebuild" << 'MOCK'
#!/bin/zsh
if [[ "$1" == "-list" ]]; then
    cat <<'EOF'
Information about project "WXUI":
    Targets:
        WXUI

    Build Configurations:
        Debug
        Release

    Schemes:
        WXUI
EOF
    exit 0
fi

if [[ "$1" == "test" ]]; then
    local bundle="" prev=""
    for arg in "$@"; do
        if [[ "$prev" == "-resultBundlePath" ]]; then
            bundle="$arg"
        fi
        prev="$arg"
    done
    if [[ -n "$bundle" ]]; then
        mkdir -p "$bundle"
    fi
    exit "${MOCK_XCODEBUILD_EXIT:-0}"
fi

exit 0
MOCK
    chmod +x "${MOCK_BIN}/xcodebuild"

    cat > "${MOCK_BIN}/xcrun" << 'MOCK'
#!/bin/zsh
if [[ "$1" == "xcresulttool" ]]; then
    print -r -- "$MOCK_XCRESULT_JSON"
    exit 0
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/xcrun"
}

run_parity() {
    local pkg="${1:-WXUI}"
    PATH="${MOCK_BIN}:$PATH" \
        "$PARITY_SCRIPT" --derived-data "${TEST_TMP_DIR}/dd" "$pkg"
}

# ============================================================================
# Tests: Help and Usage (sanity)
# ============================================================================

test_help_output() {
    local output
    output=$("$PARITY_SCRIPT" --help 2>&1)

    assert_contains "$output" "Coverage-parity guard" && \
    assert_contains "$output" "--tolerance"
}

# ============================================================================
# Tests: Crash detection
#
# This is the reproduction of the reported bug: a simulator run where 9 of
# 76 WXUI test cases were SIGKILLed under load still posts totalTestCount=76
# (a killed case still lands in the count), matching a clean host run of 76
# and producing gap=0. Before the fix, that gap=0 was the only signal the
# script looked at, so it printed PARITY CHECK PASSED. This test must FAIL
# against the unfixed script and PASS against the fix.
#
# The fixture keeps the incident's totals (76 total, 9 failed) but abbreviates
# testFailures to two entries — the guard fires on ANY crash signature, so
# listing all nine would only make the fixture longer, not the test stronger.
# ============================================================================

test_crash_signature_fails_despite_matching_counts() {
    export MOCK_HOST_TOTAL=76
    export MOCK_XCODEBUILD_EXIT=65
    export MOCK_XCRESULT_JSON='{
  "totalTestCount": 76,
  "passedTests": 67,
  "failedTests": 9,
  "skippedTests": 0,
  "expectedFailures": 0,
  "result": "Failed",
  "testFailures": [
    {"testName": "WXUITests.testAlbumArtLoads()", "targetName": "WXUITests", "failureText": "testAlbumArtLoads() crashed with signal kill.", "testIdentifier": 1, "testIdentifierString": "WXUITests/testAlbumArtLoads()"},
    {"testName": "WXUITests.testWaveformRendersUnderLoad()", "targetName": "WXUITests", "failureText": "testWaveformRendersUnderLoad() crashed with signal kill.", "testIdentifier": 2, "testIdentifierString": "WXUITests/testWaveformRendersUnderLoad()"}
  ]
}'

    local output
    local exit_code=0
    output=$(run_parity WXUI 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "a crashed simulator run must fail the parity check even when counts match" && \
    assert_contains "$output" "PARITY CHECK FAILED" && \
    assert_contains "$output" "crashed under load"
}

# ============================================================================
# Tests: An ordinary (non-crash) simulator-only test failure is still
# tolerated when counts match — this preserves the script's existing,
# deliberate design (see the CachingTests comment in the script header):
# parity is about coverage counts, not pass/fail, for tests that actually
# ran to completion.
# ============================================================================

test_ordinary_failure_without_crash_still_passes() {
    export MOCK_HOST_TOTAL=76
    export MOCK_XCODEBUILD_EXIT=65
    export MOCK_XCRESULT_JSON='{
  "totalTestCount": 76,
  "passedTests": 75,
  "failedTests": 1,
  "skippedTests": 0,
  "expectedFailures": 0,
  "result": "Failed",
  "testFailures": [
    {"testName": "WXUITests.testAlbumArtLoads()", "targetName": "WXUITests", "failureText": "XCTAssertEqual failed: (\"1\") is not equal to (\"2\")", "testIdentifier": 1, "testIdentifierString": "WXUITests/testAlbumArtLoads()"}
  ]
}'

    local output
    local exit_code=0
    output=$(run_parity WXUI 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "an ordinary assertion failure on a test that ran to completion must not fail parity" && \
    assert_contains "$output" "PARITY CHECK PASSED" && \
    assert_not_contains "$output" "crashed under load"
}

# ============================================================================
# Tests: A genuine count gap (no crash involved) must still fail — this is
# the script's original, pre-existing purpose and must not regress.
# ============================================================================

test_count_gap_without_crash_still_fails() {
    export MOCK_HOST_TOTAL=29
    export MOCK_XCODEBUILD_EXIT=0
    export MOCK_XCRESULT_JSON='{
  "totalTestCount": 52,
  "passedTests": 52,
  "failedTests": 0,
  "skippedTests": 0,
  "expectedFailures": 0,
  "result": "Passed",
  "testFailures": []
}'

    local output
    local exit_code=0
    output=$(run_parity WXUI 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "a real coverage gap must still fail" && \
    assert_contains "$output" "PARITY CHECK FAILED" && \
    assert_contains "$output" "silently skipping simulator-only coverage"
}

# ============================================================================
# Tests: Crash detection generalizes across signal types, not just SIGKILL
# — Xcode's synthesized message is "crashed with signal <name>" for any
# signal, and the fix matches the family, not the literal word "kill".
# ============================================================================

test_non_kill_signal_crash_also_fails() {
    export MOCK_HOST_TOTAL=10
    export MOCK_XCODEBUILD_EXIT=65
    export MOCK_XCRESULT_JSON='{
  "totalTestCount": 10,
  "passedTests": 9,
  "failedTests": 1,
  "skippedTests": 0,
  "expectedFailures": 0,
  "result": "Failed",
  "testFailures": [
    {"testName": "WXUITests.testScrollPerformance()", "targetName": "WXUITests", "failureText": "testScrollPerformance() crashed with signal segmentation fault.", "testIdentifier": 1, "testIdentifierString": "WXUITests/testScrollPerformance()"}
  ]
}'

    local output
    local exit_code=0
    output=$(run_parity WXUI 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "a non-SIGKILL crash signature must also fail" && \
    assert_contains "$output" "crashed under load"
}

# ============================================================================
# Tests: an absolute --derived-data must be honoured as given, not
# concatenated onto the repo root. "$REPO_ROOT/$DERIVED_DATA" against an
# already-absolute value yields "<repo>//var/folders/.../dd", so every run
# writes its .xcresult bundles into a shadow /var tree inside the working
# copy. `git status` never reports that — .gitignore ignores *.xcresult and
# git says nothing about a directory whose whole contents are ignored — so
# the litter is invisible and accumulates one temp dir per run. This test is
# what keeps the path normalization in place.
# ============================================================================

test_absolute_derived_data_stays_out_of_the_repo() {
    export MOCK_HOST_TOTAL=5
    export MOCK_XCODEBUILD_EXIT=0
    export MOCK_XCRESULT_JSON='{"totalTestCount": 5, "result": "Passed", "testFailures": []}'

    # The exact path the bug produces: "$REPO_ROOT/$DERIVED_DATA" against an
    # absolute --derived-data appends the absolute path whole. TEST_TMP_DIR is
    # unique per test, so this location is unique to this run — which means the
    # check can't be satisfied by litter an earlier run left behind, and needs
    # to delete nothing in the working tree to set itself up. Checking for a
    # bare <repo>/var instead would mean rm -rf'ing a path outside the test's
    # scratch space before every run, which is not a test's business.
    local repo_root shadow
    repo_root="$(dirname "$PROJECT_DIR")"
    shadow="${repo_root}${TEST_TMP_DIR}"

    run_parity WXUI > /dev/null 2>&1 || true

    local stray="absent"
    [[ -e "$shadow" ]] && stray="present"

    # Remove only this run's own shadow subtree, never a broader path.
    [[ -e "$shadow" ]] && rm -rf "$shadow"

    assert_contains "$stray" "absent" \
        "an absolute --derived-data must not be re-rooted at the repo — it created $shadow" && \
    assert_contains "$(ls "${TEST_TMP_DIR}/dd-results" 2>&1)" "WXUI.xcresult" \
        "the result bundle must land under the absolute --derived-data the caller asked for"
}

# ============================================================================
# Run All Tests
# ============================================================================

echo ""
echo "========================================"
echo "  verify-spm-parity.sh Tests"
echo "========================================"
echo ""

echo "Help and Usage:"
run_test "help output" test_help_output

echo ""
echo "Crash Detection:"
run_test "crash signature fails despite matching counts" test_crash_signature_fails_despite_matching_counts
run_test "ordinary failure without crash still passes" test_ordinary_failure_without_crash_still_passes
run_test "count gap without crash still fails" test_count_gap_without_crash_still_fails
run_test "non-kill signal crash also fails" test_non_kill_signal_crash_also_fails

echo ""
echo "Artifact Paths:"
run_test "absolute --derived-data stays out of the repo" test_absolute_derived_data_stays_out_of_the_repo

echo ""
echo "========================================"
echo "  Results: $TESTS_PASSED/$TESTS_RUN passed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "  ${RED}$TESTS_FAILED test(s) failed${NC}"
    exit 1
else
    echo "  ${GREEN}All tests passed!${NC}"
    exit 0
fi
