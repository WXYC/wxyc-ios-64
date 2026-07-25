#!/bin/zsh
#
# reimport-app-icon.sh
# WXYC
#
# Re-imports an Icon Composer ".icon" bundle into the committed iOS app-icon
# asset (WXYC/iOS/Assets/AppIcon.icon) verbatim, then commits.
#
# WHAT THIS SCRIPT DOES
# ---------------------
# It is a faithful passthrough. Whatever the source .icon bundle contains — the
# icon.json parameters and every asset (the vector logo.svg wordmark, the plasma
# background PNG, any layer you add) — is mirrored into the committed bundle
# exactly as authored. The script applies NO massaging: no image swaps, no scale
# or opacity overrides. Icon Composer is the source of truth; this script just
# carries the bundle into the repo and makes a clean, scoped commit.
#
# The wordmark is already a hand-authored vector (logo.svg) inside the bundle,
# so it stays resolution-independent with no special handling. The only raster
# is the plasma background, which is a rendered image and cannot be a vector.
#
# Usage:
#   scripts/reimport-app-icon.sh <path-to-AppIcon.icon> [commit-subject]
#   scripts/reimport-app-icon.sh --dry-run <path-to-AppIcon.icon>
#
# Examples:
#   scripts/reimport-app-icon.sh "~/Pictures/.../iOS/AppIcon.icon"
#   scripts/reimport-app-icon.sh --dry-run "~/Pictures/.../iOS/AppIcon.icon"
#
# Exit codes:
#   0  success (committed, or nothing to commit, or dry-run completed)
#   1  usage / validation error
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Config.
# ---------------------------------------------------------------------------
DEST_REL="WXYC/iOS/Assets/AppIcon.icon"   # committed bundle, relative to repo root
DEFAULT_COMMIT_SUBJECT="chore(app-icon): reimport the iOS AppIcon from Icon Composer"

# ---------------------------------------------------------------------------
# Locate the repo (this script lives in <repo>/scripts/).
# ---------------------------------------------------------------------------
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { print -r -- "reimport-app-icon: $*"; }
die()  { print -r -- "reimport-app-icon: error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse arguments.
# ---------------------------------------------------------------------------
DRY_RUN=0
SRC_ICON=""
COMMIT_SUBJECT=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            if [[ -z "$SRC_ICON" ]]; then
                SRC_ICON="$arg"
            elif [[ -z "$COMMIT_SUBJECT" ]]; then
                COMMIT_SUBJECT="$arg"
            else
                die "unexpected extra argument: $arg"
            fi
            ;;
    esac
done

[[ -n "$SRC_ICON" ]] || die "missing path to the source .icon bundle (see --help)"
[[ -n "$COMMIT_SUBJECT" ]] || COMMIT_SUBJECT="$DEFAULT_COMMIT_SUBJECT"

# Expand a leading ~ that arrived quoted.
SRC_ICON="${SRC_ICON/#\~/$HOME}"

# ---------------------------------------------------------------------------
# Validate the source and destination bundles.
# ---------------------------------------------------------------------------
[[ -d "$SRC_ICON" ]]             || die "source is not a directory: $SRC_ICON"
[[ "$SRC_ICON" == *.icon ]]      || die "source is not a .icon bundle: $SRC_ICON"
[[ -f "$SRC_ICON/icon.json" ]]   || die "source is missing icon.json: $SRC_ICON"
[[ -d "$SRC_ICON/Assets" ]]      || die "source is missing an Assets/ directory: $SRC_ICON"

DEST_ICON="$REPO_ROOT/$DEST_REL"
[[ -d "$DEST_ICON" ]]            || die "committed bundle not found: $DEST_ICON"

command -v rsync >/dev/null || die "rsync is required but not on PATH"

log "repo:        $REPO_ROOT"
log "source:      $SRC_ICON"
log "destination: $DEST_REL"
(( DRY_RUN )) && log "mode:        DRY RUN (no files written, no commit)"

# ---------------------------------------------------------------------------
# 1. Mirror the Assets/ directory verbatim (drop stale layers via --delete).
# ---------------------------------------------------------------------------
RSYNC_OPTS=(-a --delete --exclude='.DS_Store')
if (( DRY_RUN )); then
    log "--- rsync plan for Assets/ ---"
    rsync -n -i "${RSYNC_OPTS[@]}" "$SRC_ICON/Assets/" "$DEST_ICON/Assets/" || true
else
    rsync "${RSYNC_OPTS[@]}" "$SRC_ICON/Assets/" "$DEST_ICON/Assets/"
    log "mirrored Assets/ verbatim"
fi

# ---------------------------------------------------------------------------
# 2. Copy icon.json verbatim.
# ---------------------------------------------------------------------------
if (( DRY_RUN )); then
    log "--- icon.json diff (committed -> source) ---"
    if diff -u "$DEST_ICON/icon.json" "$SRC_ICON/icon.json"; then
        log "icon.json: no change"
    fi
    log "dry run complete; nothing was written or committed."
    exit 0
fi

cp "$SRC_ICON/icon.json" "$DEST_ICON/icon.json"

# ---------------------------------------------------------------------------
# 3. Stage + commit only the icon bundle.
# ---------------------------------------------------------------------------
git -C "$REPO_ROOT" add -- "$DEST_REL"

if git -C "$REPO_ROOT" diff --cached --quiet -- "$DEST_REL"; then
    log "no changes to commit — the committed bundle already matches the source."
    exit 0
fi

log "staged changes:"
git -C "$REPO_ROOT" status --short -- "$DEST_REL" | sed 's/^/  /'

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
git -C "$REPO_ROOT" commit --only -m "$COMMIT_SUBJECT" -- "$DEST_REL"
log "committed to '$BRANCH': $COMMIT_SUBJECT"
