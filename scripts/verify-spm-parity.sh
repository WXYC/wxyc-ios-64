#!/bin/zsh
#
# verify-spm-parity.sh
# WXYC
#
# Coverage-parity guard for SPM_RUNNABLE (see .github/scripts/affected-tests.sh).
# For each package given, runs the same test target twice — once on the
# macOS host via `swift test --package-path`, once on the iOS Simulator via
# `xcodebuild test` — and compares how many tests each side actually
# executed. A package whose host count falls materially short of its
# simulator count is silently skipping real coverage and must not be on
# SPM_RUNNABLE (see #797).
#
# This exists because "the package builds and passes on the macOS host" has
# twice been wrong evidence for a move onto the host-only path:
#   - 3fb1c916 dropped Artwork after `swift test` hung indefinitely on the
#     macos-latest CI runner (a paravirt/graphics-stack issue invisible
#     locally).
#   - #394 moved ColorPalette off the host path after discovering its
#     UIKit-gated suites (#if canImport(UIKit)) were silently skipping on
#     the macOS host — the package "passed" while running none of that
#     coverage.
# Neither failure mode is visible from a local green run. This script makes
# both detectable by comparing counts instead of trusting exit codes.
#
# Usage:
#   scripts/verify-spm-parity.sh [options] [package...]
#
# Options:
#   --simulator <value>     Destination value, as the body after
#                           "platform=iOS Simulator,". Accepts "id=<UUID>" or
#                           "name=<name>". Default: id=<iPhone 17 UDID>.
#   --derived-data <path>   Shared -derivedDataPath for the xcodebuild runs.
#                           Default: .build/dd-verify-parity (repo-relative).
#   --tolerance <n>         Maximum acceptable (simulator - host) shortfall
#                           per package before it's flagged. Default: 0 —
#                           this is the quantity the flag actually gates
#                           (simulator count minus host count), and every
#                           package measured through this script so far came
#                           out at an exact match, including Concerts at
#                           216/216. The ticket's own 222/221 figure (#797)
#                           measured *declared* vs. *host* — a looser,
#                           different comparison this script doesn't
#                           perform — so it isn't evidence for slack here.
#                           Real silent-skip shortfalls are two orders of
#                           magnitude past zero (ColorPalette: 34, host=25/
#                           sim=59; Playback: 120+, host=329/grep-floor=449+
#                           — see below). Raise this for a specific package
#                           that demonstrably needs it, not as a blanket
#                           default.
#   --dry-run               Print the swift test / xcodebuild commands
#                           without executing them.
#   -h, --help               Show this message.
#
# With no positional packages, checks exactly the packages CI treats as
# SPM_RUNNABLE today (fetched from .github/scripts/affected-tests.sh's
# run_all_and_exit via FORCE_RUN_ALL=1, so this script never carries its own
# stale copy of that list). Pass explicit packages to check a candidate
# addition instead, e.g.:
#
#   scripts/verify-spm-parity.sh                          # today's SPM_RUNNABLE — every package passes except LikedSongs, which prints NOT CHECKED (see below) and is why the run still exits non-zero
#   scripts/verify-spm-parity.sh AnalyticsMacros Core \
#     Caching Analytics Playlist LikedSongs Metadata \
#     MusicShareKit Concerts WXUI ColorPalette            # negative case (must fail on ColorPalette)
#
# LikedSongs cannot currently be measured on the simulator side at all:
# `xcodebuild -only-testing:LikedSongsTests -testPlan WXYC` fails with
# "isn't a member of the specified test plan or scheme", and isolating it via
# -skip-testing of every other target instead fails with "There are no test
# bundles available to test" — reproducible from a clean -derivedDataPath,
# unrelated to anything in this script (see PR #798's Blockers section for
# the full investigation). This script does not attempt LikedSongs'
# simulator side; it reports LikedSongs as NOT CHECKED with that reason
# rather than either skipping it silently or letting the attempt fail and
# masking every package after it in package-list order (that masking was a
# real bug here once — see the "Compare" section below for how per-package
# failures are now isolated). LikedSongs' host side is unaffected and still
# runs for real evidence.
#
# Playback is deliberately not runnable through this script's execution path
# below cost limits: its xcodebuild side is four bundles (PlaybackTests,
# RadioPlayerTests, MP3StreamerTests, HLSPlayerTests) and installing/running
# all four on a simulator is exactly the expense this script's manual/
# on-demand invocation model (rather than a CI job) is meant to avoid paying
# routinely. Its shortfall is instead demonstrated with two cheap, real
# commands (see the SPM_RUNNABLE exclusion comment in affected-tests.sh for
# the exact counts measured 2026-08-06):
#   swift test --package-path Shared/Playback   (real host count: 329)
#   grep -c against Shared/Playback/Tests        (a declared-count proxy —
#     NOT a simulator-executed count; parameterized `@Test(arguments:)`
#     cases expand at run time, so this undercounts the true simulator
#     total, making the demonstrated gap — 329 vs. 449+ — a floor, not the
#     real number)
# Do not extend SPM_RUNNABLE to include Playback on the strength of a local
# green `swift test` run — this script's actual host/simulator comparison,
# run against Playback, is the only acceptable evidence for that move, and
# nobody has paid for that run yet.
#
# Count parsing differs by side, because the two sides don't print the same
# kind of thing:
#
#   - Host (`swift test`): text log parsing. Handles both frameworks a
#     package's test target CAN print, even though no bundle checked here
#     currently mixes them within one target: AnalyticsMacros is XCTest-only
#     (it tests a SwiftSyntax compiler-plugin macro expansion, which needs
#     XCTest's `assertMacroExpansion`), and every other package this script
#     checks is Swift Testing-only (verified: no `Shared/*/Tests/*/`
#     directory imports both `XCTest` and `Testing`). The parser stays
#     dual-format as future-proofing — a package could add an
#     XCTestCase-based test alongside its Swift Testing suite without this
#     script silently mis-parsing it — not because a current bundle needs it:
#       - Swift Testing: "Test run with N tests in M suites {passed,failed}"
#         (summed across every occurrence — each xctest process prints its
#         own line, so multiple bundles in one invocation each contribute a
#         line, and summing is correct).
#       - XCTest: "Executed N tests, with M failures" — printed at every
#         suite-nesting level (per class, per bundle, per top-level "All
#         tests" run), all reporting overlapping/duplicate counts. Only the
#         occurrence immediately following "Test Suite 'All tests' (passed|
#         failed)" is counted, since that is the true top-level aggregate;
#         nested per-class/per-bundle lines are subsets already folded into
#         it, and summing them too would inflate the result.
#
#   - Simulator (`xcodebuild test`): NOT text log parsing. `-testPlan`-based
#     runs on this Xcode version distribute test cases across simulator
#     clones ("Clone N of iPhone 17") and print only per-test-case lines —
#     "Test case 'X' passed on 'Clone 1...'" — with no aggregate summary
#     line at all, and the same identifier repeats once per parameterized
#     `@Test(arguments:)` invocation, so a raw line count doesn't match the
#     host's rolled-up figure either (confirmed empirically against
#     CoreTests: 129 raw "passed" lines vs. 88 on both the host summary and
#     the authoritative source below). The reliable number comes from the
#     .xcresult bundle instead: every xcodebuild invocation writes one via
#     `-resultBundlePath`, and `xcrun xcresulttool get test-results summary
#     --path <bundle>` reports a top-level `totalTestCount` that matches the
#     host figure exactly, regardless of which framework produced the
#     tests — see count_from_xcresult below.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Repo root + defaults
# ---------------------------------------------------------------------------

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
cd "$REPO_ROOT"

SIMULATOR="id=B49BE311-B868-4E8B-AE14-85C159CAD776"
DERIVED_DATA=".build/dd-verify-parity"
TOLERANCE=0
DRY_RUN=0
local -a PACKAGES=()

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
verify-spm-parity.sh

Coverage-parity guard: for each package given, runs its test target once on
the macOS host (swift test) and once on the iOS Simulator (xcodebuild test),
and compares how many tests each side actually executed.

Usage:
  scripts/verify-spm-parity.sh [options] [package...]

Options:
  --simulator <value>     Destination value, as the body after
                          "platform=iOS Simulator,". Accepts "id=<UUID>" or
                          "name=<name>". Default: id=<iPhone 17 UDID>.
  --derived-data <path>   Shared -derivedDataPath for the xcodebuild runs.
                          Default: .build/dd-verify-parity (repo-relative).
  --tolerance <n>         Maximum acceptable (simulator - host) shortfall
                          per package before it's flagged. Default: 0 — see
                          the file header for why (every package measured
                          through this script so far matched exactly).
  --dry-run               Print the swift test / xcodebuild commands without
                          executing them.
  -h, --help              Show this message.

With no positional packages, checks today's SPM_RUNNABLE (sourced from
.github/scripts/affected-tests.sh). Pass explicit packages to check a
candidate addition instead. See the file header for the full rationale and
Playback's derived-not-executed exception.
EOF
}

require_value() {
    local flag="$1"
    local remaining="$2"
    if (( remaining < 2 )); then
        echo "option $flag requires a value" >&2
        exit 2
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --simulator)     require_value "$1" "$#"; SIMULATOR="$2"; shift 2 ;;
        --derived-data)  require_value "$1" "$#"; DERIVED_DATA="$2"; shift 2 ;;
        --tolerance)     require_value "$1" "$#"; TOLERANCE="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        --*)             echo "Unknown option: $1" >&2; exit 2 ;;
        *)                PACKAGES+=("$1"); shift ;;
    esac
done

DESTINATION="platform=iOS Simulator,${SIMULATOR}"

# ---------------------------------------------------------------------------
# Package → simulator test target(s). Mirrors TEST_TARGETS in
# .github/scripts/affected-tests.sh for the subset of packages this script
# is ever asked to check (today's SPM_RUNNABLE, plus ColorPalette for the
# negative-case demonstration). Update alongside that file.
# ---------------------------------------------------------------------------

typeset -A PKG_TEST_TARGETS
PKG_TEST_TARGETS[AnalyticsMacros]="AnalyticsMacrosTests"
PKG_TEST_TARGETS[Core]="CoreTests"
PKG_TEST_TARGETS[Caching]="CachingTests"
PKG_TEST_TARGETS[Analytics]="AnalyticsTests"
PKG_TEST_TARGETS[Playlist]="PlaylistTests"
PKG_TEST_TARGETS[LikedSongs]="LikedSongsTests"
PKG_TEST_TARGETS[Metadata]="MetadataTests"
PKG_TEST_TARGETS[MusicShareKit]="MusicShareKitTests"
PKG_TEST_TARGETS[ColorPalette]="ColorPaletteTests"
PKG_TEST_TARGETS[Concerts]="ConcertsTests"
PKG_TEST_TARGETS[WXUI]="WXUITests"

# Packages whose test target is NOT in WXYC.xctestplan. Their "simulator"
# side runs against the package's own auto-generated scheme instead of the
# WXYC scheme + test plan.
#   - Concerts, WXUI: deliberately kept out of the plan (see
#     affected-tests.sh's SPM_RUNNABLE comment); their coverage is verified
#     by this script instead.
#   - AnalyticsMacros: can't be in the plan at all. AnalyticsMacrosTests
#     exercises a SwiftSyntax compiler-plugin macro expansion — host-only
#     compiler tooling with no on-device behavior — so there is no iOS
#     Simulator destination for it in the first place (confirmed: it is
#     absent from both WXYC.xctestplan and affected-tests.sh's
#     all_test_plan_targets). See PKG_MACOS_ONLY below.
typeset -A PKG_OUT_OF_PLAN
PKG_OUT_OF_PLAN[Concerts]=1
PKG_OUT_OF_PLAN[WXUI]=1
PKG_OUT_OF_PLAN[AnalyticsMacros]=1

# Packages whose "simulator" comparison point is actually macOS, not the iOS
# Simulator, because the test target itself only ever builds for macOS (a
# compiler plugin). The host/device dichotomy this script otherwise checks
# doesn't apply to these; running with -destination platform=macOS is a
# sanity check that the two invocation paths agree, not a real
# host-vs-device comparison, and is expected to always show gap=0.
typeset -A PKG_MACOS_ONLY
PKG_MACOS_ONLY[AnalyticsMacros]=1

# Known, intentional host-side skips that are NOT the silent-skip failure
# mode this script guards against — they're CI-runner/host-environment
# artifacts with a matching skip already established in scripts/test-affected.sh
# and .github/workflows/build-and-test.yml. Applied identically to both the
# host and simulator runs so they don't register as a parity shortfall.
typeset -A PKG_SKIP_TEST
PKG_SKIP_TEST[Core]="ImageCompatibilityTests"

# Packages whose simulator side is known, today, to be unmeasurable through
# no fault of this script — attempting the run would just fail and (before
# the per-package isolation added below) could mask every package after it
# in list order. Recorded here as an explicit, commented exception instead
# of a bare failure so the reason is visible without re-deriving it: this
# script reports these as NOT CHECKED rather than either silently skipping
# them or letting a doomed attempt run. See PR #798's Blockers section for
# the full investigation (reproduced from a clean -derivedDataPath, both
# -only-testing and -skip-testing isolation styles tried).
typeset -A PKG_KNOWN_BLOCKED
PKG_KNOWN_BLOCKED[LikedSongs]="LikedSongsTests cannot be selected via xcodebuild against WXYC.xctestplan: -only-testing:LikedSongsTests fails with \"isn't a member of the specified test plan or scheme\", and isolating it via -skip-testing of every other target instead fails with \"There are no test bundles available to test\". Unrelated to this script or #797/#798 — see PR #798 Blockers."

# ---------------------------------------------------------------------------
# Default package list: today's SPM_RUNNABLE, sourced from
# affected-tests.sh's run_all_and_exit (FORCE_RUN_ALL=1) rather than a second
# hardcoded copy here. See #797 — the local test-affected.sh --full path
# drifted from this exact list once already by duplicating it.
# ---------------------------------------------------------------------------

if (( ${#PACKAGES[@]} == 0 )); then
    OUTPUT_FILE=$(mktemp)
    FORCE_RUN_ALL=true GITHUB_OUTPUT="$OUTPUT_FILE" zsh .github/scripts/affected-tests.sh > /dev/null
    local spm_line
    spm_line=$(grep '^spm_affected=' "$OUTPUT_FILE" | tail -1)
    rm -f "$OUTPUT_FILE"
    if [[ -z "$spm_line" ]]; then
        echo "Could not determine default package list from affected-tests.sh" >&2
        exit 2
    fi
    PACKAGES=(${=spm_line#spm_affected=})
fi

echo "Packages: ${PACKAGES[*]}"
echo "Destination: $DESTINATION"
echo "Tolerance: $TOLERANCE"
echo ""

# ---------------------------------------------------------------------------
# Count parsing
# ---------------------------------------------------------------------------

# count_swift_testing <output> — sum every "Test run with N tests in M
# suites" occurrence. Each xctest bundle process prints its own line, so
# multiple -only-testing targets in one invocation each contribute a line,
# and summing them is the correct total (unlike the XCTest case below, these
# don't nest).
count_swift_testing() {
    local output="$1"
    awk '
        match($0, /Test run with [0-9]+ tests? in [0-9]+ suites?/) {
            line = substr($0, RSTART, RLENGTH)
            match(line, /[0-9]+/)
            total += substr(line, RSTART, RLENGTH)
        }
        END { print total + 0 }
    ' <<<"$output"
}

# count_xctest_all_tests <output> — the "Executed N tests" line immediately
# following the top-level "Test Suite 'All tests' (passed|failed)" marker
# only. XCTest also prints per-class and per-bundle "Executed N tests" lines
# that are subsets of this total; summing every occurrence double- and
# triple-counts the same tests.
count_xctest_all_tests() {
    local output="$1"
    awk '
        /Test Suite .All tests. (passed|failed)/ { want=1; next }
        want && match($0, /Executed [0-9]+ tests?/) {
            s = substr($0, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", s)
            total += s
            want = 0
        }
        END { print total + 0 }
    ' <<<"$output"
}

host_total_count() {
    local output="$1"
    local st xc
    st=$(count_swift_testing "$output")
    xc=$(count_xctest_all_tests "$output")
    echo $((st + xc))
}

# count_from_xcresult <path> — the authoritative simulator-side count, read
# from the .xcresult bundle's top-level totalTestCount rather than scraped
# from console output (see the file header for why). Retries up to 3 times,
# covering both failure shapes seen in practice: xcresulttool exiting
# non-zero (a first read against a freshly-written bundle failed once —
# 2026-08-06, AnalyticsMacros — with a manual retry succeeding immediately
# after, suggesting a brief finalization lag), and it exiting 0 with
# empty/unparseable output. Both are checked via an explicit `if cmd; then
# ... else rc=$?; fi` rather than a bare `result=$(...)` assignment — under
# this script's `set -euo pipefail`, a bare assignment whose pipeline fails
# triggers errexit immediately, which is a real bug this had once: a
# non-existent or invalid bundle made xcresulttool exit non-zero, `pipefail`
# propagated that through the `| python3` stage regardless of python3's own
# (always-zero) exit code, and the script died mid-package with a bare
# unlabeled line and no PARITY CHECK verdict, no attempt 2 or 3, and no
# per-package diagnostic — the retry loop below was unreachable. The `if`
# guard is what makes retrying actually happen. Prints 0 (to stdout) if the
# bundle doesn't exist, or after exhausting retries — the caller treats a 0
# count as fatal for that package, not this function.
count_from_xcresult() {
    # NOTE: the local var is deliberately not named "path" — zsh links the
    # scalar $path to the special $PATH-backing array, and shadowing it
    # breaks command lookup (mktemp/python3/xcrun/etc. all start failing
    # with "command not found") for the rest of this function's scope. Cost
    # real debugging time once already; don't reintroduce it.
    local bundle_path="$1"
    if [[ ! -e "$bundle_path" ]]; then
        echo "no result bundle at $bundle_path" >&2
        echo 0
        return
    fi
    local attempt result rc
    for attempt in 1 2 3; do
        if result=$(xcrun xcresulttool get test-results summary --path "$bundle_path" 2>/dev/null \
            | python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("totalTestCount", 0))
except Exception:
    print(0)'); then
            rc=0
        else
            rc=$?
        fi
        if [[ "$rc" -eq 0 && -n "$result" && "$result" != "0" ]]; then
            echo "$result"
            return
        fi
        if (( attempt < 3 )); then
            sleep 2
        fi
    done
    # Three attempts, still 0/unparseable/erroring — surface what
    # xcresulttool actually says rather than hiding it behind a bare "0".
    # The `|| true` matters: this diagnostic pipeline can itself fail (that
    # is the whole reason we're here), and under this script's
    # `set -euo pipefail`, an unguarded failing pipeline — even one that's
    # purely informational — triggers errexit and kills the script before
    # `echo 0` below ever runs, which is the same failure class this
    # function's retry loop exists to avoid.
    echo "xcresulttool did not return a usable count for $bundle_path after 3 attempts (last exit=$rc):" >&2
    xcrun xcresulttool get test-results summary --path "$bundle_path" 2>&1 | tail -5 >&2 || true
    echo 0
}

# ---------------------------------------------------------------------------
# Host + simulator runners
# ---------------------------------------------------------------------------

run_or_print() {
    local label="$1"; shift
    echo "==> $label" >&2
    printf '    ' >&2
    printf '%q ' "$@" >&2
    echo "" >&2
    if (( DRY_RUN == 1 )); then
        return 0
    fi
    "$@"
}

run_host() {
    local pkg="$1"
    local -a skip_args=()
    if [[ -n "${PKG_SKIP_TEST[$pkg]:-}" ]]; then
        skip_args=(--skip "${PKG_SKIP_TEST[$pkg]}")
    fi
    WXYC_SKIP_KNOWN_FLAKES=1 WXYC_SKIP_CI_HANG=1 \
        run_or_print "swift test --package-path Shared/$pkg" \
        swift test --package-path "Shared/$pkg" --disable-dependency-cache "${skip_args[@]}"
}

# scheme_for_package <pkg> — the auto-generated SwiftPM scheme that includes
# the package's test target. Packages with more than one product get a
# distinct "<Pkg>-Package" aggregate scheme; packages with exactly one
# product (matching the package name, as WXUI's does) fold the aggregate
# into the product's own scheme instead and never generate a "-Package"
# scheme at all — detect which applies rather than assuming the suffix.
scheme_for_package() {
    local pkg="$1"
    local list_output
    list_output=$(cd "Shared/$pkg" && xcodebuild -list 2>/dev/null || true)
    if grep -qE "^[[:space:]]+${pkg}-Package\$" <<<"$list_output"; then
        echo "${pkg}-Package"
    else
        echo "$pkg"
    fi
}

# result_bundle_path <pkg> — deterministic per-package .xcresult location so
# each run's count can be read back unambiguously. xcodebuild refuses to
# write into an existing bundle, so callers must rm -rf it first.
result_bundle_path() {
    local pkg="$1"
    echo "$REPO_ROOT/$DERIVED_DATA-results/$pkg.xcresult"
}

run_simulator() {
    local pkg="$1"
    local target="${PKG_TEST_TARGETS[$pkg]:?no PKG_TEST_TARGETS entry for $pkg}"
    local -a skip_args=()
    if [[ -n "${PKG_SKIP_TEST[$pkg]:-}" ]]; then
        skip_args=(-skip-testing:"$target/${PKG_SKIP_TEST[$pkg]}")
    fi
    local bundle
    bundle=$(result_bundle_path "$pkg")
    mkdir -p "${bundle:h}"
    rm -rf "$bundle"
    if [[ -n "${PKG_OUT_OF_PLAN[$pkg]:-}" ]]; then
        local scheme
        scheme=$(scheme_for_package "$pkg")
        local destination="$DESTINATION"
        if [[ -n "${PKG_MACOS_ONLY[$pkg]:-}" ]]; then
            destination="platform=macOS"
        fi
        (
            cd "Shared/$pkg"
            TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1 TEST_RUNNER_WXYC_SKIP_CI_HANG=1 \
                run_or_print "xcodebuild test -scheme $scheme -destination $destination ($pkg, not in WXYC.xctestplan)" \
                xcodebuild test \
                -scheme "$scheme" \
                -destination "$destination" \
                -skipMacroValidation \
                -derivedDataPath "$REPO_ROOT/$DERIVED_DATA" \
                -resultBundlePath "$bundle" \
                "${skip_args[@]}"
        )
    else
        TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1 TEST_RUNNER_WXYC_SKIP_CI_HANG=1 \
            run_or_print "xcodebuild test -only-testing:$target (WXYC scheme + test plan)" \
            xcodebuild test \
            -project WXYC.xcodeproj \
            -scheme WXYC \
            -testPlan WXYC \
            -only-testing:"$target" \
            -destination "$DESTINATION" \
            -skipMacroValidation \
            -derivedDataPath "$REPO_ROOT/$DERIVED_DATA" \
            -resultBundlePath "$bundle" \
            "${skip_args[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Compare
#
# Every package in PACKAGES gets a verdict — PASS, FAIL, or NOT_CHECKED —
# recorded as the loop goes and printed in a final summary once the loop
# finishes. No package's outcome can mask another's: a failure or a
# known-blocked package (see PKG_KNOWN_BLOCKED above) moves on to the next
# package via `continue`, never `exit`. An earlier version of this script
# used `exit 1` on the first fatal condition, which meant LikedSongs' known,
# unrelated xcodebuild breakage (6th in the default package-list order)
# silently prevented Metadata, MusicShareKit, Concerts, and WXUI — the two
# packages this ticket is actually about — from ever being checked in the
# same run. See PR #798 review.
# ---------------------------------------------------------------------------

typeset -A RESULT_STATUS   # pkg -> PASS | FAIL | NOT_CHECKED
typeset -A RESULT_DETAIL   # pkg -> human-readable reason, always populated
typeset -a ORDERED=()      # preserves PACKAGES order for the summary

printf '%-16s %8s %8s %8s %s\n' "PACKAGE" "HOST" "SIM" "GAP" "NOTE"
printf -- '---------------------------------------------\n'

for pkg in "${PACKAGES[@]}"; do
    ORDERED+=("$pkg")

    if [[ -z "${PKG_TEST_TARGETS[$pkg]:-}" ]]; then
        echo "No PKG_TEST_TARGETS entry for '$pkg' — add one to scripts/verify-spm-parity.sh" >&2
        exit 2
    fi

    if (( DRY_RUN == 1 )); then
        run_host "$pkg" > /dev/null
        if [[ -z "${PKG_KNOWN_BLOCKED[$pkg]:-}" ]]; then
            run_simulator "$pkg" > /dev/null
        fi
        continue
    fi

    # Host: always attempted, even for a known-blocked package — LikedSongs'
    # host side works fine; only its simulator side is blocked.
    #
    # A nonzero exit alone is not fatal — it can mean an individual test
    # failed or errored, which is not this script's concern (it compares
    # counts, not pass/fail: e.g. CachingTests has one simulator-only test
    # failure that has nothing to do with coverage). But an executed count
    # of exactly 0 is fatal on its own, regardless of exit status: a clean
    # exit with 0 tests run is the exact silent-skip signature this script
    # exists to catch. Gating the zero-count check on a nonzero exit too (an
    # earlier version of this check did) misses it — a 0-host/0-simulator
    # pair where both sides happen to exit cleanly computes gap=0 and would
    # print PARITY CHECK PASSED having verified nothing.
    host_status="ok"
    if host_output=$(run_host "$pkg" 2>&1); then
        :
    else
        host_status="exit $?"
    fi
    host_count=$(host_total_count "$host_output")
    if [[ "$host_count" -eq 0 ]]; then
        echo "$host_output" >&2
        RESULT_STATUS[$pkg]="FAIL"
        RESULT_DETAIL[$pkg]="host executed 0 tests ($host_status) — silent-skip signature, fatal regardless of exit status"
        printf '%-16s %8s %8s %8s %s\n' "$pkg" "0" "-" "-" "FAIL: 0 host tests"
        continue
    fi

    if [[ -n "${PKG_KNOWN_BLOCKED[$pkg]:-}" ]]; then
        RESULT_STATUS[$pkg]="NOT_CHECKED"
        RESULT_DETAIL[$pkg]="${PKG_KNOWN_BLOCKED[$pkg]}"
        printf '%-16s %8s %8s %8s %s\n' "$pkg" "$host_count" "n/a" "n/a" "NOT CHECKED — see summary"
        continue
    fi

    sim_status="ok"
    if sim_output=$(run_simulator "$pkg" 2>&1); then
        :
    else
        sim_status="exit $?"
    fi
    sim_count=$(count_from_xcresult "$(result_bundle_path "$pkg")")
    if [[ "$sim_count" -eq 0 ]]; then
        echo "$sim_output" >&2
        RESULT_STATUS[$pkg]="FAIL"
        RESULT_DETAIL[$pkg]="simulator executed 0 tests ($sim_status) — silent-skip signature, fatal regardless of exit status"
        printf '%-16s %8s %8s %8s %s\n' "$pkg" "$host_count" "0" "-" "FAIL: 0 sim tests"
        continue
    fi

    gap=$((sim_count - host_count))
    local note=""
    [[ "$host_status" != "ok" ]] && note="$note host:$host_status"
    [[ "$sim_status" != "ok" ]] && note="$note sim:$sim_status"
    printf '%-16s %8s %8s %8s %s\n' "$pkg" "$host_count" "$sim_count" "$gap" "$note"

    if (( gap > TOLERANCE )); then
        RESULT_STATUS[$pkg]="FAIL"
        RESULT_DETAIL[$pkg]="host=$host_count sim=$sim_count gap=$gap (tolerance=$TOLERANCE) — host is silently skipping simulator-only coverage"
    elif (( -gap > TOLERANCE )); then
        # The inverse shouldn't happen for real coverage (a package
        # legitimately having MORE tests on host than the simulator finds is
        # not a known scenario here) — flag it too rather than silently
        # accepting it. This exact case caught a bug in this script itself
        # once already: a broken simulator-side count reader reported 0.
        RESULT_STATUS[$pkg]="FAIL"
        RESULT_DETAIL[$pkg]="host=$host_count sim=$sim_count gap=$gap (tolerance=$TOLERANCE) — simulator count is suspiciously low; verify the .xcresult bundle rather than assuming this is fine"
    else
        RESULT_STATUS[$pkg]="PASS"
        RESULT_DETAIL[$pkg]="host=$host_count sim=$sim_count gap=$gap${note:+ ($note)}"
    fi
done

if (( DRY_RUN == 1 )); then
    echo ""
    echo "DRY RUN — no commands executed, no counts compared"
    exit 0
fi

echo ""
echo "SUMMARY"
printf -- '---------------------------------------------\n'
typeset -i pass_count=0 fail_count=0 not_checked_count=0
for pkg in "${ORDERED[@]}"; do
    printf '%-16s %-11s %s\n' "$pkg" "${RESULT_STATUS[$pkg]}" "${RESULT_DETAIL[$pkg]}"
    case "${RESULT_STATUS[$pkg]}" in
        PASS)        pass_count=$((pass_count + 1)) ;;
        FAIL)        fail_count=$((fail_count + 1)) ;;
        NOT_CHECKED) not_checked_count=$((not_checked_count + 1)) ;;
    esac
done
echo ""
echo "$pass_count passed, $fail_count failed, $not_checked_count not checked (of ${#ORDERED[@]} total)."

if (( fail_count > 0 || not_checked_count > 0 )); then
    echo "PARITY CHECK FAILED"
    exit 1
fi

echo "PARITY CHECK PASSED — all ${#ORDERED[@]} package(s) within tolerance ($TOLERANCE)."
