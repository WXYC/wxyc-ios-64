#!/bin/zsh
#
# simulator.zsh
#
# Run-time resolution of an iOS Simulator destination. Sourced, never executed.
#
# Every script and doc in this repo used to carry its own hardcoded simulator
# identifier, and they disagreed with each other and with the machine:
# `verify-spm-parity.sh` pinned a UUID, `test-affected.sh` pinned
# `name=iPhone 17`, `docs/build-test.md` named `iPhone Air` and `iPhone 16 Pro`,
# and `CLAUDE.md` named a fifth. A simulator identifier is local to one machine
# and one Xcode version, so a committed one is a constant with an expiry date —
# and it expires into `xcodebuild: error: Unable to find a device matching the
# provided destination specifier`, which reads like a broken script rather than
# a stale literal, several minutes into a build.
#
# Callers that want a specific device still pass `--simulator`; this is only the
# default. Selection order:
#
#   1. A booted iPhone — booting is the slowest part of an xcodebuild run, so
#      reuse one the developer already has up.
#   2. Any available iPhone.
#   3. Any available iOS device (an iPad-only install is unusual but workable).
#
# Selection is confined to the `-- iOS ... --` section. The watchOS and tvOS
# sections are always present, because the app has targets for both, and they
# sort after iOS — so "first UUID in the output" would work everywhere except
# a machine with no iPhone, which is the one case the fallback exists for.
#
# Usage:
#
#     source "${REPO_ROOT}/scripts/lib/simulator.zsh"
#     SIMULATOR=$(resolve_default_simulator) || { ...; exit 1; }
#
# Returns `id=<UUID>` on stdout, or nonzero with nothing on stdout.

# The device list is read through a variable so the regression suite can feed
# captured output: shell-script-tests.yml runs on a box with no Xcode and no
# simulators, and the selection logic is exactly what has to be tested there.
: "${WXYC_SIMCTL_LIST_CMD:=xcrun simctl list devices available}"

resolve_default_simulator() {
    local raw ios_section line udid

    raw=$(eval "${WXYC_SIMCTL_LIST_CMD}" 2>/dev/null) || return 1

    ios_section=$(print -r -- "$raw" | awk '/^-- iOS /{f=1; next} /^-- /{f=0} f')
    [[ -n "$ios_section" ]] || return 1

    line=$(print -r -- "$ios_section" | grep -F 'iPhone' | grep -F '(Booted)' | head -1)
    [[ -n "$line" ]] || line=$(print -r -- "$ios_section" | grep -F 'iPhone' | head -1)
    [[ -n "$line" ]] || line=$(print -r -- "$ios_section" | grep -E '\([0-9A-Fa-f-]{36}\)' | head -1)
    [[ -n "$line" ]] || return 1

    udid=$(print -r -- "$line" | sed -E 's/.*\(([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})\).*/\1/')
    [[ "$udid" != "$line" ]] || return 1

    print -r -- "id=${udid}"
}

# Resolve, or exit with a message that names what IS installed — the failure a
# developer actually needs to act on is "your machine has these instead", not
# "the destination specifier was invalid".
resolve_default_simulator_or_die() {
    local resolved
    if ! resolved=$(resolve_default_simulator); then
        print -r -- "No available iOS Simulator found. Installed devices:" >&2
        eval "${WXYC_SIMCTL_LIST_CMD}" >&2 2>/dev/null || print -r -- "  (xcrun simctl list failed)" >&2
        print -r -- "Install one in Xcode, or pass --simulator 'name=<device>'." >&2
        return 1
    fi
    print -r -- "$resolved"
}
