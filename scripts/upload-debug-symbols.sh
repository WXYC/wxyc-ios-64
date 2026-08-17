#!/bin/zsh
#
# upload-debug-symbols.sh
#
# Uploads the dSYMs this build produced to Sentry (org wxyc, project ios).
# Run by the "Upload Debug Symbols to Sentry" build phase on the WXYC target,
# on every build, on every machine.
#
# Server-side symbolication of Release stacks rests entirely on this upload.
# Without it, Sentry has addresses and no function names, and anything that
# reasons about the symbolicated stack — grouping rules, fingerprints, the
# innermost-in-app-frame heuristics in #952 — quietly goes inert.
#
# The one design decision here is that a missed upload means different things
# in different places:
#
#   On a dev Mac, sentry-cli is optional. Somebody debugging a layout bug in
#   a Debug build should not be blocked because they never installed it, and
#   local builds are not what Sentry symbolicates anyway. Every failure path
#   is a `warning:` and the build continues.
#
#   On CI, a missed upload is the whole problem — for a build that ships. An
#   Xcode Cloud archive that skips this reaches TestFlight or the App Store
#   with no symbols on the server and nothing anywhere says so: the build is
#   green, the archive is valid, and the damage only shows up weeks later as
#   an unreadable crash. Every failure path is an `error:` and the build
#   stops. (#955)
#
#   A CI build that does not ship — a test workflow — skips the upload
#   entirely. Note that "has dSYMs" is not the discriminator: WXYC builds
#   Debug with DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an ordinary
#   simulator build fills DWARF_DSYM_FOLDER_PATH exactly like an archive
#   does. See is_shipping_build().
#
# Environment (all supplied by Xcode, except where noted):
#   DWARF_DSYM_FOLDER_PATH  the folder Xcode wrote this build's dSYMs into
#   CONFIGURATION / ACTION  Release / install for an archive; selects strictness
#   SRCROOT                 repo root; where .ci-tools/bin and .sentryclirc live
#   CI / CI_XCODE_CLOUD     set by Xcode Cloud; selects error-vs-warning
#   SENTRY_AUTH_TOKEN       optional, read by sentry-cli itself
#   SENTRY_CLI              optional explicit path to the binary (tests)
#
# Tested by scripts/tests/test-upload-debug-symbols.sh.

set -uo pipefail

readonly SENTRY_ORG_SLUG="wxyc"
readonly SENTRY_PROJECT_SLUG="ios"

# sentry-cli resolves .sentryclirc relative to the working directory, so pin
# the working directory to the repo root rather than inheriting whatever
# Xcode happened to leave it at. This is how every dev Mac authenticates.
if [[ -n "${SRCROOT:-}" && -d "${SRCROOT}" ]]; then
    cd "$SRCROOT" || exit 1
fi
readonly REPO_ROOT="${SRCROOT:-$PWD}"

# Xcode Cloud sets CI=TRUE; GitHub Actions sets CI=true. Some tools set
# CI=false to mean "not CI", which a bare emptiness test would read backwards.
is_ci() {
    [[ -n "${CI_XCODE_CLOUD:-}" ]] && return 0
    case "${${CI:-}:l}" in
        "" | false | 0 | no | off) return 1 ;;
        *) return 0 ;;
    esac
}

# Can this build reach a user? xcodebuild sets ACTION=install when archiving,
# and the shipping configuration is Release.
#
# The presence of dSYMs is NOT the test. WXYC builds Debug with
# DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an ordinary simulator build
# populates DWARF_DSYM_FOLDER_PATH exactly like an archive — meaning a
# strict-whenever-dSYMs-exist rule would demand a Sentry token from every
# Xcode Cloud test workflow and fail the ones that don't have one.
#
# Neither setting present is treated as shipping. A spurious CI failure is
# loud and gets fixed in an afternoon; a skipped upload is silent and is the
# whole reason this script exists.
is_shipping_build() {
    [[ "${ACTION:-}" == "install" ]] && return 0
    [[ -z "${CONFIGURATION:-}" ]] && return 0
    [[ "${CONFIGURATION}" != "Debug" ]] && return 0
    return 1
}

# Where the binary might be, in order of specificity: an explicit override,
# the copy ci_scripts/install-sentry-cli.sh vendors into the checkout (Xcode
# Cloud runners ship no sentry-cli and have no writable PATH entry we can
# count on), then whatever a developer installed system-wide.
resolve_sentry_cli() {
    if [[ -n "${SENTRY_CLI:-}" && -x "${SENTRY_CLI}" ]]; then
        print -r -- "${SENTRY_CLI}"
        return 0
    fi

    local vendored="${REPO_ROOT}/.ci-tools/bin/sentry-cli"
    if [[ -x "$vendored" ]]; then
        print -r -- "$vendored"
        return 0
    fi

    local on_path
    if on_path=$(command -v sentry-cli 2>/dev/null) && [[ -n "$on_path" ]]; then
        print -r -- "$on_path"
        return 0
    fi

    return 1
}

# sentry-cli takes credentials from SENTRY_AUTH_TOKEN or from a .sentryclirc
# in the working directory or the home directory. Checking first only buys a
# better diagnostic than the CLI's own — but "no token" and "token rejected"
# have completely different fixes, and the build log is where that gets read.
has_credentials() {
    [[ -n "${SENTRY_AUTH_TOKEN:-}" ]] && return 0
    [[ -f "${REPO_ROOT}/.sentryclirc" ]] && return 0
    [[ -n "${HOME:-}" && -f "${HOME}/.sentryclirc" ]] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# 1. Did this build produce anything to upload?
# ---------------------------------------------------------------------------

dsym_folder="${DWARF_DSYM_FOLDER_PATH:-}"

if [[ -z "$dsym_folder" || ! -d "$dsym_folder" ]]; then
    echo "note: no dSYM folder for this build; skipping Sentry debug-symbol upload"
    exit 0
fi

dsym_bundles=("$dsym_folder"/*.dSYM(N))
if (( ${#dsym_bundles} == 0 )); then
    echo "note: no dSYMs in ${dsym_folder}; skipping Sentry debug-symbol upload"
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Is this a build whose symbols anyone will need?
#
# A CI runner's Debug build reports no events to Sentry, so uploading its
# dSYMs only pads the debug-file list. Skip outright rather than upload-and-
# ignore-failures, which would put a network call on the critical path of
# every test workflow. Locally the upload still runs on every build: a
# developer's simulator crashes do reach Sentry and are worth symbolicating.
# ---------------------------------------------------------------------------

if is_ci && ! is_shipping_build; then
    echo "note: ${CONFIGURATION:-unknown}/${ACTION:-unknown} build on CI does not ship; skipping Sentry debug-symbol upload"
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Is there a binary to run?
# ---------------------------------------------------------------------------

if ! sentry_cli=$(resolve_sentry_cli); then
    if is_ci; then
        echo "error: sentry-cli is not installed on this runner, so this build's dSYMs cannot reach Sentry and its Release events would arrive unsymbolicated. ci_scripts/install-sentry-cli.sh installs it during ci_post_clone — check that it ran and succeeded."
        exit 1
    fi
    echo "warning: sentry-cli not installed, skipping debug symbol upload"
    exit 0
fi

# ---------------------------------------------------------------------------
# 4. Is there anything to authenticate with?
# ---------------------------------------------------------------------------

if ! has_credentials; then
    if is_ci; then
        echo "error: no Sentry credentials available (neither SENTRY_AUTH_TOKEN nor a .sentryclirc), so this build's dSYMs cannot reach Sentry. Set SENTRY_AUTH_TOKEN as a secret environment variable on the Xcode Cloud workflow; see docs/configuration.md."
        exit 1
    fi
    echo "warning: no Sentry credentials (SENTRY_AUTH_TOKEN or .sentryclirc), skipping debug symbol upload"
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Upload.
# ---------------------------------------------------------------------------

export SENTRY_ORG="$SENTRY_ORG_SLUG"
export SENTRY_PROJECT="$SENTRY_PROJECT_SLUG"

# Split the streams: sentry-cli's stdout (what it uploaded, which debug IDs)
# belongs in the build log unconditionally, while its stderr is captured so
# the failure message can ride on the `error:`/`warning:` line itself — Xcode's
# issue navigator shows that one line and nothing around it, and "upload
# failed, see above" is exactly the kind of diagnostic that gets ignored.
# The fd 3 dance is what makes stdout escape the command substitution.
{
    upload_error=$("$sentry_cli" debug-files upload --include-sources "$dsym_folder" 2>&1 >&3 3>&-)
    upload_status=$?
} 3>&1

if (( upload_status != 0 )); then
    # Collapse to one line: a multi-line diagnostic only prefixes its first
    # line, so everything after the newline would lose the error: marker.
    summary="${upload_error//$'\n'/ }"
    if is_ci; then
        echo "error: sentry-cli - ${summary}"
        exit 1
    fi
    echo "warning: sentry-cli - ${summary}"
    exit 0
fi

# No count here: sentry-cli walks the whole folder and uploads every debug
# file it recognizes, not just the .dSYM bundles this script counted to decide
# whether to run at all. Its own output above is the accurate inventory.
echo "note: uploaded debug symbols to Sentry (${SENTRY_ORG_SLUG}/${SENTRY_PROJECT_SLUG})"
exit 0
