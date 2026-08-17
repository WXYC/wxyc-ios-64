#!/bin/zsh
#
# install-sentry-cli.sh
#
# Puts a sentry-cli on the machine and gives it credentials, so the "Upload
# Debug Symbols to Sentry" build phase (scripts/upload-debug-symbols.sh) has
# both halves it needs. Called from ci_post_clone.sh; safe to run by hand on a
# dev Mac to reproduce a CI failure.
#
# Xcode Cloud runners ship no sentry-cli, and the auth token lives in
# .sentryclirc, which is gitignored and therefore absent from every clean
# checkout. Both gaps used to degrade to a `warning:` in the build phase, so
# an Xcode Cloud archive shipped with no server-side symbolication at all and
# nothing said so. (#955)
#
# Two decisions worth keeping:
#
#   The binary is vendored into the checkout at .ci-tools/bin rather than
#   installed system-wide. The upstream installer falls back to `sudo -k` when
#   its target directory isn't writable, which on a non-interactive runner is
#   a hang or a prompt-less failure, and the build phase can find a checkout-
#   relative path off SRCROOT without depending on what PATH looks like inside
#   xcodebuild.
#
#   The token is written to ~/.sentryclirc rather than left in the
#   environment. Xcode Cloud workflow environment variables are documented as
#   reaching custom build scripts; whether one reaches a run-script phase
#   nested inside xcodebuild is a much thinner guarantee. A config file on
#   disk is one sentry-cli reads no matter how it was invoked, and it costs
#   nothing to write on an ephemeral runner. SENTRY_AUTH_TOKEN still works if
#   it does propagate — this is a second path, not a replacement.
#
# Usage:
#   ci_scripts/install-sentry-cli.sh [--require-auth]
#
#   --require-auth  fail when no token is available, instead of warning. Xcode
#                   Cloud archive workflows pass this: an archive that cannot
#                   upload dSYMs should die at minute zero, not twenty minutes
#                   later in the build phase.
#
# Environment:
#   SENTRY_AUTH_TOKEN       the upload credential (an Xcode Cloud secret)
#   SENTRY_CLI_VERSION      override the pinned version below
#   SENTRY_CLI_INSTALL_DIR  override the install directory
#   SENTRY_CLI_INSTALLER    path to an installer script to run instead of
#                           downloading https://sentry.io/get-cli/ (tests)
#   SENTRY_CLI_RC_PATH      override the config file written (default
#                           ~/.sentryclirc)
#
# Tested by scripts/tests/test-install-sentry-cli.sh.

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

# Pinned, not floating. A sentry-cli that changes under the build is a way for
# an archive to start failing (or worse, start silently uploading nothing) on
# a day when nothing in this repo changed. Bump deliberately: check the
# release notes at https://github.com/getsentry/sentry-cli/releases, change
# the line below, and run an archive workflow.
PINNED_SENTRY_CLI_VERSION="3.6.2"

VERSION="${SENTRY_CLI_VERSION:-$PINNED_SENTRY_CLI_VERSION}"
INSTALL_DIR="${SENTRY_CLI_INSTALL_DIR:-${REPO_ROOT}/.ci-tools/bin}"
INSTALL_PATH="${INSTALL_DIR}/sentry-cli"
RC_PATH="${SENTRY_CLI_RC_PATH:-${HOME:-}/.sentryclirc}"

REQUIRE_AUTH=false
for arg in "$@"; do
    case "$arg" in
        --require-auth) REQUIRE_AUTH=true ;;
        *)
            echo "error: unknown argument '$arg'"
            exit 1
            ;;
    esac
done

# `sentry-cli --version` prints "sentry-cli X.Y.Z".
installed_version() {
    [[ -x "$INSTALL_PATH" ]] || return 1
    local reported
    reported=$("$INSTALL_PATH" --version 2>/dev/null) || return 1
    print -r -- "${reported##* }"
}

echo "🔧 sentry-cli ${VERSION}"
echo "   Install path: ${INSTALL_PATH}"

# ---------------------------------------------------------------------------
# 1. Install the binary, unless the pinned version is already sitting there.
# ---------------------------------------------------------------------------

current=$(installed_version)
if [[ "$current" == "$VERSION" ]]; then
    echo "   Already installed at the pinned version; skipping download"
else
    if [[ -e "$INSTALL_PATH" ]]; then
        # The upstream installer refuses to overwrite, so a stale copy (a
        # warm runner cache, an older pin) has to go first.
        echo "   Replacing sentry-cli ${current:-unknown} with ${VERSION}"
        rm -f "$INSTALL_PATH"
    fi

    installer="${SENTRY_CLI_INSTALLER:-}"
    installer_tmp=""
    if [[ -z "$installer" ]]; then
        installer_tmp=$(mktemp -t sentry-get-cli) || {
            echo "error: could not create a temporary file for the sentry-cli installer"
            exit 1
        }
        if ! curl -sSfL https://sentry.io/get-cli/ -o "$installer_tmp"; then
            echo "error: could not download the sentry-cli installer from https://sentry.io/get-cli/"
            rm -f "$installer_tmp"
            exit 1
        fi
        installer="$installer_tmp"
    fi

    INSTALL_DIR="$INSTALL_DIR" SENTRY_CLI_VERSION="$VERSION" sh "$installer"
    install_status=$?
    [[ -n "$installer_tmp" ]] && rm -f "$installer_tmp"

    if (( install_status != 0 )); then
        echo "error: the sentry-cli installer failed (exit ${install_status}); dSYMs from this build cannot be uploaded to Sentry"
        rm -f "$INSTALL_PATH"
        exit 1
    fi

    # A pin nobody verifies is a comment. The installer resolves the version
    # server-side, so this is the only place a typo'd or yanked version shows
    # up as something other than a mystery later.
    current=$(installed_version)
    if [[ "$current" != "$VERSION" ]]; then
        echo "error: installed sentry-cli reports version ${current:-unknown}, expected the pinned ${VERSION}"
        rm -f "$INSTALL_PATH"
        exit 1
    fi
    echo "   Installed sentry-cli ${current}"
fi

# ---------------------------------------------------------------------------
# 2. Give it something to authenticate with.
# ---------------------------------------------------------------------------

if [[ -f "$RC_PATH" ]]; then
    # Never clobber one that already exists — on a dev Mac that file is the
    # developer's own token, and this script is meant to be runnable there.
    echo "   Leaving the existing ${RC_PATH} in place"

    # Never-clobber is not never-check. An rc file with no token in it — an
    # empty one, a stale [defaults]-only section — satisfies "the file exists"
    # while leaving the archive exactly as unable to upload as it was, and
    # --require-auth exists to catch that here rather than twenty minutes on.
    if grep -q '^[[:space:]]*token[[:space:]]*=' "$RC_PATH"; then
        exit 0
    fi
    if [[ -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
        echo "   It carries no token, but SENTRY_AUTH_TOKEN is set and takes precedence"
        exit 0
    fi
    if [[ "$REQUIRE_AUTH" == "true" ]]; then
        echo "error: ${RC_PATH} exists but carries no token= line, and SENTRY_AUTH_TOKEN is not set, so this archive could not upload its dSYMs to Sentry. Add SENTRY_AUTH_TOKEN as a secret environment variable on the Xcode Cloud workflow; see docs/configuration.md."
        exit 1
    fi
    echo "warning: ${RC_PATH} carries no token= line and SENTRY_AUTH_TOKEN is not set; debug symbols will not be uploaded"
    exit 0
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
    if [[ "$REQUIRE_AUTH" == "true" ]]; then
        echo "error: SENTRY_AUTH_TOKEN is not set and there is no ${RC_PATH}, so this archive could not upload its dSYMs to Sentry. Add SENTRY_AUTH_TOKEN as a secret environment variable on the Xcode Cloud workflow; see docs/configuration.md."
        exit 1
    fi
    echo "warning: SENTRY_AUTH_TOKEN is not set and there is no ${RC_PATH}; debug symbols will not be uploaded"
    exit 0
fi

# umask first: the token must never exist, even momentarily, at a mode other
# than 600.
umask 077
if ! printf '[auth]\ntoken=%s\n' "$SENTRY_AUTH_TOKEN" > "$RC_PATH"; then
    echo "error: could not write ${RC_PATH}"
    exit 1
fi
chmod 600 "$RC_PATH"
echo "   Wrote Sentry credentials to ${RC_PATH} (mode 600)"

exit 0
