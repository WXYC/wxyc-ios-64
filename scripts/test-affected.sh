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
#   --dry-run             Print the swift test / xcodebuild commands without
#                         executing.
#   --full                Run the full test plan via xcodebuild; skip the
#                         affected-tests scoping and the SPM-direct fast path.
#   --skip-spm            Skip the swift-test SPM-direct step (use xcodebuild
#                         even when only SPM-runnable packages are affected).
#   -h, --help            Show this message.
#
# Two-step execution mirroring CI:
#   1. swift test --package-path Shared/<pkg> for affected SPM-runnable
#      packages (host, fast). Also covers CoreTests.
#   2. xcodebuild test on simulator for the remaining affected targets, only
#      when xcb_required (a non-SPM-runnable package is affected, or run_all).
#
# The local diff uses the merge-base of HEAD and BASE_REF, then layers staged,
# unstaged, and untracked-non-ignored changes on top. Untracked Package.resolved
# and .DS_Store files are filtered out so Xcode-auto-generated noise doesn't
# inflate the affected set.
#
# Fail-open: when affected-tests.sh signals run_all=true (no upstream, project
# file change, etc.), this script falls back to the full xcodebuild plan,
# matching CI.
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
SKIP_SPM=0

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
  --dry-run             Print swift test / xcodebuild commands without executing.
  --full                Run the full test plan via xcodebuild; skip affected
                        scoping and the SPM-direct fast path.
  --skip-spm            Skip the swift-test SPM-direct step.
  -h, --help            Show this message.

Two-step execution mirroring CI:
  1. swift test --package-path Shared/<pkg> for affected SPM-runnable
     packages (host, fast). Also covers CoreTests when Core is affected.
  2. xcodebuild test on simulator for the remaining affected targets, only
     when xcb_required (a non-SPM-runnable package is affected, or run_all).

Fail-open: when affected-tests.sh signals run_all=true, falls back to the full
xcodebuild plan, matching CI.
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
        --skip-spm)   SKIP_SPM=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

DESTINATION="platform=iOS Simulator,${SIMULATOR}"

# ---------------------------------------------------------------------------
# Compute affected test scope
# ---------------------------------------------------------------------------

SKIP_FLAGS="-skip-testing:WXYCUITests -skip-testing:CoreTests"
ONLY_FLAGS=""
SPM_AFFECTED=""
XCB_REQUIRED="true"
RUN_ALL="false"
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
    XCB_REQUIRED="true"
    # Match affected-tests.sh's run_all_and_exit: swift-test all SPM-runnable
    # packages on host, xcodebuild runs the rest (skip spm-covered targets to
    # avoid double coverage).
    SPM_AFFECTED="AnalyticsMacros Core Caching Analytics ColorPalette Playlist"
    SKIP_FLAGS="-skip-testing:WXYCUITests \
-skip-testing:AnalyticsMacrosTests \
-skip-testing:CoreTests -skip-testing:CachingTests -skip-testing:AnalyticsTests \
-skip-testing:ColorPaletteTests -skip-testing:PlaylistTests"
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
        XCB_REQUIRED="true"
    }
    rm -f "$STDERR_FILE"

    if [[ -n "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                run_all)            RUN_ALL="$value" ;;
                skip_testing_flags) SKIP_FLAGS="$value" ;;
                only_testing_flags) ONLY_FLAGS="$value" ;;
                spm_affected)       SPM_AFFECTED="$value" ;;
                xcb_required)       XCB_REQUIRED="$value" ;;
                affected_summary)   AFFECTED_SUMMARY="$value" ;;
            esac
        done < "$OUTPUT_FILE"
        rm -f "$OUTPUT_FILE"
    fi
fi

if (( SKIP_SPM == 1 )); then
    SPM_AFFECTED=""
    XCB_REQUIRED="true"
fi

echo "Base ref:    $BASE_REF"
echo "Destination: $DESTINATION"
echo "Run all:     $RUN_ALL"
echo "Summary:     $AFFECTED_SUMMARY"
echo "SPM steps:   ${SPM_AFFECTED:-(none)}"
echo "xcb step:    $XCB_REQUIRED"
echo ""

# ---------------------------------------------------------------------------
# Step 1: swift test for affected SPM-runnable packages (host)
# Step 2: xcodebuild test on simulator (only when xcb_required)
# ---------------------------------------------------------------------------

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

spm_exit=0
typeset -A SPM_SKIP
SPM_SKIP[Core]='ImageCompatibilityTests' # HEIF/HEVC unsupported on macos-latest virtualization
if [[ -n "$SPM_AFFECTED" ]]; then
    for pkg in ${=SPM_AFFECTED}; do
        skip_args=()
        if [[ -n "${SPM_SKIP[$pkg]:-}" ]]; then
            skip_args=(--skip "${SPM_SKIP[$pkg]}")
        fi
        run_or_print "swift test $pkg" swift test --package-path "Shared/$pkg" "${skip_args[@]}" || spm_exit=$?
        if (( spm_exit != 0 )); then
            break # fail fast — don't run xcodebuild after a swift test failure
        fi
        echo ""
    done
fi

xcb_exit=0
if (( spm_exit == 0 )) && [[ "$XCB_REQUIRED" == "true" ]]; then
    XCB_CMD=(
        xcodebuild test
        -project WXYC.xcodeproj
        -scheme WXYC
        -testPlan WXYC
        -destination "$DESTINATION"
        -skipMacroValidation
        -disable-concurrent-testing
        CODE_SIGNING_ALLOWED=NO
        -resultBundlePath TestResults.xcresult
    )
    if [[ "$RUN_ALL" == "true" ]]; then
        XCB_CMD+=(${=SKIP_FLAGS})
    else
        XCB_CMD+=(${=ONLY_FLAGS})
    fi
    run_or_print "xcodebuild test" "${XCB_CMD[@]}" || xcb_exit=$?
fi

if (( spm_exit != 0 || xcb_exit != 0 )); then
    echo ""
    echo "FAILED (swift test=$spm_exit, xcodebuild=$xcb_exit)" >&2
    exit 1
fi

if (( DRY_RUN == 0 )); then
    echo ""
    echo "PASSED"
fi
