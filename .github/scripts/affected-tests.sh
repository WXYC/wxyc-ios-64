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
#   BASE_REF  — the base branch ref to diff against (e.g. "origin/master").
#               If empty, outputs run_all=true (used for workflow_dispatch).
#
# Outputs (written to $GITHUB_OUTPUT):
#   run_all            — "true" if all tests should run, "false" otherwise
#   skip_testing_flags — space-separated -skip-testing: flags for xcodebuild
#   run_core_tests     — "true" if CoreTests is in the affected set
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
    output "run_all" "true"
    output "skip_testing_flags" "-skip-testing:WXYCUITests -skip-testing:CoreTests"
    output "run_core_tests" "true"
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

changed_files=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null) || {
    run_all_and_exit "git diff failed"
}

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
        Shared/*)          ;; # handled in step 4
        WXYC/*)            run_all_and_exit "app source changed: $file" ;;
        *.xcodeproj/*)     run_all_and_exit "project file changed: $file" ;;
        *.xctestplan)      run_all_and_exit "test plan changed: $file" ;;
        *)                 echo "  ignoring non-code file: $file" ;;
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
TEST_TARGETS[Playback]="PlaybackTests RadioPlayerTests MP3StreamerTests HLSPlayerTests"
TEST_TARGETS[Artwork]="ArtworkTests"
TEST_TARGETS[ColorPalette]="ColorPaletteTests"
TEST_TARGETS[SemanticIndex]="SemanticIndexTests"
TEST_TARGETS[Wallpaper]="WallpaperTests"
TEST_TARGETS[Metadata]="MetadataTests"
TEST_TARGETS[MusicShareKit]="MusicShareKitTests"
TEST_TARGETS[PlayerHeaderView]="PlayerHeaderViewTests"
TEST_TARGETS[AppServices]="AppServicesTests"

typeset -A affected_targets
# WXYCTests always runs when any package changes
affected_targets[WXYCTests]=1

for pkg in ${(k)affected}; do
    for target in ${=TEST_TARGETS[$pkg]:-}; do
        affected_targets[$target]=1
    done
done

echo "Affected test targets: ${(k)affected_targets}"

# ---------------------------------------------------------------------------
# 9. Determine which test plan targets to skip
#    These are the 18 targets in WXYC.xctestplan. WXYCUITests is always
#    skipped (existing behavior). CoreTests is handled by a separate step.
# ---------------------------------------------------------------------------

local all_test_plan_targets=(
    PlaylistTests
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
    SemanticIndexTests
)

local skip_flags="-skip-testing:WXYCUITests"
local skipped_count=0

for target in $all_test_plan_targets; do
    if [[ -z "${affected_targets[$target]:-}" ]]; then
        skip_flags="$skip_flags -skip-testing:$target"
        skipped_count=$((skipped_count + 1))
    fi
done

# CoreTests is always skipped from the main test step (it runs in its own step)
if [[ -z "${skip_flags##*-skip-testing:CoreTests*}" ]]; then
    : # already skipped because it's unaffected
else
    skip_flags="$skip_flags -skip-testing:CoreTests"
fi

local run_core_tests="false"
if [[ -n "${affected_targets[CoreTests]:-}" ]]; then
    run_core_tests="true"
fi

local affected_count=${#affected[@]}
local summary="${(k)changed_packages} ($affected_count affected packages, $skipped_count test targets skipped)"

echo ""
echo "Skip flags: $skip_flags"
echo "Run CoreTests: $run_core_tests"
echo "Summary: $summary"

output "run_all" "false"
output "skip_testing_flags" "$skip_flags"
output "run_core_tests" "$run_core_tests"
output "affected_summary" "$summary"
