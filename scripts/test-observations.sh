#!/bin/bash

#
# test-observations.sh
# Run observation-related tests and generate reports
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🧪 Observation Testing Suite"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
RUN_BUG_TESTS=true
RUN_HARNESS=true
RUN_CROSS_PLATFORM=true
RUN_ALL=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --bug-only)
            RUN_HARNESS=false
            RUN_CROSS_PLATFORM=false
            shift
            ;;
        --harness-only)
            RUN_BUG_TESTS=false
            RUN_CROSS_PLATFORM=false
            shift
            ;;
        --cross-platform-only)
            RUN_BUG_TESTS=false
            RUN_HARNESS=false
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --bug-only              Run only bug demonstration tests"
            echo "  --harness-only          Run only test harness"
            echo "  --cross-platform-only   Run only cross-platform tests"
            echo "  --all                   Run all Core tests"
            echo "  --verbose               Show detailed output"
            echo "  --help                  Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

# Function to run tests with filter
run_test_suite() {
    local suite_name=$1
    local filter=$2
    local description=$3

    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} $description"
    echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
    echo ""

    if [ "$VERBOSE" = true ]; then
        swift test --package-path WXYC/Shared/StreamingAudioPlayer --filter "$filter"
    else
        swift test --package-path WXYC/Shared/StreamingAudioPlayer --filter "$filter" 2>&1 | grep -E "(Test Suite|Test Case|passed|failed|✅|❌|⚠️|BUG|CORRECT)" || true
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ $suite_name completed${NC}"
    else
        echo -e "${RED}❌ $suite_name had failures${NC}"
    fi

    return $exit_code
}

# Track overall results
FAILED_SUITES=()

# Run bug demonstration tests
if [ "$RUN_BUG_TESTS" = true ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Bug Demonstration Tests${NC}"
    echo -e "${YELLOW}  (These should FAIL or record Issues)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

    if ! run_test_suite "Bug Tests" "ObservationBugTests" "Testing Current Broken Implementation"; then
        FAILED_SUITES+=("Bug Tests (expected to show issues)")
    fi
fi

# Run test harness
if [ "$RUN_HARNESS" = true ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Test Harness${NC}"
    echo -e "${YELLOW}  (Comparing different strategies)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

    if ! run_test_suite "Test Harness" "ObservationTestHarness" "Running Strategy Comparisons"; then
        FAILED_SUITES+=("Test Harness")
    fi
fi

# Run cross-platform tests
if [ "$RUN_CROSS_PLATFORM" = true ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Cross-Platform Tests${NC}"
    echo -e "${YELLOW}  (Should pass on all platforms)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

    if ! run_test_suite "Cross-Platform Tests" "CrossPlatformObservationTests" "Testing Platform Compatibility"; then
        FAILED_SUITES+=("Cross-Platform Tests")
    fi
fi

# Run all Core tests if requested
if [ "$RUN_ALL" = true ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  All Core Tests${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

    if ! run_test_suite "All Core Tests" "." "Running Complete Core Test Suite"; then
        FAILED_SUITES+=("All Core Tests")
    fi
fi

# Print summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All test suites completed${NC}"
    echo ""
    echo "Note: Bug demonstration tests are expected to show issues"
    echo "This is normal and proves the bug exists."
else
    echo -e "${YELLOW}Test suites with failures:${NC}"
    for suite in "${FAILED_SUITES[@]}"; do
        echo -e "  ${YELLOW}•${NC} $suite"
    done
fi

echo ""
echo "For more details, see:"
echo "  WXYC/Shared/StreamingAudioPlayer/Tests/StreamingAudioPlayerTests/OBSERVATION_TESTING_GUIDE.md"
echo ""

# Detect iOS version
echo "Platform Information:"
if swift --version | grep -q "26"; then
    echo -e "  ${GREEN}iOS 26+ detected${NC} - Using Observations API"
else
    echo -e "  ${BLUE}iOS < 26 detected${NC} - Using withObservationTracking"
fi
echo ""
