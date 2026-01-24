#!/bin/zsh
#
#  test_process_preview.sh
#  app-store-previews
#
#  Unit tests for process-preview.sh.
#
#  Created by Jake on 01/22/26.
#  Copyright © 2026 WXYC. All rights reserved.
#

set -euo pipefail

# ============================================================================
# Test Framework
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROCESS_SCRIPT="${PROJECT_DIR}/process-preview.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Temporary directory for test artifacts
TEST_TMP_DIR=""

set_up() {
    TEST_TMP_DIR=$(mktemp -d)
}

tear_down() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo ""
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        [[ -n "$message" ]] && echo "    Message:  $message"
        return 1
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
        echo "    Actual: '${haystack:0:200}...'"
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

    if $test_func 2>/dev/null; then
        echo "${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "${RED}FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    tear_down
}

# ============================================================================
# Tests: Help and Usage
# ============================================================================

test_help_output() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "Usage:" && \
    assert_contains "$output" "OPTIONS:" && \
    assert_contains "$output" "DEVICES:" && \
    assert_contains "$output" "iphone-6.9"
}

test_help_shows_all_devices() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "iphone-6.9" && \
    assert_contains "$output" "iphone-6.5" && \
    assert_contains "$output" "ipad-13" && \
    assert_contains "$output" "appletv" && \
    assert_contains "$output" "mac" && \
    assert_contains "$output" "visionpro"
}

test_no_args_shows_error() {
    local output
    local exit_code=0
    output=$("$PROCESS_SCRIPT" 2>&1) || exit_code=$?

    assert_contains "$output" "No input file" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Invalid Device
# ============================================================================

test_invalid_device_error() {
    local input_file="${TEST_TMP_DIR}/test.mov"
    touch "$input_file"

    local mock_bin="${TEST_TMP_DIR}/bin"
    mkdir -p "$mock_bin"

    # Create mock ffprobe
    cat > "${mock_bin}/ffprobe" << 'MOCK'
#!/bin/zsh
if [[ "$*" == *"width"* ]]; then
    echo "1920"
elif [[ "$*" == *"height"* ]]; then
    echo "1080"
elif [[ "$*" == *"duration"* ]]; then
    echo "20.0"
fi
MOCK
    chmod +x "${mock_bin}/ffprobe"

    local output
    local exit_code=0
    PATH="${mock_bin}:$PATH" output=$("$PROCESS_SCRIPT" -d invalid-device "$input_file" 2>&1) || exit_code=$?

    assert_contains "$output" "Unknown device" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Missing Input File
# ============================================================================

test_missing_input_file() {
    local output
    local exit_code=0
    output=$("$PROCESS_SCRIPT" -d iphone-6.9 /nonexistent/file.mov 2>&1) || exit_code=$?

    assert_contains "$output" "not found" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Dry Run Mode
# ============================================================================

test_dry_run_shows_command() {
    # Create a mock video file and ffprobe
    local input_file="${TEST_TMP_DIR}/test_input.mov"
    touch "$input_file"

    local mock_bin="${TEST_TMP_DIR}/bin"
    mkdir -p "$mock_bin"

    # Create mock ffprobe
    cat > "${mock_bin}/ffprobe" << 'MOCK'
#!/bin/zsh
if [[ "$*" == *"width"* ]]; then
    echo "1920"
elif [[ "$*" == *"height"* ]]; then
    echo "1080"
elif [[ "$*" == *"duration"* ]]; then
    echo "20.0"
fi
MOCK
    chmod +x "${mock_bin}/ffprobe"

    local output
    PATH="${mock_bin}:$PATH" output=$("$PROCESS_SCRIPT" -d iphone-6.9 --dry-run "$input_file" 2>&1)

    assert_contains "$output" "DRY RUN"
}

# ============================================================================
# Tests: Help Shows Examples
# ============================================================================

test_help_shows_examples() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "EXAMPLES:" && \
    assert_contains "$output" "process-preview.sh"
}

# ============================================================================
# Tests: Help Shows Scale Modes
# ============================================================================

test_help_shows_scale_modes() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "fit" && \
    assert_contains "$output" "fill" && \
    assert_contains "$output" "crop"
}

# ============================================================================
# Tests: Help Shows ProRes Option
# ============================================================================

test_help_shows_prores() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "--prores" && \
    assert_contains "$output" "ProRes"
}

# ============================================================================
# Tests: Help Shows Trim Option
# ============================================================================

test_help_shows_trim() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "--trim" && \
    assert_contains "$output" "start:end"
}

# ============================================================================
# Tests: Required Devices Marked
# ============================================================================

test_required_devices_marked() {
    local output
    output=$("$PROCESS_SCRIPT" --help 2>&1)

    assert_contains "$output" "REQUIRED"
}

# ============================================================================
# Run All Tests
# ============================================================================

echo ""
echo "========================================"
echo "  App Store Preview Processor Tests"
echo "========================================"
echo ""

# Help and Usage
echo "Help and Usage:"
run_test "help output" test_help_output
run_test "help shows all devices" test_help_shows_all_devices
run_test "no args shows error" test_no_args_shows_error
run_test "help shows examples" test_help_shows_examples
run_test "help shows scale modes" test_help_shows_scale_modes
run_test "help shows prores option" test_help_shows_prores
run_test "help shows trim option" test_help_shows_trim
run_test "required devices marked" test_required_devices_marked

# Error Handling
echo ""
echo "Error Handling:"
run_test "invalid device error" test_invalid_device_error
run_test "missing input file" test_missing_input_file

# Dry Run
echo ""
echo "Dry Run Mode:"
run_test "dry run shows command" test_dry_run_shows_command

# Summary
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
