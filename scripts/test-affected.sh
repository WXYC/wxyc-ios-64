#!/bin/zsh
#
# test-affected.sh
# WXYC
#
# Runs the WXYC test plan locally, scoped to test targets affected by the
# current branch's diff against a base ref. Reuses .github/scripts/affected-tests.sh
# so the local and CI scoping logic stay in sync.
#
# Usage:
#   scripts/test-affected.sh [options]
#
# Options:
#   --base-ref <ref>      Diff base. Default: origin/master.
#   --simulator <value>   Destination value (passed to -destination as the body
#                         after "platform=iOS Simulator,"). Accepts "id=<UUID>"
#                         or "name=<name>". Default: name=iPhone 17.
#   --dry-run             Print the xcodebuild commands without executing.
#   --full                Run the full test plan; skip the affected-tests logic.
#   --core                Also run the CoreTests step. CoreTests defaults to
#                         OFF locally because -only-testing:CoreTests (whole
#                         bundle) is known to trigger a Swift Testing scheduler
#                         hang under load — see issue #359. The CI workflow
#                         works around this by enumerating tests individually;
#                         the wrapper does not.
#   -h, --help            Show this message.
#
# The local diff uses the merge-base of HEAD and BASE_REF, then layers staged,
# unstaged, and untracked-non-ignored changes on top. Untracked Package.resolved
# and .DS_Store files are filtered out so Xcode-auto-generated noise doesn't
# inflate the affected set.
#
# Fail-open: when affected-tests.sh signals run_all=true (no upstream, project
# file change, etc.), this script falls back to the full plan, matching CI.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Repo root + defaults
# ---------------------------------------------------------------------------

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
cd "$REPO_ROOT"

BASE_REF="origin/master"
SIMULATOR="name=iPhone 17"
DRY_RUN=0
FORCE_FULL=0
RUN_CORE_OVERRIDE=""

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
test-affected.sh

Runs the WXYC test plan locally, scoped to test targets affected by the
current branch's diff against a base ref. Reuses .github/scripts/affected-tests.sh
so the local and CI scoping logic stay in sync.

Usage:
  scripts/test-affected.sh [options]

Options:
  --base-ref <ref>      Diff base. Default: origin/master.
  --simulator <value>   Destination value (passed to -destination as the body
                        after "platform=iOS Simulator,"). Accepts "id=<UUID>"
                        or "name=<name>". Default: name=iPhone 17.
  --dry-run             Print the xcodebuild commands without executing.
  --full                Run the full test plan; skip the affected-tests logic.
  --core                Also run the CoreTests step. CoreTests defaults to OFF
                        locally because -only-testing:CoreTests (whole bundle)
                        is known to trigger a Swift Testing scheduler hang
                        under load — see issue #359. The CI workflow works
                        around this by enumerating tests individually; the
                        wrapper does not.
  -h, --help            Show this message.

Fail-open: when affected-tests.sh signals run_all=true (no upstream, project
file change, etc.), this script falls back to the full plan, matching CI.
EOF
}

require_value() {
    local flag="$1"
    local remaining="$2"
    if (( remaining < 2 )); then
        echo "option $flag requires a value" >&2
        usage >&2
        exit 2
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --base-ref)   require_value "$1" "$#"; BASE_REF="$2"; shift 2 ;;
        --simulator)  require_value "$1" "$#"; SIMULATOR="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --full)       FORCE_FULL=1; shift ;;
        --core)       RUN_CORE_OVERRIDE="true"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

DESTINATION="platform=iOS Simulator,${SIMULATOR}"

# ---------------------------------------------------------------------------
# Compute affected test scope
# ---------------------------------------------------------------------------

SKIP_FLAGS="-skip-testing:WXYCUITests -skip-testing:CoreTests"
RUN_ALL="false"
RUN_CORE_TESTS="false"
AFFECTED_SUMMARY="all tests (forced via --full)"

if (( FORCE_FULL == 0 )); then
    if ! git rev-parse --verify --quiet "$BASE_REF" > /dev/null; then
        echo "Base ref '$BASE_REF' does not resolve. Try \`git fetch\` first, or pass --full." >&2
        echo "Falling back to full plan." >&2
        FORCE_FULL=1
    fi
fi

if (( FORCE_FULL == 1 )); then
    RUN_ALL="true"
fi

if (( FORCE_FULL == 0 )); then
    # Local diff: use the merge-base of HEAD and BASE_REF so phantom changes
    # from a moved-ahead origin/master don't inflate the affected set. Then
    # layer working-tree (staged + unstaged) and untracked non-ignored files.
    # Filter known Xcode-auto-generated noise (Package.resolved files outside
    # of Sources/, .DS_Store) so they don't trigger run-all or fan-out via
    # affected-tests.sh's case arms.
    MERGE_BASE=$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo "$BASE_REF")

    LOCAL_CHANGED=$(
        {
            git diff --name-only "$MERGE_BASE" 2>/dev/null || true
            git ls-files --others --exclude-standard 2>/dev/null || true
        } | grep -v -E '(^|/)(\.DS_Store|Package\.resolved)$' || true
    )

    STDERR_FILE=$(mktemp)
    OUTPUT_FILE=$(mktemp)
    # Containment: subshell isolates `set -e`, `exit 0` in run-all path, and
    # cwd changes inside the script. Stdout is silenced (success-path chatter),
    # but stderr is captured to a tempfile and dumped on failure so a future
    # break in affected-tests.sh produces actionable diagnostics.
    (
        export BASE_REF
        export CHANGED_FILES="$LOCAL_CHANGED"
        export GITHUB_OUTPUT="$OUTPUT_FILE"
        zsh .github/scripts/affected-tests.sh
    ) > /dev/null 2> "$STDERR_FILE" || {
        echo "affected-tests.sh failed; falling back to full plan" >&2
        if [[ -s "$STDERR_FILE" ]]; then
            echo "--- affected-tests.sh stderr ---" >&2
            cat "$STDERR_FILE" >&2
            echo "--------------------------------" >&2
        fi
        rm -f "$OUTPUT_FILE"
        OUTPUT_FILE=""
        RUN_ALL="true"
    }
    rm -f "$STDERR_FILE"

    if [[ -n "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                run_all)            RUN_ALL="$value" ;;
                skip_testing_flags) SKIP_FLAGS="$value" ;;
                run_core_tests)     RUN_CORE_TESTS="$value" ;;
                affected_summary)   AFFECTED_SUMMARY="$value" ;;
            esac
        done < "$OUTPUT_FILE"
        rm -f "$OUTPUT_FILE"
    fi
fi

# CoreTests defaults to off locally (Swift Testing scheduler hang risk).
# --core opts back in; affected-tests.sh's run_core_tests signal is ignored.
if [[ -n "$RUN_CORE_OVERRIDE" ]]; then
    RUN_CORE_TESTS="$RUN_CORE_OVERRIDE"
else
    RUN_CORE_TESTS="false"
fi

echo "Base ref:    $BASE_REF"
echo "Destination: $DESTINATION"
echo "Run all:     $RUN_ALL"
echo "Summary:     $AFFECTED_SUMMARY"
echo "Skip flags:  $SKIP_FLAGS"
echo "Run Core:    $RUN_CORE_TESTS"
echo ""

# ---------------------------------------------------------------------------
# Build xcodebuild invocations
# ---------------------------------------------------------------------------

XCODEBUILD_BASE=(
    xcodebuild test
    -project WXYC.xcodeproj
    -scheme WXYC
    -testPlan WXYC
    -destination "$DESTINATION"
    -skipMacroValidation
    -disable-concurrent-testing
    CODE_SIGNING_ALLOWED=NO
)

MAIN_CMD=(
    "${XCODEBUILD_BASE[@]}"
    -resultBundlePath TestResults.xcresult
    ${=SKIP_FLAGS}
)

# CoreTests runs separately, matching the CI workflow's handling of the Swift
# Testing scheduler issue. See .github/workflows/build-and-test.yml.
CORE_CMD=(
    xcodebuild test
    -project WXYC.xcodeproj
    -scheme WXYC
    -testPlan WXYC
    -destination "$DESTINATION"
    -skipMacroValidation
    -disable-concurrent-testing
    CODE_SIGNING_ALLOWED=NO
    -resultBundlePath CoreTestResults.xcresult
    -only-testing:CoreTests
)

run_or_print() {
    local label="$1"; shift
    echo "==> $label"
    printf '    '
    printf '%q ' "$@"
    echo ""
    if (( DRY_RUN == 1 )); then
        return 0
    fi
    "$@"
}

main_exit=0
run_or_print "Main test step" "${MAIN_CMD[@]}" || main_exit=$?

core_exit=0
if [[ "$RUN_CORE_TESTS" == "true" ]]; then
    echo ""
    run_or_print "CoreTests step" "${CORE_CMD[@]}" || core_exit=$?
fi

if (( main_exit != 0 || core_exit != 0 )); then
    echo ""
    echo "FAILED (main=$main_exit, core=$core_exit)" >&2
    exit 1
fi

if (( DRY_RUN == 0 )); then
    echo ""
    echo "PASSED"
fi
