#!/bin/zsh
#
# test-affected-error-fallback.sh
#
# Black-box regression test for scripts/test-affected.sh's behavior when
# .github/scripts/affected-tests.sh itself fails (crashes) instead of
# reporting a normal run_all/scoped result.
#
# The bug: in the local-diff branch (the non---full path), a nonzero exit
# from affected-tests.sh is caught and the script hand-sets RUN_ALL="true"
# and XCB_REQUIRED="true", but never touches SPM_AFFECTED (which stays at
# its initial "") or SKIP_FLAGS (which stays at its initial
# "-skip-testing:WXYCUITests -skip-testing:CoreTests" — a narrower list than
# the one affected-tests.sh's own run_all_and_exit would have produced).
# CoreTests is deliberately routed away from xcodebuild (it hangs there
# under load, see affected-tests.sh's own comments) and is only ever
# exercised by `swift test --package-path Shared/Core` when Core appears in
# SPM_AFFECTED. With SPM_AFFECTED empty and CoreTests skipped in the
# xcodebuild command, CoreTests runs under neither runner — precisely in the
# scenario (an error) where you most want full coverage.
#
# The fixture below copies the REAL scripts/test-affected.sh (so this test
# always exercises current file content, not a stale copy) into a throwaway
# git repo alongside a STUB .github/scripts/affected-tests.sh that fails
# unless invoked with FORCE_RUN_ALL=true — modeling a genuine internal crash
# in the real script's diff-dependent code paths while leaving its
# FORCE_RUN_ALL fast path (used verbatim by the --full flag) intact. This
# mirrors run_all_and_exit's real output shape (spm_affected includes Core;
# skip_testing_flags still skips CoreTests, because SPM covers it) so a
# correct retry-on-failure fix is distinguishable from a "just run
# everything under xcodebuild including CoreTests" fix that would reintroduce
# the parallel-scheduler hang.
#
# Run directly:
#   zsh scripts/tests/test-affected-error-fallback.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
REAL_SCRIPT="${REPO_ROOT}/scripts/test-affected.sh"

if [[ ! -f "$REAL_SCRIPT" ]]; then
    echo "Cannot find scripts/test-affected.sh at $REAL_SCRIPT" >&2
    exit 2
fi

typeset -g PASS=0
typeset -g FAIL=0

ok() {
    PASS=$((PASS + 1))
    echo "ok - $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL - $1"
    shift
    for line in "$@"; do
        echo "    $line"
    done
}

expect_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc" "expected to contain: $needle" "--- actual ---" "${(f)haystack}" "--------------"
    fi
}

expect_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc" "expected NOT to contain: $needle" "--- actual ---" "${(f)haystack}" "--------------"
    fi
}

# -----------------------------------------------------------------------
# Fixture: a throwaway git repo containing a fresh copy of the real
# scripts/test-affected.sh plus a stub .github/scripts/affected-tests.sh
# that fails unless FORCE_RUN_ALL=true is set — simulating a crash that
# only affects the diff-dependent code paths, not the forced-run-all path.
# -----------------------------------------------------------------------

FIXTURE=$(mktemp -d)
git -C "$FIXTURE" init -q -b master
git -C "$FIXTURE" config user.email "test@wxyc.org"
git -C "$FIXTURE" config user.name "WXYC CI Test"
echo "root" > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -q -m "root commit"
BASE_SHA=$(git -C "$FIXTURE" rev-parse HEAD)
git -C "$FIXTURE" update-ref refs/remotes/origin/master "$BASE_SHA"

mkdir -p "$FIXTURE/.github/scripts" "$FIXTURE/scripts"
cp "$REAL_SCRIPT" "$FIXTURE/scripts/test-affected.sh"
chmod +x "$FIXTURE/scripts/test-affected.sh"

cat > "$FIXTURE/.github/scripts/affected-tests.sh" <<'STUB'
#!/bin/zsh
# Fails to simulate a real crash in the diff-dependent code paths of
# affected-tests.sh (an unbound variable, a bad awk invocation, etc.) —
# UNLESS invoked with FORCE_RUN_ALL=true, which in the real script skips
# straight past all of that to run_all_and_exit. This mirrors the exact
# output run_all_and_exit produces today, so the assertions below catch a
# regression in the retry's targets, not just "did it retry at all".
if [[ "${FORCE_RUN_ALL:-false}" != "true" ]]; then
    echo "simulated internal crash" >&2
    exit 1
fi
spm_all="AnalyticsMacros Core Caching Analytics Playlist LikedSongs Metadata MusicShareKit Concerts WXUI"
skip="-skip-testing:WXYCUITests -skip-testing:AnalyticsMacrosTests -skip-testing:CoreTests -skip-testing:CachingTests -skip-testing:AnalyticsTests -skip-testing:PlaylistTests -skip-testing:LikedSongsTests -skip-testing:MetadataTests -skip-testing:MusicShareKitTests -skip-testing:ConcertsTests -skip-testing:WXUITests"
{
    echo "run_all=true"
    echo "skip_testing_flags=$skip"
    echo "only_testing_flags="
    echo "spm_affected=$spm_all"
    echo "xcb_required=true"
    echo "affected_summary=all tests (forced (FORCE_RUN_ALL=true))"
} >> "$GITHUB_OUTPUT"
exit 0
STUB
chmod +x "$FIXTURE/.github/scripts/affected-tests.sh"

echo "change" >> "$FIXTURE/README.md"

# =========================================================================
# Case 1: affected-tests.sh crashes in the local-diff branch. The fallback
# must still get CoreTests covered by SOMETHING.
# =========================================================================

echo "=== Case 1: affected-tests.sh crash in local-diff mode ==="
OUT=$(cd "$FIXTURE" && zsh scripts/test-affected.sh --dry-run --base-ref HEAD 2>&1)

expect_contains "crash is surfaced, not swallowed silently" "$OUT" "simulated internal crash"

# The load-bearing assertion: Core must show up in the "SPM steps:" line,
# i.e. `swift test --package-path Shared/Core` actually runs. Isolate that
# one line before asserting — "Core" as a bare substring of the whole
# output would also match "-skip-testing:CoreTests" in the printed
# xcodebuild command, which is present in BOTH the buggy and fixed
# behavior (CoreTests is always skipped in xcodebuild; that's correct only
# when Core is also in the SPM list). Before the fix, the isolated line
# reads "SPM steps:   (none)" — CoreTests is skipped by the default
# SKIP_FLAGS in the xcodebuild command AND never gets an SPM run, so it is
# covered by neither runner on exactly the path where you most want full
# coverage.
SPM_LINE=$(print -r -- "$OUT" | grep -m1 '^SPM steps:')
expect_contains "CoreTests is covered by the SPM (host swift test) runner after the crash" "$SPM_LINE" "Core"
expect_not_contains "SPM steps line does not read '(none)' after the crash" "$SPM_LINE" "(none)"

rm -rf "$FIXTURE"

# =========================================================================
# Summary
# =========================================================================

echo ""
echo "=== $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
    exit 1
fi
exit 0
