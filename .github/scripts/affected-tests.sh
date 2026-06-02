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
    local spm_all="AnalyticsMacros Core Caching Analytics ColorPalette Playlist"
    local skip="-skip-testing:WXYCUITests"
    skip="$skip -skip-testing:AnalyticsMacrosTests"
    skip="$skip -skip-testing:CoreTests -skip-testing:CachingTests -skip-testing:AnalyticsTests"
    skip="$skip -skip-testing:ColorPaletteTests -skip-testing:PlaylistTests"
    output "run_all" "true"
    output "skip_testing_flags" "$skip"
    output "only_testing_flags" ""
    output "spm_affected" "$spm_all"
    output "xcb_required" "true"
    output "affected_summary" "all tests ($reason)"
    exit 0
}

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
DEPS[Playlist]="Analytics Core Caching Logger"
DEPS[Playback]="Caching Core Analytics Logger"
DEPS[Artwork]="Core Caching Playlist Logger"
DEPS[ColorPalette]="Caching Core Logger"
DEPS[SemanticIndex]="Core Caching Logger"
DEPS[MusicShareKit]="WXUI Logger Core Analytics Caching"
DEPS[Wallpaper]="Analytics Caching ColorPalette Core Logger WXUI"
DEPS[Metadata]="Artwork Core Caching Playlist Logger"
DEPS[PlayerHeaderView]="Caching Playback Wallpaper WXUI"
DEPS[AppServices]="Core Playback Playlist Artwork Caching Analytics Logger"
# Packages without test targets (included as dependency intermediaries)
DEPS[DebugPanel]="AppServices Caching Playback Playlist Wallpaper PlayerHeaderView"
DEPS[Intents]="Analytics Logger Playback"
DEPS[PartyHorn]=""

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
TEST_TARGETS[Playback]="PlaybackTests"
TEST_TARGETS[Artwork]="ArtworkTests"
TEST_TARGETS[ColorPalette]="ColorPaletteTests"
TEST_TARGETS[Wallpaper]="WallpaperTests"
TEST_TARGETS[Metadata]="MetadataTests"
TEST_TARGETS[MusicShareKit]="MusicShareKitTests"
TEST_TARGETS[PlayerHeaderView]="PlayerHeaderViewTests"
TEST_TARGETS[AppServices]="AppServicesTests"
TEST_TARGETS[PartyHorn]="PartyHornTests"

# ---------------------------------------------------------------------------
# 8a. Partition affected packages into SPM-runnable vs xcodebuild-required.
#     SPM-runnable packages run via `swift test --package-path Shared/<pkg>` on
#     the macOS host, bypassing xcodebuild + simulator. Their test targets are
#     also excluded from xcodebuild's only_testing scope to avoid double
#     coverage.
#
#     Excluded (forces xcb):
#       - AppServices       — MockURLProtocol static handler + WidgetCenter
#                             cause host hangs
#       - Logger            — global Logger.addDestination shared mutable state
#                             races (suite-level test interference)
#       - Playback          — MP3Streamer state-tracking test diverges between
#                             macOS host AudioToolbox and iOS simulator
#       - Artwork           — swift test hangs indefinitely on macos-latest
#                             (no test ever runs after the runner finishes
#                             linking ArtworkPackageTests); locally fine
#       - Metadata          — untested on CI virtualization; deferred until
#                             Artwork's hang is diagnosed
#       - PartyHorn         — Vortex / Bundle.module not host-portable
#       - MusicShareKit     — uses SwiftUI #Preview macro at host build time
#       - PlayerHeaderView  — depends on Wallpaper (a git submodule)
#       - Wallpaper         — submodule
# ---------------------------------------------------------------------------

local -a SPM_RUNNABLE=(AnalyticsMacros Core Caching Analytics ColorPalette Playlist)
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
#    These are the 17 targets in WXYC.xctestplan. WXYCUITests is always
#    skipped. CoreTests runs via `swift test --package-path Shared/Core`
#    (host) instead of xcodebuild, bypassing Swift Testing's parallel-scheduler
#    hang under load — so it's always in skip_flags here, and the workflow's
#    swift-test step covers it when Core is affected.
# ---------------------------------------------------------------------------

local all_test_plan_targets=(
    PlaylistTests
    WXYCTests
    ArtworkTests
    CachingTests
    MusicShareKitTests
    PlayerHeaderViewTests
    MetadataTests
    CoreTests
    AppServicesTests
    PlaybackTests
    WallpaperTests
    ColorPaletteTests
    AnalyticsTests
    PartyHornTests
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
