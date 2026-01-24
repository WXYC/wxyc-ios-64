#!/bin/bash
#
# record-marketing.sh
#
# Records a marketing video by running the MarketingRecordingUITests on the Simulator.
# Starts screen recording, runs the UI test, and stops recording when complete.
#
# Usage:
#   ./record-marketing.sh [options]
#
# Options:
#   -d, --device <name>      Simulator device name (default: "iPhone 17 Pro Max")
#   -o, --output <path>      Output video path (default: marketing_recording_<timestamp>.mov)
#   -s, --simulator <udid>   Use specific simulator UDID instead of device name
#   --no-build               Skip building, run test directly
#   --no-process             Skip automatic processing with process-preview.sh
#   -h, --help               Show this help message
#
# Prerequisites:
#   - Xcode and Simulator
#   - The app must be built for the simulator
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
DEVICE_NAME="iPhone 17 Pro Max"
SIMULATOR_UDID=""
OUTPUT_PATH=""
SKIP_BUILD=false
SKIP_PROCESS=false

# Logging helpers
log() {
    echo "📹 $*"
}

error() {
    echo "❌ $*" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--device)
            DEVICE_NAME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -s|--simulator)
            SIMULATOR_UDID="$2"
            shift 2
            ;;
        --no-build)
            SKIP_BUILD=true
            shift
            ;;
        --no-process)
            SKIP_PROCESS=true
            shift
            ;;
        -h|--help)
            head -30 "$0" | tail -n +2 | sed 's/^#//' | sed 's/^ //'
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Generate default output path if not specified
if [[ -z "$OUTPUT_PATH" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_PATH="$PROJECT_DIR/marketing_recording_${TIMESTAMP}.mov"
fi

# Find simulator UDID if not specified
if [[ -z "$SIMULATOR_UDID" ]]; then
    log "Looking for simulator: $DEVICE_NAME"
    SIMULATOR_UDID=$(xcrun simctl list devices available -j | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    for device in devices:
        if device.get('name') == '$DEVICE_NAME' and device.get('isAvailable', False):
            print(device['udid'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null) || {
        error "Could not find simulator: $DEVICE_NAME"
        log "Available simulators:"
        xcrun simctl list devices available | grep -E "^\s+\w" | head -20
        exit 1
    }
fi

log "Using simulator: $SIMULATOR_UDID"

# Boot simulator if needed
DEVICE_STATE=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for device in devices:
        if device.get('udid') == '$SIMULATOR_UDID':
            print(device.get('state', 'Unknown'))
            sys.exit(0)
print('Unknown')
")

if [[ "$DEVICE_STATE" != "Booted" ]]; then
    log "Booting simulator..."
    xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
    # Wait for boot
    sleep 3
fi

# Open Simulator app to make it visible
log "Opening Simulator..."
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID"
sleep 2

# Start recording in background
log "Starting screen recording: $OUTPUT_PATH"
xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 "$OUTPUT_PATH" &
RECORD_PID=$!

# Give recording time to start
sleep 1

# Cleanup function
cleanup() {
    log "Stopping recording..."
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Run the marketing UI test (xcodebuild test handles building internally)
log "Running marketing recording test..."
cd "$PROJECT_DIR"

BUILD_FLAG=""
if [[ "$SKIP_BUILD" == "true" ]]; then
    BUILD_FLAG="-skip-testing:all"  # Will run test-without-building behavior
fi

xcodebuild test \
    -scheme WXYC \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -only-testing:WXYCUITests/MarketingRecordingUITests/testMarketingRecordingSequence \
    -test-timeouts-enabled NO \
    2>&1 | while IFS= read -r line; do
        # Filter to show only relevant output
        if [[ "$line" == *"Test Case"* ]] || [[ "$line" == *"passed"* ]] || [[ "$line" == *"failed"* ]] || [[ "$line" == *"error:"* ]]; then
            echo "  $line"
        fi
    done

TEST_RESULT=${PIPESTATUS[0]}

# Stop recording (handled by trap)
sleep 1

if [[ $TEST_RESULT -eq 0 ]]; then
    log "Recording complete: $OUTPUT_PATH"

    # Show file info
    if [[ -f "$OUTPUT_PATH" ]]; then
        SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_PATH" 2>/dev/null || echo "unknown")
        log "File size: $SIZE"
        log "Duration: ${DURATION}s"

        # Verify minimum duration (15 seconds)
        if [[ "$DURATION" != "unknown" ]]; then
            DURATION_INT=${DURATION%.*}
            if [[ "$DURATION_INT" -lt 15 ]]; then
                error "Recording is shorter than 15 seconds ($DURATION_INT s). Consider increasing test wait time."
            fi
        fi

        # Process for App Store
        if [[ "$SKIP_PROCESS" != "true" ]]; then
            log ""
            log "Processing for App Store..."
            if [[ -x "$SCRIPT_DIR/process-preview.sh" ]]; then
                "$SCRIPT_DIR/process-preview.sh" -a "$OUTPUT_PATH"
            else
                log "process-preview.sh not found or not executable, skipping processing"
                log "To process manually:"
                log "  $SCRIPT_DIR/process-preview.sh -a \"$OUTPUT_PATH\""
            fi
        else
            log ""
            log "To process for App Store:"
            log "  $SCRIPT_DIR/process-preview.sh -a \"$OUTPUT_PATH\""
        fi
    fi
else
    error "Test failed with exit code: $TEST_RESULT"
    exit 1
fi
