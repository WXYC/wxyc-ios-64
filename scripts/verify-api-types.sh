#!/bin/zsh
#
# verify-api-types.sh
# WXYC
#
# Verifies that the committed Shared/WXYCAPIModels/Sources/WXYCAPIModels tree
# matches what scripts/regenerate-api-types.sh produces from the wxyc-shared
# commit pinned in Shared/WXYCAPIModels/contract-version.json. Regenerates
# into a scratch temp directory -- the committed tree is never touched -- and
# diffs it against the committed tree with `git diff --no-index --exit-code`,
# so it fails loudly on drift: a hand-edit to a generated file, a
# contract-version.json bump that wasn't followed by a regen, or an
# api.yaml change upstream that never made it into this repo.
#
# Usage:
#   scripts/verify-api-types.sh [options]
#
# Options:
#   --remote <url>   wxyc-shared remote to clone. Forwarded to regenerate-api-types.sh.
#   -h, --help       Show this message.
#
# Exit codes: 0 = committed tree matches the pinned contract. Non-zero = drift
# detected (diff printed to stdout) or the regeneration itself failed.
#

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
cd "$REPO_ROOT"

COMMITTED_DIR="Shared/WXYCAPIModels/Sources/WXYCAPIModels"
REMOTE=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log()  { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { print -ru2 -- "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"; exit 1; }

usage() {
    cat <<'EOF'
verify-api-types.sh

Regenerates Shared/WXYCAPIModels into a scratch temp dir (never touching the
committed tree) and diffs it against Shared/WXYCAPIModels/Sources/WXYCAPIModels.
Exits non-zero, with the diff on stdout, if they differ.

Usage:
  scripts/verify-api-types.sh [options]

Options:
  --remote <url>   wxyc-shared remote to clone. Forwarded to regenerate-api-types.sh.
  -h, --help       Show this message.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --remote)
            if (( $# < 2 )); then
                fail "option --remote requires a value"
            fi
            REMOTE="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -d "$COMMITTED_DIR" ]] || fail "committed tree not found: $COMMITTED_DIR"
[[ -x "$SCRIPT_DIR/regenerate-api-types.sh" ]] || fail "$SCRIPT_DIR/regenerate-api-types.sh not found or not executable"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wxyc-api-types-verify.XXXXXX") || fail "mktemp failed"
trap 'rm -rf "$TMP_ROOT"' EXIT

TMP_DEST="$TMP_ROOT/WXYCAPIModels"
mkdir -p "$TMP_DEST"

log "Regenerating into scratch dir: $TMP_DEST"
regen_args=(--dest-dir "$TMP_DEST" --work-dir "$TMP_ROOT/wxyc-shared-codegen")
if [[ -n "$REMOTE" ]]; then
    regen_args+=(--remote "$REMOTE")
fi
"$SCRIPT_DIR/regenerate-api-types.sh" "${regen_args[@]}" || fail "regeneration into scratch dir failed"

log "Diffing scratch output against $COMMITTED_DIR"
set +e
git diff --no-index --exit-code -- "$COMMITTED_DIR" "$TMP_DEST"
diff_status=$?
set -e

if (( diff_status == 0 )); then
    log "No drift. Committed tree matches the pinned wxyc-shared contract."
    exit 0
elif (( diff_status == 1 )); then
    fail "Drift detected -- committed $COMMITTED_DIR does not match a fresh regen from the pinned contract. Run scripts/regenerate-api-types.sh and commit the diff, or update Shared/WXYCAPIModels/contract-version.json if the pin should move."
else
    fail "git diff failed unexpectedly (exit $diff_status) while comparing $COMMITTED_DIR to $TMP_DEST"
fi
