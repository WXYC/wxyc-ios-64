#!/bin/zsh
#
# regenerate-api-types.sh
# WXYC
#
# Regenerates Shared/WXYCAPIModels/Sources/WXYCAPIModels from wxyc-shared's
# OpenAPI spec (api.yaml). Clones wxyc-shared at the commit pinned in
# Shared/WXYCAPIModels/contract-version.json into a gitignored scratch dir,
# runs its `generate:swift` codegen target (the swift6 generator added in
# wxyc-shared#250), then rsyncs the generated Models/ and Infrastructure/
# directories over the vendored package. Infrastructure/ is required even
# though only Models/ is "the point" -- generated models depend on
# Infrastructure support types (JSONValue, CaseIterableDefaultsLast,
# NumericRule, CodableHelper, date formatting). APIs/ (the endpoint clients)
# is intentionally dropped -- this package is models-only.
#
# Usage:
#   scripts/regenerate-api-types.sh [options]
#
# Options:
#   --work-dir <path>   Scratch clone location. Default: .build/wxyc-shared-codegen.
#   --remote <url>      wxyc-shared remote to clone. Default: git@github.com:WXYC/wxyc-shared.git.
#   --dest-dir <path>   Where to rsync Models/ + Infrastructure/ into. Default:
#                       Shared/WXYCAPIModels/Sources/WXYCAPIModels (the committed
#                       tree). scripts/verify-api-types.sh overrides this to a
#                       scratch dir so it never touches the committed tree.
#   --keep-work-dir     Don't delete the scratch clone when done (skips a full
#                       re-clone on the next run -- useful for iterating).
#   -h, --help          Show this message.
#
# Reads the pinned commit from Shared/WXYCAPIModels/contract-version.json's
# `wxycSharedSha` field. To vendor a newer wxyc-shared contract, update that
# file's `wxycSharedTag` / `wxycSharedSha` / `apiYamlVersion` first, then run
# this script and commit the diff.
#
# Requires: git, npm (+ node), java (openapi-generator-cli runs on the JVM),
# rsync.
#

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
cd "$REPO_ROOT"

PACKAGE_DIR="Shared/WXYCAPIModels"
CONTRACT_FILE="$PACKAGE_DIR/contract-version.json"
DEST_DIR="$PACKAGE_DIR/Sources/WXYCAPIModels"
WORK_DIR=".build/wxyc-shared-codegen"
REMOTE="git@github.com:WXYC/wxyc-shared.git"
KEEP_WORK_DIR=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log()  { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { print -ru2 -- "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"; exit 1; }

usage() {
    cat <<'EOF'
regenerate-api-types.sh

Regenerates Shared/WXYCAPIModels/Sources/WXYCAPIModels from the wxyc-shared
commit pinned in Shared/WXYCAPIModels/contract-version.json.

Usage:
  scripts/regenerate-api-types.sh [options]

Options:
  --work-dir <path>   Scratch clone location. Default: .build/wxyc-shared-codegen.
  --remote <url>      wxyc-shared remote to clone. Default: git@github.com:WXYC/wxyc-shared.git.
  --dest-dir <path>   Sync destination. Default: Shared/WXYCAPIModels/Sources/WXYCAPIModels.
  --keep-work-dir     Don't delete the scratch clone when done.
  -h, --help          Show this message.
EOF
}

require_value() {
    local flag="$1"
    local remaining="$2"
    if (( remaining < 2 )); then
        fail "option $flag requires a value"
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --work-dir)       require_value "$1" "$#"; WORK_DIR="$2"; shift 2 ;;
        --remote)         require_value "$1" "$#"; REMOTE="$2"; shift 2 ;;
        --dest-dir)       require_value "$1" "$#"; DEST_DIR="$2"; shift 2 ;;
        --keep-work-dir)  KEEP_WORK_DIR=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

for tool in git npm node java rsync; do
    command -v "$tool" > /dev/null 2>&1 || fail "'$tool' is required but not found on PATH"
done

[[ -f "$CONTRACT_FILE" ]] || fail "contract manifest not found: $CONTRACT_FILE"

SHA=$(node -e "process.stdout.write(require('$REPO_ROOT/$CONTRACT_FILE').wxycSharedSha || '')")
[[ -n "$SHA" ]] || fail "wxycSharedSha missing or empty in $CONTRACT_FILE"

log "Pinned wxyc-shared commit: $SHA"
log "Remote: $REMOTE"
log "Work dir: $WORK_DIR"

# ---------------------------------------------------------------------------
# Clone (or reuse) wxyc-shared at the pinned commit
# ---------------------------------------------------------------------------

if [[ -d "$WORK_DIR/.git" ]]; then
    log "Reusing existing clone at $WORK_DIR"
    git -C "$WORK_DIR" fetch --quiet origin || fail "fetch in $WORK_DIR failed"
else
    log "Cloning $REMOTE into $WORK_DIR"
    rm -rf "$WORK_DIR"
    mkdir -p "${WORK_DIR:h}"
    git clone --quiet "$REMOTE" "$WORK_DIR" || fail "clone of $REMOTE failed"
fi

log "Checking out $SHA"
git -C "$WORK_DIR" checkout --quiet "$SHA" || fail "checkout of $SHA in $WORK_DIR failed -- does the commit exist on $REMOTE?"

# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------

log "Installing wxyc-shared dependencies (npm ci)"
(cd "$WORK_DIR" && npm ci --silent) || fail "npm ci failed in $WORK_DIR"

log "Running npm run generate:swift"
(cd "$WORK_DIR" && npm run generate:swift) || fail "npm run generate:swift failed in $WORK_DIR"

GENERATED_ROOT="$WORK_DIR/generated/swift/Sources/WXYCAPI"
[[ -d "$GENERATED_ROOT/Models" ]] || fail "generated Models/ not found at $GENERATED_ROOT -- did the generator's SPM file layout change?"
[[ -d "$GENERATED_ROOT/Infrastructure" ]] || fail "generated Infrastructure/ not found at $GENERATED_ROOT"

# ---------------------------------------------------------------------------
# Sync into the vendored package (Models/ + Infrastructure/ only -- no APIs/)
# ---------------------------------------------------------------------------

log "Syncing Models/ and Infrastructure/ into $DEST_DIR (APIs/ intentionally excluded)"
mkdir -p "$DEST_DIR/Models" "$DEST_DIR/Infrastructure"
rsync -a --delete "$GENERATED_ROOT/Models/" "$DEST_DIR/Models/" || fail "rsync of Models/ failed"
rsync -a --delete "$GENERATED_ROOT/Infrastructure/" "$DEST_DIR/Infrastructure/" || fail "rsync of Infrastructure/ failed"

if (( KEEP_WORK_DIR == 0 )); then
    log "Cleaning up $WORK_DIR"
    rm -rf "$WORK_DIR"
else
    log "Leaving scratch clone in place at $WORK_DIR (--keep-work-dir)"
fi

FILE_COUNT=$(find "$DEST_DIR" -name '*.swift' | wc -l | tr -d ' ')
log "Done. $FILE_COUNT Swift files vendored into $DEST_DIR"
