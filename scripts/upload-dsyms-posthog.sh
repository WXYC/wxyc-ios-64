#!/bin/zsh
#
# upload-dsyms-posthog.sh
#
# Uploads the dSYMs this build produced to PostHog (project 134292, WXYC iOS),
# which symbolicates exception stacks server-side. Run by the "Upload Debug
# Symbols to PostHog" build phase on the WXYC target, on every build.
#
# Warn, never fail. Unlike upload-debug-symbols.sh this phase has no strict
# mode: until release tagging and credentials land (#1167) a missed upload is
# a `warning:` on every build and the build continues. Every failure path
# below exits 0.
#
# Environment:
#   DWARF_DSYM_FOLDER_PATH   supplied by Xcode; the folder holding this build's dSYMs
#   POSTHOG_CLI_API_KEY      optional; read from ~/.posthog-cli.env when unset,
#                            because Xcode.app does not inherit a shell's environment
#   POSTHOG_CLI_SEARCH_DIRS  optional, colon-separated; prefixes to check for
#                            posthog-cli beyond PATH. See the default.
#
# Tested by scripts/tests/test-upload-dsyms-posthog.sh.

set -uo pipefail

if [ -z "${POSTHOG_CLI_API_KEY:-}" ] && [ -r ~/.posthog-cli.env ]; then set -a; . ~/.posthog-cli.env; set +a; fi

export POSTHOG_CLI_PROJECT_ID=134292

# A build phase's PATH omits /opt/homebrew/bin; see upload-debug-symbols.sh.
# `=` and not `:=` so the tests can pass an explicit empty string.
: ${POSTHOG_CLI_SEARCH_DIRS=/opt/homebrew/bin:/usr/local/bin}

resolve_posthog_cli() {
    local candidate dir
    candidate="$(command -v posthog-cli 2>/dev/null)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        print -r -- "$candidate"
        return 0
    fi
    for dir in ${(s.:.)POSTHOG_CLI_SEARCH_DIRS}; do
        if [[ -x "${dir}/posthog-cli" ]]; then
            print -r -- "${dir}/posthog-cli"
            return 0
        fi
    done
    return 1
}

if ! posthog_cli=$(resolve_posthog_cli); then
    echo "warning: posthog-cli not found; install with: brew install posthog/tap/posthog-cli"
    exit 0
fi

if [[ -z "${POSTHOG_CLI_API_KEY:-}" ]]; then
    echo "warning: no POSTHOG_CLI_API_KEY; put POSTHOG_CLI_API_KEY=... in ~/.posthog-cli.env, skipping PostHog debug symbol upload"
    exit 0
fi

# stderr is captured so the failure rides on the one `warning:` line Xcode shows.
{
    upload_error=$("$posthog_cli" dsym upload --directory "${DWARF_DSYM_FOLDER_PATH:-}" --include-source 2>&1 >&3 3>&-)
    upload_status=$?
} 3>&1

if (( upload_status != 0 )); then
    echo "warning: posthog-cli dsym upload failed - ${upload_error//$'\n'/ }"
    exit 0
fi

echo "note: uploaded debug symbols to PostHog (project ${POSTHOG_CLI_PROJECT_ID})"
exit 0
