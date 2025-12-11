#!/bin/bash

# run_all_tests.sh
# Runs tests for the main app target and all Swift packages under WXYC/Shared

set -e

# Track child process for cleanup
CHILD_PID=""

cleanup() {
    if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
        kill -TERM "$CHILD_PID" 2>/dev/null
        wait "$CHILD_PID" 2>/dev/null
    fi
    echo -e "\n\033[0;31mInterrupted. Exiting...\033[0m"
    exit 130
}

trap cleanup INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/WXYC/Shared"
SIMULATOR_ID=""
SIMULATOR_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track results
declare -a PASSED_TESTS=()
declare -a FAILED_TESTS=()

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

detect_simulator() {
    # Find the iPhone simulator with the latest iOS version
    local result
    result=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Find iOS runtimes, sorted by version (latest first)
runtimes = sorted([r for r in data['devices'].keys() if 'iOS' in r and 'watch' not in r.lower() and 'tv' not in r.lower()], reverse=True)
for runtime in runtimes:
    for device in data['devices'][runtime]:
        if 'iPhone' in device['name'] and device['isAvailable']:
            print(f\"{device['name']}|{device['udid']}\")
            sys.exit(0)
print('')
" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        echo "Error: No available iPhone simulator found" >&2
        exit 1
    fi
    
    SIMULATOR_NAME=$(echo "$result" | cut -d'|' -f1)
    SIMULATOR_ID=$(echo "$result" | cut -d'|' -f2)
}

run_app_tests() {
    print_header "Running WXYCTests (Main App Target)"
    
    cd "$SCRIPT_DIR"
    
    xcodebuild test \
        -project WXYC.xcodeproj \
        -scheme WXYC \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -only-testing:WXYCTests \
        -quiet \
        2>&1 &
    CHILD_PID=$!
    
    if wait "$CHILD_PID"; then
        print_success "WXYCTests passed"
        PASSED_TESTS+=("WXYCTests")
    else
        print_failure "WXYCTests failed"
        FAILED_TESTS+=("WXYCTests")
    fi
    CHILD_PID=""
}

run_package_tests() {
    local package_path="$1"
    local package_name="$(basename "$package_path")"
    
    print_header "Running tests for $package_name"
    
    cd "$package_path"
    
    swift test --parallel 2>&1 &
    CHILD_PID=$!
    
    if wait "$CHILD_PID"; then
        print_success "$package_name tests passed"
        PASSED_TESTS+=("$package_name")
    else
        print_failure "$package_name tests failed"
        FAILED_TESTS+=("$package_name")
    fi
    CHILD_PID=""
}

discover_testable_packages() {
    # Find all directories containing Package.swift with non-empty Tests directories
    local packages=()
    
    for package_swift in "$SHARED_DIR"/*/Package.swift; do
        local package_dir="$(dirname "$package_swift")"
        local tests_dir="$package_dir/Tests"
        
        # Check if Tests directory exists and has Swift files
        if [[ -d "$tests_dir" ]] && find "$tests_dir" -name "*.swift" -type f 2>/dev/null | grep -q .; then
            packages+=("$package_dir")
        fi
    done
    
    # Sort and return
    printf '%s\n' "${packages[@]}" | sort
}

print_summary() {
    print_header "Test Summary"
    
    echo ""
    if [[ ${#PASSED_TESTS[@]} -gt 0 ]]; then
        echo -e "${GREEN}Passed (${#PASSED_TESTS[@]}):${NC}"
        for test in "${PASSED_TESTS[@]}"; do
            echo -e "  ${GREEN}✓${NC} $test"
        done
    fi
    
    echo ""
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed (${#FAILED_TESTS[@]}):${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        echo ""
        return 0
    fi
}

main() {
    print_header "WXYC Test Runner"
    echo ""
    print_info "Simulator: $SIMULATOR_NAME ($SIMULATOR_ID)"
    print_info "Shared packages directory: $SHARED_DIR"
    
    # Discover packages with tests dynamically
    local packages=()
    while IFS= read -r package; do
        packages+=("$package")
    done < <(discover_testable_packages)
    
    print_info "Found ${#packages[@]} packages with tests"
    
    # Run main app tests first
    run_app_tests
    
    # Run package tests
    for package_path in "${packages[@]}"; do
        run_package_tests "$package_path"
    done
    
    # Print summary and exit with appropriate code
    print_summary
}

# Parse arguments
SKIP_APP_TESTS=false
PACKAGES_ONLY=false
APP_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --packages-only)
            PACKAGES_ONLY=true
            shift
            ;;
        --app-only)
            APP_ONLY=true
            shift
            ;;
        --simulator)
            SIMULATOR_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --packages-only        Run only Swift package tests"
            echo "  --app-only             Run only main app tests"
            echo "  --simulator <name>     Specify iOS simulator (auto-detects if not provided)"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Modify main based on arguments
if [[ "$PACKAGES_ONLY" == true ]]; then
    run_app_tests() { :; }  # No-op
elif [[ "$APP_ONLY" == true ]]; then
    run_package_tests() { :; }  # No-op
fi

# Auto-detect simulator if not specified, or look up ID if name was provided
if [[ -z "$SIMULATOR_NAME" ]]; then
    detect_simulator
else
    # Look up ID for the provided simulator name (prefer latest iOS version)
    SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = '$SIMULATOR_NAME'
data = json.load(sys.stdin)
runtimes = sorted([r for r in data['devices'].keys() if 'iOS' in r], reverse=True)
for runtime in runtimes:
    for device in data['devices'][runtime]:
        if device['name'] == name and device['isAvailable']:
            print(device['udid'])
            sys.exit(0)
print('')
" 2>/dev/null)
    if [[ -z "$SIMULATOR_ID" ]]; then
        echo "Error: Simulator '$SIMULATOR_NAME' not found" >&2
        exit 1
    fi
fi

main
