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
#   --base-ref <ref>      Diff base. Default: origin/master
#   --simulator <value>   Destination value (passed to -destination as the body
#                         after "platform=iOS Simulator,"). Accepts "id=<UUID>"
#                         or "name=<name>". Default: the canonical sim from
#                         CLAUDE.md memory, fallback iPhone 17 by name.
#   --dry-run             Print the xcodebuild commands without executing.
#   --full                Run the full test plan; skip the affected-tests logic.
#   --no-core             Skip the CoreTests step entirely (useful when you
#                         only want to validate non-Core changes quickly).
#   -h, --help            Show this message.
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
SIMULATOR="id=DBE8242C-FAA0-48B9-B2EF-CDD5FECBBC30"
DRY_RUN=0
FORCE_FULL=0
SKIP_CORE=0

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
  --base-ref <ref>      Diff base. Default: origin/master
  --simulator <value>   Destination value (passed to -destination as the body
                        after "platform=iOS Simulator,"). Accepts "id=<UUID>"
                        or "name=<name>". Default: the canonical sim from
                        CLAUDE.md memory, fallback iPhone 17 by name.
  --dry-run             Print the xcodebuild commands without executing.
  --full                Run the full test plan; skip the affected-tests logic.
  --no-core             Skip the CoreTests step entirely (useful when you
                        only want to validate non-Core changes quickly).
  -h, --help            Show this message.

Fail-open: when affected-tests.sh signals run_all=true (no upstream, project
file change, etc.), this script falls back to the full plan, matching CI.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --base-ref)   BASE_REF="$2"; shift 2 ;;
        --simulator)  SIMULATOR="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --full)       FORCE_FULL=1; shift ;;
        --no-core)    SKIP_CORE=1; shift ;;
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
RUN_CORE_TESTS="true"
AFFECTED_SUMMARY="all tests (forced via --full)"

if (( FORCE_FULL == 1 )); then
    RUN_ALL="true"
fi

if (( FORCE_FULL == 0 )); then
    # Local diff: tracked changes since BASE_REF (committed + staged + unstaged)
    # plus untracked, non-ignored files. CI's BASE_REF...HEAD form excludes
    # the working tree, which is the wrong default for a developer iterating
    # before commit.
    if ! git rev-parse --verify --quiet "$BASE_REF" > /dev/null; then
        echo "Base ref '$BASE_REF' does not resolve. Try \`git fetch\` first, or pass --full." >&2
        echo "Falling back to full plan." >&2
        FORCE_FULL=1
    fi
fi

if (( FORCE_FULL == 0 )); then
    LOCAL_CHANGED=$(
        { git diff --name-only "$BASE_REF" 2>/dev/null || true; }
        { git ls-files --others --exclude-standard 2>/dev/null || true; }
    )

    OUTPUT_FILE=$(mktemp)
    # Containment: subshell isolates `set -e`, `exit 0` in run-all path, and
    # cwd changes inside the script.
    (
        export BASE_REF
        export CHANGED_FILES="$LOCAL_CHANGED"
        export GITHUB_OUTPUT="$OUTPUT_FILE"
        zsh .github/scripts/affected-tests.sh
    ) > /dev/null 2>&1 || {
        echo "affected-tests.sh failed; falling back to full plan" >&2
        rm -f "$OUTPUT_FILE"
        OUTPUT_FILE=""
    }

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

if (( SKIP_CORE == 1 )); then
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

MAIN_CMD=("${XCODEBUILD_BASE[@]}" ${=SKIP_FLAGS})

# CoreTests runs separately, matching the CI workflow's handling of the Swift
# Testing scheduler issue. See .github/workflows/build-and-test.yml.
CORE_CMD=(
    xcodebuild test
    -project WXYC.xcodeproj
    -scheme WXYC
    -destination "$DESTINATION"
    -skipMacroValidation
    -disable-concurrent-testing
    CODE_SIGNING_ALLOWED=NO
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
