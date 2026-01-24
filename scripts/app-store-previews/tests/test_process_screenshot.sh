#!/bin/zsh
#
#  test_process_screenshot.sh
#  app-store-previews
#
#  Unit tests for process-screenshot.sh.
#
#  Created by Jake on 01/23/26.
#

set -euo pipefail

# ============================================================================
# Test Framework
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCREENSHOT_SCRIPT="${PROJECT_DIR}/process-screenshot.sh"

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

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    if [[ -f "$file" ]]; then
        return 0
    else
        echo ""
        echo "    Expected file to exist: $file"
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
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "Usage:" && \
    assert_contains "$output" "OPTIONS:" && \
    assert_contains "$output" "DEVICES:" && \
    assert_contains "$output" "iphone-6.9"
}

test_help_shows_all_devices() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "iphone-6.9" && \
    assert_contains "$output" "iphone-6.5" && \
    assert_contains "$output" "ipad-13" && \
    assert_contains "$output" "mac-16x10" && \
    assert_contains "$output" "appletv" && \
    assert_contains "$output" "visionpro" && \
    assert_contains "$output" "watch-ultra3"
}

test_no_args_shows_error() {
    local output
    local exit_code=0
    output=$("$SCREENSHOT_SCRIPT" 2>&1) || exit_code=$?

    assert_contains "$output" "No input file" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Format Options
# ============================================================================

test_help_shows_format_options() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "--format" && \
    assert_contains "$output" "png" && \
    assert_contains "$output" "jpg"
}

test_help_shows_quality_option() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "--quality" && \
    assert_contains "$output" "JPEG quality"
}

# ============================================================================
# Tests: Scale Modes
# ============================================================================

test_help_shows_scale_modes() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "SCALE MODES:" && \
    assert_contains "$output" "fill" && \
    assert_contains "$output" "fit" && \
    assert_contains "$output" "crop"
}

# ============================================================================
# Tests: Invalid Device
# ============================================================================

test_invalid_device_error() {
    # Create a test image
    local input_file="${TEST_TMP_DIR}/test.png"
    sips -z 100 100 -s format png /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -1 || \
    convert -size 100x100 xc:white "$input_file" 2>/dev/null || \
    touch "$input_file"

    local output
    local exit_code=0
    output=$("$SCREENSHOT_SCRIPT" -d invalid-device "$input_file" 2>&1) || exit_code=$?

    assert_contains "$output" "Unknown device" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Missing Input File
# ============================================================================

test_missing_input_file() {
    local output
    local exit_code=0
    output=$("$SCREENSHOT_SCRIPT" -d iphone-6.9 /nonexistent/file.png 2>&1) || exit_code=$?

    assert_contains "$output" "not found" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Tests: Dry Run Mode
# ============================================================================

test_dry_run_shows_info() {
    # Create a simple test image using sips
    local input_file="${TEST_TMP_DIR}/test_input.png"

    # Create a simple PNG using printf and sips
    printf '\x89PNG\r\n\x1a\n' > "$input_file"
    # Use a system image as source
    if [[ -f "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns" ]]; then
        sips -s format png "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns" --out "$input_file" >/dev/null 2>&1
    fi

    local output
    output=$("$SCREENSHOT_SCRIPT" -d iphone-6.9 --dry-run "$input_file" 2>&1) || true

    assert_contains "$output" "DRY RUN"
}

# ============================================================================
# Tests: Watch Support
# ============================================================================

test_help_shows_watch_devices() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "Apple Watch:" && \
    assert_contains "$output" "watch-ultra3" && \
    assert_contains "$output" "watch-series10" && \
    assert_contains "$output" "watch-series3"
}

# ============================================================================
# Tests: Background Option
# ============================================================================

test_help_shows_background_option() {
    local output
    output=$("$SCREENSHOT_SCRIPT" --help 2>&1)

    assert_contains "$output" "--background" && \
    assert_contains "$output" "letterbox"
}

# ============================================================================
# Tests: Invalid Format
# ============================================================================

test_invalid_format_error() {
    local input_file="${TEST_TMP_DIR}/test.png"
    touch "$input_file"

    local output
    local exit_code=0
    output=$("$SCREENSHOT_SCRIPT" -d iphone-6.9 -f gif "$input_file" 2>&1) || exit_code=$?

    assert_contains "$output" "Unsupported format" && \
    assert_exit_code 1 "$exit_code"
}

# ============================================================================
# Run All Tests
# ============================================================================

echo ""
echo "========================================"
echo "  App Store Screenshot Processor Tests"
echo "========================================"
echo ""

# Help and Usage
echo "Help and Usage:"
run_test "help output" test_help_output
run_test "help shows all devices" test_help_shows_all_devices
run_test "no args shows error" test_no_args_shows_error

# Format Options
echo ""
echo "Format Options:"
run_test "format options shown" test_help_shows_format_options
run_test "quality option shown" test_help_shows_quality_option

# Scale Modes
echo ""
echo "Scale Modes:"
run_test "scale modes shown" test_help_shows_scale_modes

# Error Handling
echo ""
echo "Error Handling:"
run_test "invalid device error" test_invalid_device_error
run_test "missing input file" test_missing_input_file
run_test "invalid format error" test_invalid_format_error

# Dry Run
echo ""
echo "Dry Run Mode:"
run_test "dry run shows info" test_dry_run_shows_info

# Watch Support
echo ""
echo "Watch Support:"
run_test "watch devices shown" test_help_shows_watch_devices

# Background Option
echo ""
echo "Background Option:"
run_test "background option shown" test_help_shows_background_option

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
