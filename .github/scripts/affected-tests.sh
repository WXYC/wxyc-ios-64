#!/bin/zsh
#
# affected-tests.sh
#
# Determines which test targets are affected by changes on the current branch
# and outputs -skip-testing: flags for unaffected targets. This lets CI skip
# tests for packages that haven't changed, while running everything by default
# for new/unknown targets (fail-open via -skip-testing: instead of -only-testing:).
#
# Inputs:
#   BASE_REF       — the base branch ref to diff against (e.g. "origin/master").
#                    If empty, outputs run_all=true (used for workflow_dispatch).
#   CHANGED_FILES  — (optional) newline-separated file paths. If set, used
#                    directly instead of computing a git diff. Used by the
#                    local test-affected.sh wrapper to include working-tree
#                    changes (which BASE_REF...HEAD excludes).
#
# Outputs (written to $GITHUB_OUTPUT):
#   run_all            — "true" if all tests should run, "false" otherwise
#   skip_testing_flags — space-separated -skip-testing: flags for xcodebuild
#   only_testing_flags — space-separated -only-testing: flags for xcodebuild
#   spm_affected       — space-separated SPM-runnable package names (host-tested
#                        via `swift test --package-path Shared/<pkg>`)
#   xcb_required       — "true" when xcodebuild + simulator is required (any
#                        non-SPM-runnable affected package, or the WXYCTests
#                        app-integration safety net)
#   affected_summary   — human-readable summary for the step log
#
# The dependency graph is hardcoded from Shared/*/Package.swift. Update it
# when packages are added, removed, or have their dependencies changed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "$1=$2" >> "$GITHUB_OUTPUT"
    fi
    echo "  $1=$2"
}

run_all_and_exit() {
    local reason="$1"
    echo "Running all tests: $reason"
    # SPM-runnable packages run via swift test on host; xcodebuild skips their
    # test targets to avoid double coverage. Keep in sync with SPM_RUNNABLE in
    # step 8a below.
    local spm_all="AnalyticsMacros Core Caching Analytics Playlist LikedSongs Metadata MusicShareKit Concerts WXUI"
    local skip="-skip-testing:WXYCUITests"
    skip="$skip -skip-testing:AnalyticsMacrosTests"
    skip="$skip -skip-testing:CoreTests -skip-testing:CachingTests -skip-testing:AnalyticsTests"
    skip="$skip -skip-testing:PlaylistTests -skip-testing:LikedSongsTests"
    skip="$skip -skip-testing:MetadataTests -skip-testing:MusicShareKitTests"
    # ConcertsTests and WXUITests are deliberately absent from WXYC.xctestplan
    # (they run via the swift-test step against the auto-generated per-package
    # scheme instead — see docs/build-test.md), so these flags are inert today.
    # They exist so a future addition of either target to the plan can't
    # double-run it without also updating this list.
    skip="$skip -skip-testing:ConcertsTests -skip-testing:WXUITests"
    output "run_all" "true"
    output "skip_testing_flags" "$skip"
    output "only_testing_flags" ""
    output "spm_affected" "$spm_all"
    output "xcb_required" "true"
    output "affected_summary" "all tests ($reason)"
    exit 0
}

# ---------------------------------------------------------------------------
# 0. FORCE_RUN_ALL — lets callers (scripts/test-affected.sh --full,
#    scripts/verify-spm-parity.sh) get the run_all_and_exit lists (spm_all,
#    skip flags) without duplicating them. This is the single source of truth
#    for "what runs when everything runs" — see run_all_and_exit above.
# ---------------------------------------------------------------------------

if [[ "${FORCE_RUN_ALL:-false}" == "true" ]]; then
    run_all_and_exit "forced (FORCE_RUN_ALL=true)"
fi

# ---------------------------------------------------------------------------
# 1. No base ref → run everything (workflow_dispatch)
# ---------------------------------------------------------------------------

if [[ -z "${BASE_REF:-}" ]]; then
    run_all_and_exit "no base ref (manual dispatch)"
fi

# ---------------------------------------------------------------------------
# 2. Compute changed files
# ---------------------------------------------------------------------------

if [[ -n "${CHANGED_FILES:-}" ]]; then
    changed_files="$CHANGED_FILES"
else
    changed_files=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null) || {
        run_all_and_exit "git diff failed"
    }
fi

if [[ -z "$changed_files" ]]; then
    run_all_and_exit "no changed files"
fi

echo "Changed files:"
echo "$changed_files" | sed 's/^/  /'
echo ""

# ---------------------------------------------------------------------------
# 3. Check for fallback triggers (changes that could affect any test)
# ---------------------------------------------------------------------------

while IFS= read -r file; do
    case "$file" in
        Shared/*)                                 ;; # handled in step 4
        WXYC/*)                                   run_all_and_exit "app source changed: $file" ;;
        *.xcodeproj/*)                            run_all_and_exit "project file changed: $file" ;;
        *.xctestplan)                             run_all_and_exit "test plan changed: $file" ;;
        .github/scripts/affected-tests.sh)        run_all_and_exit "affected-tests.sh changed" ;;
        .github/workflows/build-and-test.yml)     run_all_and_exit "build-and-test workflow changed" ;;
        *)                                        echo "  ignoring non-code file: $file" ;;
    esac
done <<< "$changed_files"

# ---------------------------------------------------------------------------
# 4. Map changed files to package names
# ---------------------------------------------------------------------------

typeset -A changed_packages

while IFS= read -r file; do
    case "$file" in
        Shared/*)
            local pkg="${file#Shared/}"
            pkg="${pkg%%/*}"
            if [[ -n "$pkg" ]]; then
                changed_packages[$pkg]=1
            fi
            ;;
    esac
done <<< "$changed_files"

echo "Directly changed packages: ${(k)changed_packages}"

# ---------------------------------------------------------------------------
# 5. Dependency graph (package → its direct dependencies)
#    Source of truth: Shared/*/Package.swift
# ---------------------------------------------------------------------------

typeset -A DEPS
DEPS[Logger]=""
DEPS[WXUI]=""
DEPS[AnalyticsMacros]=""
DEPS[Core]="Logger"
DEPS[Caching]="Core Logger"
DEPS[Analytics]="AnalyticsMacros Logger"
DEPS[Playlist]="Analytics Core Caching Logger WXYCAPIModels Concerts"
DEPS[LikedSongs]="Core Playlist Logger"
DEPS[Playback]="Caching Core Analytics Logger"
DEPS[Artwork]="Core Caching Playlist Logger"
DEPS[ColorPalette]="Core"
DEPS[MusicShareKit]="WXUI Logger Core Analytics Caching"
DEPS[Wallpaper]="Analytics Caching ColorPalette Core Logger WXUI"
DEPS[Metadata]="Core Caching Playlist Logger WXYCAPIModels"
DEPS[PlayerHeaderView]="Caching Playback Wallpaper WXUI"
# `Intents` and `Concerts` are both declared in Shared/AppServices/Package.swift
# (platform-conditioned on iOS/macCatalyst/macOS) and had long gone unrecorded
# here. #805 is the demonstration: renaming Intents' reindexer protocols breaks
# AppServices' conformances to them, yet without this edge a WXYCIntents-only
# change selects WXYCIntentsTests and never AppServicesTests.
DEPS[AppServices]="Core Playback Playlist Artwork Caching Analytics Logger Intents Concerts"
# `Caching` is #751's addition (the widget bootstrap's in-memory
# PlaycutHistoryStore default).
DEPS[Intents]="Analytics Caching Concerts Core Logger Playback Playlist"
DEPS[Concerts]="Core Logger"
# Packages without test targets (included as dependency intermediaries)
DEPS[DebugPanel]="AppServices Caching Playback Playlist Wallpaper PlayerHeaderView WXUI"
DEPS[PartyHorn]=""
# Vendored generated DTOs (no test target). A Metadata (runtime) dep and a
# PlaylistTests-target dep; listed on both above so a change to it marks
# MetadataTests + PlaylistTests affected. As a non-SPM-runnable package with no
# test target, a direct change to it also conservatively forces the xcb net.
DEPS[WXYCAPIModels]=""

# ---------------------------------------------------------------------------
# 6. Compute reverse dependency map (package → packages that depend on it)
# ---------------------------------------------------------------------------

typeset -A REVERSE_DEPS

for pkg in ${(k)DEPS}; do
    for dep in ${=DEPS[$pkg]}; do
        if [[ -n "${REVERSE_DEPS[$dep]:-}" ]]; then
            REVERSE_DEPS[$dep]="${REVERSE_DEPS[$dep]} $pkg"
        else
            REVERSE_DEPS[$dep]="$pkg"
        fi
    done
done

# ---------------------------------------------------------------------------
# 7. Compute transitive closure of affected packages
# ---------------------------------------------------------------------------

typeset -A affected
for pkg in ${(k)changed_packages}; do
    affected[$pkg]=1
done

local changed=true
while $changed; do
    changed=false
    for pkg in ${(k)affected}; do
        for dependent in ${=REVERSE_DEPS[$pkg]:-}; do
            if [[ -z "${affected[$dependent]:-}" ]]; then
                affected[$dependent]=1
                changed=true
            fi
        done
    done
done

echo "Affected packages (with transitive dependents): ${(k)affected}"

# ---------------------------------------------------------------------------
# 8. Map affected packages to test targets
# ---------------------------------------------------------------------------

typeset -A TEST_TARGETS
TEST_TARGETS[Logger]="LoggerTests"
TEST_TARGETS[AnalyticsMacros]="AnalyticsMacrosTests"
TEST_TARGETS[Core]="CoreTests"
TEST_TARGETS[Caching]="CachingTests"
TEST_TARGETS[Analytics]="AnalyticsTests"
TEST_TARGETS[Playlist]="PlaylistTests"
TEST_TARGETS[LikedSongs]="LikedSongsTests"
TEST_TARGETS[Playback]="PlaybackTests RadioPlayerTests MP3StreamerTests HLSPlayerTests"
TEST_TARGETS[Artwork]="ArtworkTests"
TEST_TARGETS[ColorPalette]="ColorPaletteTests"
TEST_TARGETS[Wallpaper]="WallpaperTests"
TEST_TARGETS[Metadata]="MetadataTests"
TEST_TARGETS[MusicShareKit]="MusicShareKitTests"
TEST_TARGETS[PlayerHeaderView]="PlayerHeaderViewTests"
TEST_TARGETS[AppServices]="AppServicesTests"
TEST_TARGETS[Intents]="WXYCIntentsTests"
TEST_TARGETS[PartyHorn]="PartyHornTests"
TEST_TARGETS[Concerts]="ConcertsTests"
TEST_TARGETS[WXUI]="WXUITests"

# ---------------------------------------------------------------------------
# 8a. Partition affected packages into SPM-runnable vs xcodebuild-required.
#     SPM-runnable packages run via `swift test --package-path Shared/<pkg>` on
#     the macOS host, bypassing xcodebuild + simulator. Their test targets are
#     also excluded from xcodebuild's only_testing scope to avoid double
#     coverage.
#
#     Every package on this list is expected to pass
#     scripts/verify-spm-parity.sh — the host swift-test count must match the
#     simulator xcodebuild count (or come within the script's tolerance). Run
#     that script before adding a package here; a package that "passes"
#     swift test while silently skipping real coverage is not safe to add
#     (see #797, which added this guard after two silent-skip incidents).
#
#     Excluded (forces xcb):
#       - AppServices       — MockURLProtocol static handler + WidgetCenter
#                             cause host hangs
#       - Logger            — global Logger.addDestination shared mutable state
#                             races (suite-level test interference). Note
#                             this is worse than the other exclusions on this
#                             list: LoggerTests (16 tests) is ALSO absent
#                             from WXYC.xctestplan's targets, so excluding it
#                             here does not fall through to xcb the way the
#                             comment used to imply — LoggerTests currently
#                             runs in no CI configuration at all. Tracked in
#                             #800; do not add Logger here without either
#                             fixing the race or adding LoggerTests to the
#                             plan.
#       - Playback          — dozens of #if canImport(UIKit)/os() platform-
#                             gate directives across its test files silently
#                             skip on the macOS host. Measured 2026-08-06:
#                             `swift test --package-path Shared/Playback`
#                             actually executes 329 tests; a grep count of
#                             `@Test` attributes across Shared/Playback/Tests
#                             finds 449+ (a floor, not the true simulator
#                             total — parameterized `@Test(arguments:)` cases
#                             expand at run time, so the real gap is larger).
#                             Same failure mode as ColorPalette below, at a
#                             much larger scale, in the package that covers
#                             audio playback. Also, MP3Streamer's state-
#                             tracking test diverges between macOS host
#                             AudioToolbox and the iOS simulator independent
#                             of the gap above. Do not move without first
#                             lifting the platform gates and running
#                             scripts/verify-spm-parity.sh Playback for real
#                             (not this ticket — see #797's non-goals).
#       - ColorPalette      — DominantColorExtractor is wrapped in
#                             #if canImport(UIKit) and silently skips on the
#                             macOS host (#394).
#                             Measured 2026-08-07 with
#                             `scripts/verify-spm-parity.sh ColorPalette`
#                             (added by #797, which is also why this is an
#                             exact rerunnable command and not just a
#                             description): 21 executed on host, 44 on the
#                             simulator, a 23-test gap — it fails the check
#                             as expected. Run via xcb in the iOS simulator
#                             instead. The earlier 25/59/34 reading counted
#                             two suites #754 deleted, and they moved
#                             different halves of it: ColorPaletteCacheKey-
#                             Tests (4 tests, ungated) is the whole host-side
#                             drop, 25 → 21, and ColorPaletteServiceTests
#                             (11 tests, entirely inside canImport(UIKit), so
#                             0 on host) came off the simulator alone. Sim
#                             59 → 44 is those 15 together. The gap narrowed
#                             by exactly the 11 gated service tests but did
#                             not close, because DominantColorExtractorTests
#                             (21 tests, all gated) was always the larger
#                             half of it.
#       - Artwork           — ArtworkTests bundle hangs at 0% CPU on
#                             macos-latest paravirt (root cause unclear;
#                             suspected module-init or shared-singleton
#                             interaction with @testable import Artwork).
#                             Re-add once the hang is diagnosed.
#       - Intents           — an 18-to-20-test gap between the declared
#                             suite and what runs on host (182 executed on
#                             host as of 2026-08-06), cause not yet root-
#                             caused. Named follow-up from #368; still open
#                             per #797's non-goals. Excluded pending
#                             investigation, not because of a confirmed
#                             platform-gate skip like ColorPalette/Playback.
#       - PartyHorn         — Vortex / Bundle.module not host-portable
#       - PlayerHeaderView  — depends on Wallpaper (a git submodule)
#       - Wallpaper         — submodule
# ---------------------------------------------------------------------------

local -a SPM_RUNNABLE=(AnalyticsMacros Core Caching Analytics Playlist LikedSongs Metadata MusicShareKit Concerts WXUI)
typeset -A SPM_RUNNABLE_SET
for pkg in $SPM_RUNNABLE; do
    SPM_RUNNABLE_SET[$pkg]=1
done

local spm_affected_list=""
local xcb_required="false"

for pkg in ${(k)affected}; do
    if [[ -n "${SPM_RUNNABLE_SET[$pkg]:-}" ]]; then
        if [[ -z "$spm_affected_list" ]]; then
            spm_affected_list="$pkg"
        else
            spm_affected_list="$spm_affected_list $pkg"
        fi
    else
        xcb_required="true"
    fi
done

# WXYCTests is an app-target integration safety net for changes that aren't
# fully covered by per-package tests. Only force it when xcodebuild is already
# required — pure-SPM affected sets are covered by their `swift test` runs.
typeset -A affected_targets
if [[ "$xcb_required" == "true" ]]; then
    affected_targets[WXYCTests]=1
fi

# Only add xcb test targets for non-SPM-runnable affected packages. SPM-runnable
# packages are covered by the swift-test step; adding their xcb targets here
# would double-cover and waste simulator time.
for pkg in ${(k)affected}; do
    if [[ -n "${SPM_RUNNABLE_SET[$pkg]:-}" ]]; then
        continue
    fi
    for target in ${=TEST_TARGETS[$pkg]:-}; do
        affected_targets[$target]=1
    done
done

echo "SPM-affected (host-runnable): $spm_affected_list"
echo "xcb required: $xcb_required"
echo "Affected test targets: ${(k)affected_targets}"

# ---------------------------------------------------------------------------
# 9. Determine which test plan targets to skip in the xcodebuild step.
#    These are the 19 targets in WXYC.xctestplan. WXYCUITests is always
#    skipped. CoreTests runs via `swift test --package-path Shared/Core`
#    (host) instead of xcodebuild, bypassing Swift Testing's parallel-scheduler
#    hang under load — so it's always in skip_flags here, and the workflow's
#    swift-test step covers it when Core is affected.
# ---------------------------------------------------------------------------

local all_test_plan_targets=(
    PlaylistTests
    LikedSongsTests
    WXYCTests
    ArtworkTests
    RadioPlayerTests
    MP3StreamerTests
    CachingTests
    MusicShareKitTests
    PlayerHeaderViewTests
    MetadataTests
    CoreTests
    AppServicesTests
    PlaybackTests
    HLSPlayerTests
    WallpaperTests
    ColorPaletteTests
    AnalyticsTests
    PartyHornTests
    WXYCIntentsTests
)

local skip_flags="-skip-testing:WXYCUITests -skip-testing:CoreTests"
local only_flags=""
local skipped_count=0

for target in $all_test_plan_targets; do
    if [[ "$target" == "CoreTests" ]]; then
        continue # always skipped from xcodebuild; covered by swift test
    fi
    if [[ -z "${affected_targets[$target]:-}" ]]; then
        skip_flags="$skip_flags -skip-testing:$target"
        skipped_count=$((skipped_count + 1))
    else
        only_flags="$only_flags -only-testing:$target"
    fi
done

local affected_count=${#affected[@]}
local summary="${(k)changed_packages} ($affected_count affected packages, $skipped_count test targets skipped)"

echo ""
echo "Skip flags: $skip_flags"
echo "Only flags: $only_flags"
echo "Summary: $summary"

output "run_all" "false"
output "skip_testing_flags" "$skip_flags"
output "only_testing_flags" "$only_flags"
output "spm_affected" "$spm_affected_list"
output "xcb_required" "$xcb_required"
output "affected_summary" "$summary"
