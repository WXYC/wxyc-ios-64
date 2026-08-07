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
#                           per package before it's flagged. Default: 1 —
#                           observed non-zero on Concerts even in the ticket's
#                           own investigation (222 declared / 221 host), so a
#                           strict 0 would false-positive on a package that
#                           is otherwise fine. Real silent-skip shortfalls
#                           (ColorPalette: 23, Playback: ~120+) are one to two
#                           orders of magnitude past this.
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
#   scripts/verify-spm-parity.sh                          # today's SPM_RUNNABLE (must pass)
#   scripts/verify-spm-parity.sh AnalyticsMacros Core \
#     Caching Analytics Playlist LikedSongs Metadata \
#     MusicShareKit Concerts WXUI ColorPalette            # negative case (must fail on ColorPalette)
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
#   - Host (`swift test`): text log parsing, handling both frameworks a test
#     target can print (several targets in this repo mix them in one
#     bundle):
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
TOLERANCE=1
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
                          per package before it's flagged. Default: 1.
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
# from console output (see the file header for why). Prints 0 if the bundle
# doesn't exist (xcodebuild never got far enough to write one) or the field
# can't be parsed. Retries a couple of times on failure — xcodebuild returns
# once the bundle is written, but a first empty/failed read was observed in
# practice (2026-08-06, AnalyticsMacros) with a subsequent manual read of the
# same bundle succeeding immediately after, which looks like a brief
# finalization lag rather than a parsing bug; retrying is cheap insurance
# either way, and a persistent failure still surfaces its actual error
# instead of being silently swallowed.
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
    local attempt result err
    for attempt in 1 2 3; do
        err=$(mktemp)
        result=$(xcrun xcresulttool get test-results summary --path "$bundle_path" 2>"$err" \
            | python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("totalTestCount", 0))
except Exception as e:
    print("PARSE_ERROR:" + str(e), file=sys.stderr)
    print(0)')
        if [[ -n "$result" && "$result" != "0" ]]; then
            rm -f "$err"
            echo "$result"
            return
        fi
        if (( attempt < 3 )); then
            sleep 2
        fi
        rm -f "$err"
    done
    # Three attempts, still 0 (or unparseable) — could be genuine (a target
    # with no tests) or a real failure. Either way, surface what
    # xcresulttool actually said rather than hiding it.
    echo "xcresulttool result for $bundle_path (last attempt):" >&2
    xcrun xcresulttool get test-results summary --path "$bundle_path" 2>&1 | tail -5 >&2
    echo "${result:-0}"
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
# ---------------------------------------------------------------------------

typeset -a failures=()
printf '%-16s %8s %8s %8s %s\n' "PACKAGE" "HOST" "SIM" "GAP" "NOTE"
printf -- '---------------------------------------------\n'

for pkg in "${PACKAGES[@]}"; do
    if [[ -z "${PKG_TEST_TARGETS[$pkg]:-}" ]]; then
        echo "No PKG_TEST_TARGETS entry for '$pkg' — add one to scripts/verify-spm-parity.sh" >&2
        exit 2
    fi

    if (( DRY_RUN == 1 )); then
        run_host "$pkg" > /dev/null
        run_simulator "$pkg" > /dev/null
        continue
    fi

    # A nonzero exit means some individual test failed or errored — not this
    # script's concern (it compares counts, not pass/fail). Only a run that
    # produced zero parseable tests AND a nonzero exit is treated as fatal:
    # that's the signature of the tooling itself never starting (bad scheme,
    # missing target, build failure), as opposed to a real test failure
    # inside an otherwise-normal run.
    host_status="ok"
    if host_output=$(run_host "$pkg" 2>&1); then
        :
    else
        host_status="exit $?"
    fi
    host_count=$(host_total_count "$host_output")
    if [[ "$host_status" != "ok" && "$host_count" -eq 0 ]]; then
        echo "$host_output" >&2
        echo "swift test produced no parseable test count for $pkg ($host_status) — treating as a tooling failure, not a test failure" >&2
        exit 1
    fi

    sim_status="ok"
    if sim_output=$(run_simulator "$pkg" 2>&1); then
        :
    else
        sim_status="exit $?"
    fi
    sim_count=$(count_from_xcresult "$(result_bundle_path "$pkg")")
    if [[ "$sim_status" != "ok" && "$sim_count" -eq 0 ]]; then
        echo "$sim_output" >&2
        echo "xcodebuild test produced no parseable test count for $pkg ($sim_status) — treating as a tooling failure, not a test failure" >&2
        exit 1
    fi

    gap=$((sim_count - host_count))
    local note=""
    [[ "$host_status" != "ok" ]] && note="$note host:$host_status"
    [[ "$sim_status" != "ok" ]] && note="$note sim:$sim_status"
    printf '%-16s %8d %8d %8d %s\n' "$pkg" "$host_count" "$sim_count" "$gap" "$note"

    if (( gap > TOLERANCE )); then
        failures+=("$pkg: host=$host_count sim=$sim_count gap=$gap (tolerance=$TOLERANCE) — host is silently skipping simulator-only coverage")
    elif (( -gap > TOLERANCE )); then
        # The inverse shouldn't happen for real coverage (a package
        # legitimately having MORE tests on host than the simulator finds is
        # not a known scenario here) — flag it too rather than silently
        # accepting it. This exact case caught a bug in this script itself
        # once already: a broken simulator-side count reader reported 0.
        failures+=("$pkg: host=$host_count sim=$sim_count gap=$gap (tolerance=$TOLERANCE) — simulator count is suspiciously low; verify the .xcresult bundle rather than assuming this is fine")
    fi
done

if (( DRY_RUN == 1 )); then
    echo ""
    echo "DRY RUN — no commands executed, no counts compared"
    exit 0
fi

echo ""
if (( ${#failures[@]} > 0 )); then
    echo "PARITY CHECK FAILED — silent host-side skip detected:"
    for f in "${failures[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "PARITY CHECK PASSED — all ${#PACKAGES[@]} package(s) within tolerance ($TOLERANCE)."
