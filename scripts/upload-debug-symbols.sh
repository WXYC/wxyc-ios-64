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
# for different builds:
#
#   On an everyday build, sentry-cli is optional. Somebody debugging a layout
#   bug should not be blocked because they never installed it, and that build
#   is not what anyone will be reading a crash from. Every failure path is a
#   `warning:` and the build continues.
#
#   On a build that ships, a missed upload is the whole problem. An archive
#   that skips this reaches TestFlight or the App Store with no symbols on the
#   server and nothing anywhere says so: the build is green, the archive is
#   valid, and the damage only shows up weeks later as an unreadable crash.
#   Every failure path is an `error:` and the build stops. (#955)
#
#   A CI build that does not ship — a test workflow — skips the upload
#   entirely. See is_shipping_build() for what "ship" means and why the
#   presence of dSYMs cannot answer it.
#
# What separates the two is the archive, not the runner: WXYC ships from
# Product > Archive on a dev Mac, so a rule that only ever tightened on CI
# would leave the one build that reaches users taking the lenient path. See
# is_strict().
#
# Environment (all supplied by Xcode, except where noted):
#   DWARF_DSYM_FOLDER_PATH  the folder Xcode wrote this build's dSYMs into
#   ACTION                  install for an archive; the main strictness input
#   CONFIGURATION           Release, Debug TestFlight, ...; strictness on CI
#   SRCROOT                 repo root; where .ci-tools and .sentryclirc live
#   CI                      set by Xcode Cloud; widens strictness, see is_ci()
#   SENTRY_AUTH_TOKEN       optional, read by sentry-cli itself
#
# Plus one file, not an environment variable: $SRCROOT/.ci-tools/ci-runner,
# written by ci_post_clone.sh. See is_ci().
#
# Tested by scripts/tests/test-upload-debug-symbols.sh.

set -uo pipefail

export SENTRY_ORG="wxyc"
export SENTRY_PROJECT="ios"

# sentry-cli resolves .sentryclirc relative to the working directory, so pin
# the working directory to the repo root rather than inheriting whatever
# Xcode happened to leave it at. This is how every dev Mac authenticates.
if [[ -d "${SRCROOT:-}" ]]; then
    cd "$SRCROOT" || exit 1
fi
readonly REPO_ROOT="$PWD"

# Am I on a build runner? The marker file first — see install-sentry-cli.sh on
# why a file in the checkout beats an environment variable for anything a
# nested build phase has to read. Everything strict below hangs off this
# answer, so if $CI failed to make that hop every error: would quietly become a
# warning: and #955 would be back with a passing test suite.
#
# Then the environment. Xcode Cloud sets CI=TRUE, GitHub Actions sets CI=true,
# and some tools set CI=false to mean "not CI" — which a bare emptiness test
# would read backwards.
is_ci() {
    [[ -f "${REPO_ROOT}/.ci-tools/ci-runner" ]] && return 0
    case "${${CI:-}:l}" in
        "" | false | 0 | no | off) return 1 ;;
        *) return 0 ;;
    esac
}

# Every failure below has the same shape: it stops the builds is_strict()
# names and lets every other build through. Writing that out at each site is
# how the asymmetry this script exists to establish would end up holding at
# three of four of them.
#
# $1 is the strict diagnostic — long, and it names the fix, because Xcode's
# issue navigator shows one line and nothing around it. $2 is the whole lenient
# line, prefix included, since some of these are a `note:` rather than a
# `warning:`.
fail_or_continue() {
    if is_strict; then
        echo "error: $1"
        exit 1
    fi
    echo "$2"
    exit 0
}

# The two strict contexts do not have the same fix, and the one line Xcode
# shows is the whole message: a dev Mac told to check that ci_post_clone ran
# has been handed a dead end, and so has a runner told to open Homebrew.
# $1 is the CI sentence, $2 the local one.
remedy() {
    if is_ci; then
        print -r -- "$1"
    else
        print -r -- "$2"
    fi
}

# Is this the build that gets shipped? Xcode's Product > Archive and
# `xcodebuild archive` both run the install action, on a runner and on a dev
# Mac alike — the build manifest for WXYC's 2026-08-11 local archive recorded
# ACTION=install, CONFIGURATION=Release, and no CI in the environment.
is_archive() {
    [[ "${ACTION:-}" == "install" ]]
}

# Can this build reach a user? An archive can. So can any CI build at a
# configuration that distributes something — Release, TestFlight, Release
# (Active Arch) are all named without a Debug prefix.
#
# It is a prefix and not an equality test on purpose. This project has two
# debug configurations, and the shared scheme's TestAction builds the second
# one: "Debug TestFlight". An `xcodebuild test -scheme WXYC` with no explicit
# -configuration — what scripts/test-affected.sh runs, and what an Xcode Cloud
# test workflow runs — lands there. Matching only the literal "Debug" would
# classify every one of those runs as shipping and fail it for want of a token
# nobody gave a test workflow.
#
# The presence of dSYMs is NOT the test either. WXYC builds Debug with
# DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an ordinary simulator build
# populates DWARF_DSYM_FOLDER_PATH exactly like an archive does.
#
# No CONFIGURATION at all is treated as shipping. A spurious CI failure is
# loud and gets fixed in an afternoon; a skipped upload is silent and is the
# whole reason this script exists.
is_shipping_build() {
    is_archive && return 0
    [[ "${CONFIGURATION:-}" == Debug* ]] && return 1
    return 0
}

# Does a missed upload stop this build?
#
# An archive does, wherever it runs — that is the build users get, and #955's
# original CI-only rule missed it entirely, because WXYC archives locally.
#
# On CI, every shipping build does, on the fail-safe reasoning above: a runner
# builds nothing a person is waiting on, so a spurious failure there costs a
# rerun. That reasoning does not survive the trip to a dev Mac, where the same
# guess would fail ordinary work — a plain Release build, or the developer-
# local `Release (Active Arch)` variant — for want of a tool the constraint on
# #955 said must stay optional. So locally it is the archive and nothing else.
is_strict() {
    is_shipping_build || return 1
    is_archive || is_ci
}

# Where the binary might be, most specific first: the copy
# ci_scripts/install-sentry-cli.sh vendors into the checkout (Xcode Cloud
# runners ship no sentry-cli and have no writable PATH entry we can count on),
# then whatever a developer installed system-wide.
resolve_sentry_cli() {
    local candidate
    for candidate in "${REPO_ROOT}/.ci-tools/bin/sentry-cli" "$(command -v sentry-cli 2>/dev/null)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done
    return 1
}

# sentry-cli takes credentials from SENTRY_AUTH_TOKEN or from a .sentryclirc in
# the working directory or the home directory. Checking first only buys a
# better diagnostic than the CLI's own — but "no token" and "token rejected"
# have completely different fixes, and the build log is where that gets read.
#
# An rc file counts only when it actually carries a token, the same test
# install-sentry-cli.sh applies before it declares an existing file good
# enough: an empty or [defaults]-only file otherwise reaches the upload and
# dies with sentry-cli's generic message instead of the one naming the fix.
has_credentials() {
    [[ -n "${SENTRY_AUTH_TOKEN:-}" ]] && return 0
    local rc
    for rc in "${REPO_ROOT}/.sentryclirc" "${HOME:-}/.sentryclirc"; do
        [[ -f "$rc" ]] && grep -q '^[[:space:]]*token[[:space:]]*=' "$rc" && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# 1. Is this a build whose symbols anyone will need?
#
# A CI runner's Debug build reports no events to Sentry, so uploading its
# dSYMs only pads the debug-file list. Skip outright rather than upload-and-
# ignore-failures, which would put a network call on the critical path of
# every test workflow. Locally the upload still runs on every build: a
# developer's simulator crashes do reach Sentry and are worth symbolicating.
#
# This comes before the dSYM check, not after, so that everything below runs
# only for builds whose symbols someone will want.
# ---------------------------------------------------------------------------

if is_ci && ! is_shipping_build; then
    echo "note: ${CONFIGURATION:-unknown}/${ACTION:-unknown} build on CI does not ship; skipping Sentry debug-symbol upload"
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Did this build produce anything to upload?
#
# Locally this is unremarkable — nothing to upload, nothing to say. On a
# shipping CI build it is a failure: all five WXYC configurations set
# DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an archive with an empty
# folder means a build setting moved, dsymutil failed, or the path changed.
# Passing that through as a note would be the #955 silence with a new cause.
# ---------------------------------------------------------------------------

dsym_folder="${DWARF_DSYM_FOLDER_PATH:-}"
missing_dsyms=""

if [[ -z "$dsym_folder" ]]; then
    missing_dsyms="DWARF_DSYM_FOLDER_PATH is not set"
elif [[ ! -d "$dsym_folder" ]]; then
    missing_dsyms="${dsym_folder} does not exist"
else
    dsym_bundles=("$dsym_folder"/*.dSYM(N))
    if (( ${#dsym_bundles} == 0 )); then
        missing_dsyms="no .dSYM bundles in ${dsym_folder}"
    fi
fi

if [[ -n "$missing_dsyms" ]]; then
    fail_or_continue \
        "this build ships but produced no debug symbols to upload (${missing_dsyms}), so its Sentry events would arrive unsymbolicated. Every WXYC configuration builds with DEBUG_INFORMATION_FORMAT = dwarf-with-dsym, so an empty dSYM folder means something upstream of this phase changed." \
        "note: ${missing_dsyms}; skipping Sentry debug-symbol upload"
fi

# ---------------------------------------------------------------------------
# 3. Is there a binary to run?
# ---------------------------------------------------------------------------

if ! sentry_cli=$(resolve_sentry_cli); then
    fail_or_continue \
        "sentry-cli is not installed, so this build's dSYMs cannot reach Sentry and its Release events would arrive unsymbolicated. $(remedy \
            'ci_scripts/install-sentry-cli.sh installs it during ci_post_clone — check that it ran and succeeded.' \
            'Install it with: brew install getsentry/tools/sentry-cli')" \
        "warning: sentry-cli not installed, skipping debug symbol upload"
fi

# ---------------------------------------------------------------------------
# 4. Is there anything to authenticate with?
# ---------------------------------------------------------------------------

if ! has_credentials; then
    fail_or_continue \
        "no Sentry credentials available (neither SENTRY_AUTH_TOKEN nor a .sentryclirc carrying a token), so this build's dSYMs cannot reach Sentry. $(remedy \
            'Set SENTRY_AUTH_TOKEN as a secret environment variable on the Xcode Cloud workflow; see docs/configuration.md.' \
            'Put an upload-scoped token in ~/.sentryclirc under [auth] as token=..., or export SENTRY_AUTH_TOKEN; see docs/configuration.md.')" \
        "warning: no Sentry credentials (SENTRY_AUTH_TOKEN or .sentryclirc), skipping debug symbol upload"
fi

# ---------------------------------------------------------------------------
# 5. Upload.
# ---------------------------------------------------------------------------

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
    fail_or_continue "sentry-cli - ${summary}" "warning: sentry-cli - ${summary}"
fi

# No count here: sentry-cli walks the whole folder and uploads every debug
# file it recognizes, not just the .dSYM bundles this script counted to decide
# whether to run at all. Its own output above is the accurate inventory.
echo "note: uploaded debug symbols to Sentry (${SENTRY_ORG}/${SENTRY_PROJECT})"
exit 0
