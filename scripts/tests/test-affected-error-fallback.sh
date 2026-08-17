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

source "${REPO_ROOT}/scripts/tests/harness.zsh"

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
# Case 2: affected-tests.sh fails even under FORCE_RUN_ALL=true. There is no
# third fallback, so the run must fail loudly rather than proceed with an
# unknown subset of the suite.
#
# This is the riskiest behavior the retry introduces, and it is the half that
# is NOT covered by Case 1: before the fix, a crash degraded to the narrow
# static defaults and the run continued (exit 0 under --dry-run); now a
# double failure aborts. A caller relying on the old limp-along — notably the
# opt-in pre-push hook — sees a blocked push instead of a silent under-run.
# That is the intended trade (an under-run is invisible, a blocked push is
# not, and `--no-verify` / `wxyc.skipTests` are the documented escapes), but
# it is a behavior change and it deserves a pinned test rather than a
# paragraph in a commit message.
#
# Non-vacuity: against the pre-fix script this case fails on both assertions
# — the old code swallows the crash, prints a full plan, and exits 0.
# =========================================================================

echo ""
echo "=== Case 2: affected-tests.sh fails under FORCE_RUN_ALL=true too ==="

FIXTURE2=$(mktemp -d)
git -C "$FIXTURE2" init -q -b master
git -C "$FIXTURE2" config user.email "test@wxyc.org"
git -C "$FIXTURE2" config user.name "WXYC CI Test"
echo "root" > "$FIXTURE2/README.md"
git -C "$FIXTURE2" add README.md
git -C "$FIXTURE2" commit -q -m "root commit"

mkdir -p "$FIXTURE2/.github/scripts" "$FIXTURE2/scripts"
cp "$REAL_SCRIPT" "$FIXTURE2/scripts/test-affected.sh"
chmod +x "$FIXTURE2/scripts/test-affected.sh"

cat > "$FIXTURE2/.github/scripts/affected-tests.sh" <<'STUB2'
#!/bin/zsh
# Fails unconditionally, including under FORCE_RUN_ALL=true — models the
# script being missing, unreadable, or broken in run_all_and_exit itself,
# i.e. the one situation where there is nothing left to fall back to.
echo "simulated total failure" >&2
exit 1
STUB2
chmod +x "$FIXTURE2/.github/scripts/affected-tests.sh"

echo "change" >> "$FIXTURE2/README.md"

OUT2=$(cd "$FIXTURE2" && zsh scripts/test-affected.sh --dry-run --base-ref HEAD 2>&1)
RC2=$?

expect_exit "double failure exits nonzero instead of running an unknown subset" "$RC2" "1" "$OUT2"
expect_contains "the second failure is reported as terminal" "$OUT2" "no further fallback"
# If any plan were printed, the script would have proceeded past the error
# handler — which is exactly the silent under-run this fix exists to stop.
expect_not_contains "no test plan is printed after the double failure" "$OUT2" "SPM steps:"

rm -rf "$FIXTURE2"

# =========================================================================
# Summary
# =========================================================================

summarize
