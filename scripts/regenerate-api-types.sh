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
# Reads the pin from Shared/WXYCAPIModels/contract-version.json, whose three
# fields are deliberately NOT equal in status:
#
#   wxycSharedSha     Authoritative. The exact commit the vendored tree is
#                     generated from, and the only field that decides anything.
#   apiYamlVersion    Checked, not authoritative. Asserted below to equal
#                     info.version in api.yaml at that commit, so the label a
#                     reader consults cannot drift away from the sha that
#                     decides (#923).
#   wxycSharedTag     Advisory. Names where the commit lives (a release tag, or
#                     "main" for a pin ahead of any release) purely for
#                     legibility, and is not read by this script at all.
#
# The asymmetry between the last two is principled rather than leftover:
# api.yaml's version is a property of the pinned COMMIT'S CONTENT, so it can be
# checked from the pin alone and any disagreement is our bug. A tag is a
# mutable ref -- what it points at is a property of upstream's ref state at the
# moment you look, not of what was vendored -- so checking it would let an
# upstream retag turn this repo's verified-green tree red for a reason that has
# nothing to do with drift here. It stays a label, and stays unchecked, on
# purpose. (`.github/workflows/spec-drift.yml` reads the sha for the same
# reason.)
#
# To vendor a newer wxyc-shared contract, update `wxycSharedSha` and
# `apiYamlVersion` together (and `wxycSharedTag` for legibility), then run this
# script and commit the diff. A sha/version mismatch fails immediately after
# the checkout -- before `npm ci` and the JVM codegen, which are the expensive
# part -- rather than producing a correctly-generated tree under a wrong label.
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

# Pass the manifest path as argv (not string-interpolated into the JS source),
# so a repo path containing a quote or backslash can't corrupt the program.
SHA=$(node -e 'process.stdout.write(require(process.argv[1]).wxycSharedSha || "")' "$REPO_ROOT/$CONTRACT_FILE")
[[ -n "$SHA" ]] || fail "wxycSharedSha missing or empty in $CONTRACT_FILE"

DECLARED_API_VERSION=$(node -e 'process.stdout.write(require(process.argv[1]).apiYamlVersion || "")' "$REPO_ROOT/$CONTRACT_FILE")
[[ -n "$DECLARED_API_VERSION" ]] || fail "apiYamlVersion missing or empty in $CONTRACT_FILE -- it is checked against the pinned commit's api.yaml below, so it can no longer be omitted"

log "Pinned wxyc-shared commit: $SHA"
log "Declared api.yaml version: $DECLARED_API_VERSION"
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
# Assert the recorded label describes the commit actually pinned
# ---------------------------------------------------------------------------
#
# `wxycSharedSha` decides what gets generated; `apiYamlVersion` is what a
# reader consults to answer "what shape did I generate against". Until #923
# only the first was machine-read, so the second could drift into a lie -- and
# did: #919 advanced the pin while the label sat at 1.35.0 on both sides,
# because upstream had stopped moving `info.version`. That upstream half is
# fixed (WXYC/wxyc-shared#347 fails any api.yaml content change that doesn't
# bump the version), which is what makes the label worth checking at all: from
# 1.36.0 on, two different contents cannot share a version string.
#
# Read the version exactly the way wxyc-shared's own gate does
# (scripts/check-version-bump.sh) rather than with a YAML parser -- this
# script's dependency set is git/npm/node/java/rsync and should stay that way.
# `|| true` because a missing line would otherwise abort the pipeline under
# `set -o pipefail` before the empty check below can name the real problem.
API_YAML="$WORK_DIR/api.yaml"
[[ -f "$API_YAML" ]] || fail "api.yaml not found at the pinned commit $SHA -- is $REMOTE really wxyc-shared?"

PINNED_API_VERSION=$(grep -m1 '^  version:' "$API_YAML" | awk '{print $2}' || true)
[[ -n "$PINNED_API_VERSION" ]] || fail "could not read info.version from api.yaml at $SHA (expected a line matching '^  version:')"

if [[ "$PINNED_API_VERSION" != "$DECLARED_API_VERSION" ]]; then
    fail "contract-version.json is out of sync with the commit it pins.
    $CONTRACT_FILE says apiYamlVersion: $DECLARED_API_VERSION
    api.yaml at $SHA says info.version: $PINNED_API_VERSION
  Fix whichever is wrong: set apiYamlVersion to $PINNED_API_VERSION if the sha is the intended pin, or move wxycSharedSha (and wxycSharedTag) to the commit that actually shipped $DECLARED_API_VERSION."
fi

log "Contract label matches the pinned commit (api.yaml info.version: $PINNED_API_VERSION)"

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
