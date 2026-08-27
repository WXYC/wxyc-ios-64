#!/bin/zsh
#
# test-simulator-resolution.sh
#
# Regression suite for scripts/lib/simulator.zsh's `resolve_default_simulator`.
#
# The bug it exists for: three scripts and two docs each hardcoded a different
# simulator identifier, and every one of them was wrong on a developer machine
# that had merely updated Xcode — `scripts/verify-spm-parity.sh` pinned a UUID
# that no longer existed, `scripts/test-affected.sh` pinned `name=iPhone 17` on
# a machine whose only 17 is an `iPhone 17 Pro`, and `docs/build-test.md` named
# `iPhone Air` and `iPhone 16 Pro`, neither of which was installed. A simulator
# identifier is machine-local and Xcode-version-local; committing one to the
# repo guarantees it rots, and it rots into an error message
# ("Unable to find a device matching the provided destination specifier") that
# reads like a broken script rather than a stale constant.
#
# The helper is exercised against captured `simctl` output rather than the real
# thing, so these assertions hold on a runner with no simulators installed —
# which is exactly what shell-script-tests.yml is (no Xcode, no simulator).
#
# Run directly:
#   zsh scripts/tests/test-simulator-resolution.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
source "${REPO_ROOT}/scripts/tests/harness.zsh"
source "${REPO_ROOT}/scripts/lib/simulator.zsh"

# A realistic `xcrun simctl list devices available` capture: several iOS
# devices, plus the trailing non-iOS sections that must not be selected from.
FIXTURE_TYPICAL='== Devices ==
-- iOS 26.0 --
    iPhone 16 (05CFF4D7-4E19-48F8-BEA3-C899114EC4D6) (Shutdown) 
    iPhone 17 Pro (2CF7D17C-4264-44C1-A221-537810DCB80C) (Shutdown) 
    iPhone 14 Plus (AC1F69E3-AC2E-4C74-960D-BBBBCC2AF003) (Shutdown) 
-- watchOS 26.0 --
    Apple Watch Series 10 (46 mm) (BB1F69E3-AC2E-4C74-960D-BBBBCC2AF001) (Shutdown) 
-- tvOS 26.0 --
    Apple TV (CC2F69E3-AC2E-4C74-960D-BBBBCC2AF002) (Shutdown) '

stub_simctl() {
    WXYC_SIMCTL_LIST_CMD="print -r -- ${(q)1}"
}

# --- Picks something usable out of a normal machine ------------------------

stub_simctl "$FIXTURE_TYPICAL"
expect_eq "picks the first available iPhone when none is booted" \
    "$(resolve_default_simulator)" "id=05CFF4D7-4E19-48F8-BEA3-C899114EC4D6"

# --- A booted device wins ---------------------------------------------------
#
# Booting a simulator is the slowest part of an xcodebuild run, so a developer
# who already has one up should not pay for a second one to cold-boot.

stub_simctl '== Devices ==
-- iOS 26.0 --
    iPhone 16 (05CFF4D7-4E19-48F8-BEA3-C899114EC4D6) (Shutdown) 
    iPhone 17 Pro (2CF7D17C-4264-44C1-A221-537810DCB80C) (Booted) 
    iPhone 14 Plus (AC1F69E3-AC2E-4C74-960D-BBBBCC2AF003) (Shutdown) 
-- watchOS 26.0 --
    Apple Watch Series 10 (46 mm) (BB1F69E3-AC2E-4C74-960D-BBBBCC2AF001) (Shutdown) '
expect_eq "prefers a booted iPhone over an earlier shutdown one" \
    "$(resolve_default_simulator)" "id=2CF7D17C-4264-44C1-A221-537810DCB80C"

# --- Never selects out of the watchOS/tvOS sections -------------------------
#
# The app has watchOS and tvOS targets, so those sections are always present
# and always listed after iOS. A naive "first UUID in the output" would still
# pass the cases above and fail only on a machine with no iPhones — i.e. it
# would fail in the one place nobody tests.

stub_simctl '== Devices ==
-- iOS 26.0 --
-- watchOS 26.0 --
    Apple Watch Series 10 (46 mm) (BB1F69E3-AC2E-4C74-960D-BBBBCC2AF001) (Shutdown) '
resolve_default_simulator >/dev/null 2>&1
expect_eq "fails rather than returning a watchOS device when no iOS device exists" "$?" "1"

# --- Falls back past the iPhone preference ----------------------------------

stub_simctl '== Devices ==
-- iOS 26.0 --
    iPad Pro 11-inch (M4) (DD3F69E3-AC2E-4C74-960D-BBBBCC2AF003) (Shutdown) 
-- watchOS 26.0 --
    Apple Watch Series 10 (46 mm) (BB1F69E3-AC2E-4C74-960D-BBBBCC2AF001) (Shutdown) '
expect_eq "falls back to a non-iPhone iOS device when no iPhone is installed" \
    "$(resolve_default_simulator)" "id=DD3F69E3-AC2E-4C74-960D-BBBBCC2AF003"

# --- Degrades loudly --------------------------------------------------------

stub_simctl '== Devices ==
-- iOS 26.0 --'
resolve_default_simulator >/dev/null 2>&1
expect_eq "fails when the iOS section is empty" "$?" "1"

WXYC_SIMCTL_LIST_CMD="exit 72"
resolve_default_simulator >/dev/null 2>&1
expect_eq "fails when simctl itself fails" "$?" "1"

summarize
