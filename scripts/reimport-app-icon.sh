#!/bin/zsh
#
# reimport-app-icon.sh
# WXYC
#
# Re-imports an Icon Composer ".icon" bundle into the committed iOS app-icon
# asset (WXYC/iOS/Assets/AppIcon.icon), re-applying the repo-specific massaging
# that turns a raw Icon Composer export into the shipped form, then commits.
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# The committed bundle deliberately diverges from the raw Icon Composer export
# in three places (introduced in commit 6a604cae):
#
#   1. The logo layer references a hand-authored vector "logo.svg" instead of
#      the exported raster "logo.png", so the wordmark stays resolution-
#      independent. logo.svg is NOT produced by Icon Composer.
#   2. The logo layer scale is doubled (LOGO_SCALE_MULTIPLIER). The vector
#      artwork is padded to roughly half the frame, so it needs ~2x the PNG's
#      scale to match the exported wordmark's visual size.
#   3. The plasma screenshot layer opacity is pinned to SCREENSHOT_OPACITY.
#
# Re-doing that by hand on every export is tedious and error-prone, so this
# script encodes it. The two numeric knobs live in the config block below.
#
# IMPORTANT: THE WORDMARK IS logo.svg, NOT logo.png
# -------------------------------------------------
# Because the repo ships logo.svg and this script never copies logo.png, any
# change you make to the *wordmark* in Icon Composer (which lives in logo.png)
# is IGNORED by a reimport. If you retouched the letters, regenerate logo.svg
# by hand instead. This script only carries over the plasma background layer,
# the icon.json parameters (fill, blend modes, shadow, etc.), and any *new*
# raster layers you add.
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
# Config — the repo-specific massaging policy. Edit these if the design shifts.
# ---------------------------------------------------------------------------
DEST_REL="WXYC/iOS/Assets/AppIcon.icon"   # committed bundle, relative to repo root
VECTOR_LOGO="logo.svg"                     # hand-authored wordmark the repo ships
RASTER_LOGO="logo.png"                     # Icon Composer export we DON'T copy
LOGO_LAYER_NAME="logo"                      # human name of the wordmark layer in icon.json
LOGO_SCALE_MULTIPLIER="2"                   # doubles the exported logo scale (SVG padding)
SCREENSHOT_OPACITY="0.75"                   # pin the plasma layer opacity; blank = keep source's
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
            sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
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
[[ -d "$SRC_ICON" ]]              || die "source is not a directory: $SRC_ICON"
[[ "$SRC_ICON" == *.icon ]]      || die "source is not a .icon bundle: $SRC_ICON"
[[ -f "$SRC_ICON/icon.json" ]]   || die "source is missing icon.json: $SRC_ICON"
[[ -d "$SRC_ICON/Assets" ]]      || die "source is missing an Assets/ directory: $SRC_ICON"

DEST_ICON="$REPO_ROOT/$DEST_REL"
[[ -d "$DEST_ICON" ]]            || die "committed bundle not found: $DEST_ICON"
[[ -f "$DEST_ICON/$VECTOR_LOGO" ]] \
    && VECTOR_LOGO_PRESENT=1 || VECTOR_LOGO_PRESENT=0

command -v rsync   >/dev/null || die "rsync is required but not on PATH"
command -v python3 >/dev/null || die "python3 is required but not on PATH"

log "repo:        $REPO_ROOT"
log "source:      $SRC_ICON"
log "destination: $DEST_REL"
(( DRY_RUN )) && log "mode:        DRY RUN (no files written, no commit)"

# Warn about the wordmark override so a logo tweak isn't silently dropped.
if [[ -f "$SRC_ICON/Assets/$RASTER_LOGO" && "$VECTOR_LOGO_PRESENT" == 1 ]]; then
    log "note: the repo ships $VECTOR_LOGO; the source's $RASTER_LOGO will NOT be copied."
    log "      if you retouched the wordmark, regenerate $VECTOR_LOGO by hand."
fi

# ---------------------------------------------------------------------------
# 1. Sync the Assets/ directory.
#    - copy the plasma screenshot and any new raster layers
#    - never copy the exported raster logo (RASTER_LOGO)
#    - protect the hand-authored vector logo (VECTOR_LOGO) from --delete
#    - drop assets the source no longer has (stale layers)
# ---------------------------------------------------------------------------
RSYNC_OPTS=(-a --delete --exclude='.DS_Store'
            --exclude="$RASTER_LOGO" --exclude="$VECTOR_LOGO")
if (( DRY_RUN )); then
    log "--- rsync plan for Assets/ ---"
    rsync -n -i "${RSYNC_OPTS[@]}" "$SRC_ICON/Assets/" "$DEST_ICON/Assets/" || true
else
    rsync "${RSYNC_OPTS[@]}" "$SRC_ICON/Assets/" "$DEST_ICON/Assets/"
    log "synced Assets/ (kept $VECTOR_LOGO, skipped $RASTER_LOGO)"
fi

# ---------------------------------------------------------------------------
# 2. Transform icon.json (structural, order-preserving, byte-compatible with
#    Icon Composer's formatting). For a dry run we write to a temp file and
#    diff; otherwise we overwrite the committed icon.json.
# ---------------------------------------------------------------------------
if (( DRY_RUN )); then
    OUT_JSON="$(mktemp -t reimport-app-icon.XXXXXX.json)"
    trap 'rm -f "$OUT_JSON"' EXIT
else
    OUT_JSON="$DEST_ICON/icon.json"
fi

SRC_JSON="$SRC_ICON/icon.json" OUT_JSON="$OUT_JSON" \
VECTOR_LOGO="$VECTOR_LOGO" RASTER_LOGO="$RASTER_LOGO" \
LOGO_LAYER_NAME="$LOGO_LAYER_NAME" LOGO_SCALE_MULTIPLIER="$LOGO_SCALE_MULTIPLIER" \
SCREENSHOT_OPACITY="$SCREENSHOT_OPACITY" \
python3 <<'PY'
import json, os

src_path = os.environ["SRC_JSON"]
out_path = os.environ["OUT_JSON"]
vector   = os.environ["VECTOR_LOGO"]
raster   = os.environ["RASTER_LOGO"]
logo_name = os.environ["LOGO_LAYER_NAME"]
scale_mult = float(os.environ["LOGO_SCALE_MULTIPLIER"])
shot_opacity = os.environ.get("SCREENSHOT_OPACITY", "").strip()

with open(src_path, encoding="utf-8") as f:
    data = json.load(f)

changes = []
swapped_logo = False

for group in data.get("groups", []):
    for layer in group.get("layers", []):
        name = layer.get("name")
        image = layer.get("image-name", "")

        # (1)+(2) the wordmark layer: swap the raster export for the vector,
        # and scale it up to compensate for the SVG's padding.
        if name == logo_name and image.lower().endswith(".png"):
            layer["image-name"] = vector
            swapped_logo = True
            changes.append(f"logo image-name: {image} -> {vector}")
            pos = layer.get("position")
            if isinstance(pos, dict) and isinstance(pos.get("scale"), (int, float)):
                old = pos["scale"]
                new = round(old * scale_mult, 5)
                if new != old:
                    pos["scale"] = new
                    changes.append(f"logo scale: {old} -> {new}")

        # (3) pin the plasma/screenshot layer opacity. It is the non-logo layer
        # that still references a raster image.
        elif shot_opacity and name != logo_name and image.lower().endswith(".png"):
            new = float(shot_opacity)
            old = layer.get("opacity")
            if old != new:
                layer["opacity"] = new
                changes.append(f"{name} opacity: {old} -> {new}")

out = json.dumps(data, indent=2, sort_keys=True,
                 separators=(",", " : "), ensure_ascii=False) + "\n"
with open(out_path, "w", encoding="utf-8") as f:
    f.write(out)

if not swapped_logo:
    print("reimport-app-icon: note: no logo.png layer found to swap "
          "(source may already ship a vector logo).")
if changes:
    print("reimport-app-icon: icon.json transforms applied:")
    for c in changes:
        print(f"  - {c}")
else:
    print("reimport-app-icon: icon.json needed no transforms.")
PY

# ---------------------------------------------------------------------------
# 3. Report (dry run) or stage + commit (real run).
# ---------------------------------------------------------------------------
if (( DRY_RUN )); then
    log "--- icon.json diff (committed -> would-be) ---"
    if diff -u "$DEST_ICON/icon.json" "$OUT_JSON"; then
        log "icon.json: no change"
    fi
    log "dry run complete; nothing was written or committed."
    exit 0
fi

git -C "$REPO_ROOT" add -- "$DEST_REL"

if git -C "$REPO_ROOT" diff --cached --quiet -- "$DEST_REL"; then
    log "no changes to commit — the committed bundle already matches the source."
    exit 0
fi

log "staged changes:"
git -C "$REPO_ROOT" status --short -- "$DEST_REL" | sed 's/^/  /'

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
git -C "$REPO_ROOT" commit --only -- "$DEST_REL" -m "$COMMIT_SUBJECT"
log "committed to '$BRANCH': $COMMIT_SUBJECT"
