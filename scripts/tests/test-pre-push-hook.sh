#!/bin/zsh
#
# test-pre-push-hook.sh
#
# Black-box regression tests for scripts/hooks/pre-push. Feeds the real hook
# script realistic stdin in git's actual pre-push protocol format
# ("<local-ref> <local-sha> <remote-ref> <remote-sha>", one line per ref)
# inside an isolated temp git repo, and asserts on which --base-ref (if any)
# it forwards to scripts/test-affected.sh.
#
# The temp repo's own scripts/test-affected.sh is a stub that records its
# argv instead of actually running the test plan — the hook resolves
# $REPO_ROOT via `git rev-parse --show-toplevel` from CWD, so pointing CWD at
# the temp repo is enough to redirect it there without touching the real
# scripts/test-affected.sh.
#
# Run directly:
#   zsh scripts/tests/test-pre-push-hook.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
HOOK="${REPO_ROOT}/scripts/hooks/pre-push"

if [[ ! -f "$HOOK" ]]; then
    echo "Cannot find pre-push hook at $HOOK" >&2
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

expect_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$desc"
    else
        fail "$desc" "expected: $expected" "actual:   $actual"
    fi
}

ZERO_SHA="0000000000000000000000000000000000000000"

# -------------------------------------------------------------------------
# Fixture: an isolated temp git repo with a stub scripts/test-affected.sh
# that records its argv (one arg per line) to $ARGV_FILE and exits 0
# without doing anything real.
# -------------------------------------------------------------------------

TMP_REPO=$(mktemp -d)
git -C "$TMP_REPO" init -q -b master
git -C "$TMP_REPO" config user.email "test@wxyc.org"
git -C "$TMP_REPO" config user.name "WXYC CI Test"
echo "root" > "$TMP_REPO/README.md"
git -C "$TMP_REPO" add README.md
git -C "$TMP_REPO" commit -q -m "root commit"
MASTER_SHA=$(git -C "$TMP_REPO" rev-parse HEAD)

mkdir -p "$TMP_REPO/scripts/hooks"
ARGV_FILE="$TMP_REPO/argv.log"
CALLED_FILE="$TMP_REPO/called.log"
cat > "$TMP_REPO/scripts/test-affected.sh" <<STUB
#!/bin/zsh
echo "called" > "$CALLED_FILE"
: > "$ARGV_FILE"
for a in "\$@"; do
    echo "\$a" >> "$ARGV_FILE"
done
exit 0
STUB
chmod +x "$TMP_REPO/scripts/test-affected.sh"

# A second local commit so there's a "current branch tip" distinct from
# MASTER_SHA to push, and a fake origin/master remote-tracking ref so
# `git merge-base` / `@{u}` have something real to resolve against without
# needing an actual network remote.
echo "change" >> "$TMP_REPO/README.md"
git -C "$TMP_REPO" add README.md
git -C "$TMP_REPO" commit -q -m "local change"
LOCAL_TIP_SHA=$(git -C "$TMP_REPO" rev-parse HEAD)

mkdir -p "$TMP_REPO/.git/refs/remotes/origin"
git -C "$TMP_REPO" update-ref refs/remotes/origin/master "$MASTER_SHA"
git -C "$TMP_REPO" remote add origin "$TMP_REPO/.git" 2>/dev/null || true

run_hook() {
    local stdin_data="$1"
    shift
    local extra_config="${1:-}"
    (
        cd "$TMP_REPO" || exit 99
        if [[ -n "$extra_config" ]]; then
            eval "$extra_config"
        fi
        printf '%s' "$stdin_data" | zsh "$HOOK" origin "$TMP_REPO/.git"
    )
    LAST_EXIT=$?
}

reset_logs() {
    rm -f "$ARGV_FILE" "$CALLED_FILE"
}

read_argv() {
    if [[ -f "$ARGV_FILE" ]]; then
        cat "$ARGV_FILE"
    else
        echo ""
    fi
}

# =========================================================================
# Case 1: normal update (existing branch, real remote_sha) — BASE_REF should
# be derived from remote_sha, not left as test-affected.sh's own default.
# =========================================================================

echo "=== Case 1: normal update push ==="
reset_logs
run_hook "refs/heads/master $LOCAL_TIP_SHA refs/heads/master $MASTER_SHA
"
ARGV=$(read_argv)
expect_contains "normal update: test-affected.sh was invoked" "$(cat "$CALLED_FILE" 2>/dev/null || echo '')" "called"
expect_contains "normal update: --base-ref flag is present" "$ARGV" "--base-ref"
expect_contains "normal update: base-ref value is the remote sha" "$ARGV" "$MASTER_SHA"

# =========================================================================
# Case 2: new branch push, remote_sha all zeros, no upstream configured —
# should fall back to test-affected.sh's own default (no --base-ref flag).
# =========================================================================

echo ""
echo "=== Case 2: new branch, no upstream configured ==="
reset_logs
run_hook "refs/heads/brand-new-branch $LOCAL_TIP_SHA refs/heads/brand-new-branch $ZERO_SHA
"
ARGV=$(read_argv)
expect_contains "new branch (no upstream): test-affected.sh was invoked" "$(cat "$CALLED_FILE" 2>/dev/null || echo '')" "called"
expect_not_contains "new branch (no upstream): no --base-ref flag (defers to test-affected.sh's default)" "$ARGV" "--base-ref"

# =========================================================================
# Case 3: new branch push, remote_sha all zeros, WITH an upstream configured
# — should derive BASE_REF from @{u}.
# =========================================================================

echo ""
echo "=== Case 3: new branch, upstream configured ==="
reset_logs
run_hook "refs/heads/tracked-branch $LOCAL_TIP_SHA refs/heads/tracked-branch $ZERO_SHA
" "git config branch.master.remote origin; git config branch.master.merge refs/heads/master"
ARGV=$(read_argv)
expect_contains "new branch (with upstream): --base-ref flag is present" "$ARGV" "--base-ref"
expect_contains "new branch (with upstream): base-ref value is the upstream" "$ARGV" "origin/master"

# =========================================================================
# Case 4: delete push (local_sha all zeros) — nothing to validate, hook
# should skip calling test-affected.sh entirely.
# =========================================================================

echo ""
echo "=== Case 4: delete push ==="
reset_logs
run_hook "refs/heads/doomed-branch $ZERO_SHA refs/heads/doomed-branch $MASTER_SHA
"
expect_eq "delete push: test-affected.sh was never invoked" "$([[ -f "$CALLED_FILE" ]] && echo called || echo not-called)" "not-called"
expect_eq "delete push: hook exits 0" "$LAST_EXIT" "0"

# =========================================================================
# Case 5: multiple ref lines — a delete followed by a real update. The
# real update's remote_sha should be used, the delete line skipped.
# =========================================================================

echo ""
echo "=== Case 5: multiple refs (delete + real update) ==="
reset_logs
run_hook "refs/heads/doomed-branch $ZERO_SHA refs/heads/doomed-branch $MASTER_SHA
refs/heads/master $LOCAL_TIP_SHA refs/heads/master $MASTER_SHA
"
ARGV=$(read_argv)
expect_contains "multi-ref: test-affected.sh was invoked" "$(cat "$CALLED_FILE" 2>/dev/null || echo '')" "called"
expect_contains "multi-ref: --base-ref flag is present" "$ARGV" "--base-ref"
expect_contains "multi-ref: base-ref value comes from the second (non-delete) line" "$ARGV" "$MASTER_SHA"

# =========================================================================
# Case 6: wxyc.skipTests=true — hook should exit before reading stdin at
# all, regardless of what's on it.
# =========================================================================

echo ""
echo "=== Case 6: wxyc.skipTests=true ==="
reset_logs
run_hook "refs/heads/master $LOCAL_TIP_SHA refs/heads/master $MASTER_SHA
" "git config wxyc.skipTests true"
expect_eq "skipTests=true: test-affected.sh was never invoked" "$([[ -f "$CALLED_FILE" ]] && echo called || echo not-called)" "not-called"
expect_eq "skipTests=true: hook exits 0" "$LAST_EXIT" "0"
git -C "$TMP_REPO" config --unset wxyc.skipTests 2>/dev/null || true

rm -rf "$TMP_REPO"

# =========================================================================
# Summary
# =========================================================================

echo ""
echo "=== $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
    exit 1
fi
exit 0
