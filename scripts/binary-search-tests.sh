#!/bin/bash
#
# binary-search-tests.sh
# WXYC
#
# Binary search over CoreTests to find which test(s) cause CI hangs.
# Uses the debug-core-tests workflow with partition-based execution.
#
# Created by Claude on 01/18/26.
# Copyright © 2026 WXYC. All rights reserved.
#

set -e

# Configuration
WORKFLOW_FILE="debug-core-tests.yml"
REPO="jakebromberg/wxyc-ios-64"
BRANCH="fix/github-actions-ci"
TIMEOUT_MINUTES=20
POLL_INTERVAL=30

# All 53 CoreTests
TESTS=(
    "CoreTests/ImageCompatibilityTests/heifDataProducesValidImageDataThatCanBeDecoded"
    "CoreTests/ImageCompatibilityTests/heifDataRespectsCompressionQualityParameter"
    "CoreTests/ImageCompatibilityTests/heifDataReturnsValidDataForValidImage"
    "CoreTests/ImageCompatibilityTests/scaledHEIFIsSmallerThanScaledPNG"
    "CoreTests/ImageCompatibilityTests/scaledToWidthHandlesSquareImages"
    "CoreTests/ImageCompatibilityTests/scaledToWidthHandlesTallImages"
    "CoreTests/ImageCompatibilityTests/scaledToWidthMaintainsAspectRatio"
    "CoreTests/ImageCompatibilityTests/scaledToWidthReturnsOriginalForImagesBelowTargetWidth"
    "CoreTests/ImageCompatibilityTests/scaledToWidthReturnsOriginalForImagesAtTargetWidth"
    "CoreTests/ImageCompatibilityTests/scaledToWidthScalesImagesWiderThanTarget"
    "CoreTests/AsyncMessageTests/postAndReceive"
    "CoreTests/AsyncMessageTests/multipleMessages"
    "CoreTests/AsyncMessageTests/subjectFiltering"
    "CoreTests/AsyncMessageTests/makeMessageReturnsNil"
    "CoreTests/AsyncMessageTests/cancellationStopsReceiving"
    "CoreTests/MainActorMessageTests/postAndReceiveViaSequence"
    "CoreTests/MainActorMessageTests/postAndReceiveViaObserver"
    "CoreTests/MainActorMessageTests/subjectFiltering"
    "CoreTests/MainActorMessageTests/makeMessageReturnsNil"
    "CoreTests/MainActorMessageTests/makeNotificationCreatesValidNotification"
    "CoreTests/MainActorMessageTests/multipleMessages"
    "CoreTests/DequeTests/testAppend"
    "CoreTests/DequeTests/testArrayConversion"
    "CoreTests/DequeTests/testCapacityGrowth"
    "CoreTests/DequeTests/testCapacityShrinking"
    "CoreTests/DequeTests/testCircularBuffer"
    "CoreTests/DequeTests/testCircularBufferWrapping"
    "CoreTests/DequeTests/testCollectionIndices"
    "CoreTests/DequeTests/testCopyOnWrite"
    "CoreTests/DequeTests/testEmptyDeque"
    "CoreTests/DequeTests/testEquatable"
    "CoreTests/DequeTests/testExpressibleByArrayLiteral"
    "CoreTests/DequeTests/testHashable"
    "CoreTests/DequeTests/testPrepend"
    "CoreTests/DequeTests/testPrependAndAppend"
    "CoreTests/DequeTests/testPrependMany"
    "CoreTests/DequeTests/testRandomAccessCollection"
    "CoreTests/DequeTests/testRemoveAll"
    "CoreTests/DequeTests/testRemoveFirst"
    "CoreTests/DequeTests/testRemoveFirstAll"
    "CoreTests/DequeTests/testRemoveFirstMultiple"
    "CoreTests/DequeTests/testRemoveFirstZero"
    "CoreTests/DequeTests/testRemoveLast"
    "CoreTests/DequeTests/testRemoveLastFromSingleElement"
    "CoreTests/DequeTests/testSubscript"
    "CoreTests/ExponentialBackoffTests/customConfigurationIsRespected"
    "CoreTests/ExponentialBackoffTests/defaultConfigurationHasCorrectValues"
    "CoreTests/ExponentialBackoffTests/descriptionFormatIsCorrect"
    "CoreTests/ExponentialBackoffTests/firstAttemptReturnsZeroWaitTime"
    "CoreTests/ExponentialBackoffTests/resetClearsAttemptsAndTotalWaitTime"
    "CoreTests/ExponentialBackoffTests/returnsNilWhenMaxAttemptsExhausted"
    "CoreTests/ExponentialBackoffTests/timeIntervalNanosecondsConversion"
    "CoreTests/ExponentialBackoffTests/totalWaitTimeAccumulatesCorrectly"
    "CoreTests/ExponentialBackoffTests/waitTimeIsCappedAtMaximum"
    "CoreTests/ExponentialBackoffTests/waitTimesIncreaseExponentially"
)

TOTAL_TESTS=${#TESTS[@]}

log() {
    echo "$(date '+%H:%M:%S') $1" >&2
}

# Trigger workflow and return run ID
trigger_workflow() {
    local partition=$1
    local total_partitions=$2

    log "🚀 Triggering workflow: partition=$partition, total=$total_partitions"

    gh workflow run "$WORKFLOW_FILE" \
        --repo "$REPO" \
        --ref "$BRANCH" \
        -f partition="$partition" \
        -f total_partitions="$total_partitions"

    # Wait for run to appear
    sleep 5

    # Get the most recent run ID
    local run_id
    run_id=$(gh run list --repo "$REPO" --workflow "$WORKFLOW_FILE" --limit 1 --json databaseId --jq '.[0].databaseId')
    echo "$run_id"
}

# Wait for workflow to complete, return conclusion
wait_for_workflow() {
    local run_id=$1
    local start_time=$(date +%s)
    local timeout_seconds=$((TIMEOUT_MINUTES * 60))

    log "⏳ Waiting for run $run_id (timeout: ${TIMEOUT_MINUTES}m)..."

    while true; do
        local status conclusion
        status=$(gh run view "$run_id" --repo "$REPO" --json status --jq '.status')

        if [[ "$status" == "completed" ]]; then
            conclusion=$(gh run view "$run_id" --repo "$REPO" --json conclusion --jq '.conclusion')
            echo "$conclusion"
            return
        fi

        local elapsed=$(( $(date +%s) - start_time ))
        if [[ $elapsed -gt $timeout_seconds ]]; then
            log "⏰ Timeout reached, cancelling run..."
            gh run cancel "$run_id" --repo "$REPO" 2>/dev/null || true
            echo "timeout"
            return
        fi

        local remaining=$(( (timeout_seconds - elapsed) / 60 ))
        log "   Status: $status (${remaining}m remaining)"
        sleep "$POLL_INTERVAL"
    done
}

# Run a single partition and return result
test_partition() {
    local partition=$1
    local total_partitions=$2

    local run_id
    run_id=$(trigger_workflow "$partition" "$total_partitions")

    local conclusion
    conclusion=$(wait_for_workflow "$run_id")

    if [[ "$conclusion" == "success" ]]; then
        log "✅ Partition $partition PASSED"
        return 0
    else
        log "❌ Partition $partition FAILED ($conclusion)"
        return 1
    fi
}

# Get test names for a range
get_tests_in_range() {
    local start=$1
    local end=$2

    for (( i=start; i<end && i<TOTAL_TESTS; i++ )); do
        echo "  [$i] ${TESTS[$i]}" >&2
    done
}

# Binary search to find problematic tests
binary_search() {
    local low=$1
    local high=$2
    local depth=${3:-0}
    local indent=""

    for (( i=0; i<depth; i++ )); do indent="  $indent"; done

    local count=$((high - low))

    log "${indent}🔍 Searching range [$low, $high) - $count test(s)"

    if [[ $count -le 0 ]]; then
        return
    fi

    if [[ $count -eq 1 ]]; then
        log "${indent}🎯 Testing single test: ${TESTS[$low]}"
        if test_partition "$low" "$TOTAL_TESTS"; then
            log "${indent}✅ Test passes individually"
        else
            log "${indent}💥 FOUND PROBLEMATIC TEST: ${TESTS[$low]}"
            echo "${TESTS[$low]}" >> /tmp/problematic_tests.txt
        fi
        return
    fi

    # Test the entire range first
    local partition_size=$(( (TOTAL_TESTS + 1) / 2 ))
    local test_partition_num=$((low / partition_size))

    # For binary search, we'll test the range by using appropriate partitioning
    # Calculate how many partitions we need to isolate this range
    local range_partition=$low
    local range_total=$TOTAL_TESTS

    if test_partition "$range_partition" "$range_total"; then
        log "${indent}✅ Range [$low, $high) passes - no problematic tests here"
        return
    fi

    # Range failed, split and recurse
    local mid=$(( (low + high) / 2 ))

    log "${indent}📊 Range failed, splitting at $mid"

    binary_search "$low" "$mid" $((depth + 1))
    binary_search "$mid" "$high" $((depth + 1))
}

# Main execution
main() {
    log "🔬 CoreTests Binary Search"
    log "   Total tests: $TOTAL_TESTS"
    log "   Timeout per run: ${TIMEOUT_MINUTES}m"
    log ""

    # Check gh CLI is available
    if ! command -v gh &> /dev/null; then
        log "❌ GitHub CLI (gh) not found. Install with: brew install gh"
        exit 1
    fi

    # Check authentication
    if ! gh auth status &> /dev/null; then
        log "❌ Not authenticated with GitHub CLI. Run: gh auth login"
        exit 1
    fi

    # Clear previous results
    rm -f /tmp/problematic_tests.txt

    # Parse arguments
    local mode="${1:-interactive}"

    case "$mode" in
        --full)
            log "Running full binary search..."
            binary_search 0 "$TOTAL_TESTS"
            ;;
        --range)
            local start=${2:-0}
            local end=${3:-$TOTAL_TESTS}
            log "Searching range [$start, $end)..."
            binary_search "$start" "$end"
            ;;
        --test)
            local partition=${2:-0}
            local total=${3:-$TOTAL_TESTS}
            log "Running single partition test..."
            test_partition "$partition" "$total"
            ;;
        --list)
            log "Test indices:"
            for (( i=0; i<TOTAL_TESTS; i++ )); do
                echo "  [$i] ${TESTS[$i]}" >&2
            done
            ;;
        *)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --full              Run full binary search over all tests"
            echo "  --range START END   Search specific range (0-indexed)"
            echo "  --test PARTITION [TOTAL]  Test single partition"
            echo "  --list              List all tests with indices"
            echo ""
            echo "Examples:"
            echo "  $0 --full                    # Find all problematic tests"
            echo "  $0 --range 0 27              # Search first half"
            echo "  $0 --test 0 2                # Test first half (partition 0 of 2)"
            echo "  $0 --test 15                 # Test just test index 15"
            ;;
    esac

    # Report results
    if [[ -f /tmp/problematic_tests.txt ]]; then
        log ""
        log "🚨 Problematic tests found:"
        cat /tmp/problematic_tests.txt | while read -r test; do
            log "   - $test"
        done
    fi
}

main "$@"
