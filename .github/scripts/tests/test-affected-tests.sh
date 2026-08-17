#!/bin/zsh
#
# test-affected-tests.sh
#
# Black-box regression tests for .github/scripts/affected-tests.sh. Each test
# invokes the real script as a subprocess (or sources it, for the output()
# isolation cases) against a controlled BASE_REF/CHANGED_FILES/git-history
# fixture and asserts on stdout, $GITHUB_OUTPUT contents, and exit code.
#
# No test framework dependency (bats etc. aren't vendored here) — this mirrors
# the hand-rolled style of scripts/tests/test_wxyc_utils.rb: plain assertions,
# a pass/fail counter, a TAP-ish log, nonzero exit on any failure.
#
# Run directly:
#   zsh .github/scripts/tests/test-affected-tests.sh
#
# Covers:
#   - #360: *.xcodeproj/* fallback distinguishes structural pbxproj edits
#     (new PBXNativeTarget, new membershipExceptions entry) from cosmetic
#     ones (renamed PBXGroup, reordered children) — only the former forces
#     run-all.
#   - #362 item 2: whitespace-only CHANGED_FILES is treated as "no changed
#     files" (run-all with a clear reason), not silently threaded through as
#     if it named a real file.
#   - #362 item 3: the output() helper rejects a multi-line value instead of
#     letting it corrupt the KEY=VALUE $GITHUB_OUTPUT format that
#     scripts/test-affected.sh's parser assumes.

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h:h}"
SCRIPT="${SCRIPT_DIR}/../affected-tests.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "Cannot find affected-tests.sh at $SCRIPT" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

# -----------------------------------------------------------------------
# run_script — invokes affected-tests.sh as a subprocess with the given
# BASE_REF / CHANGED_FILES (unset when CHANGED_FILES_SET=0) from CWD, and
# captures combined stdout+stderr, exit code, and $GITHUB_OUTPUT contents
# into LAST_OUT / LAST_EXIT / LAST_GH.
# -----------------------------------------------------------------------

typeset -g LAST_OUT LAST_EXIT LAST_GH

run_script() {
    local cwd="$1" base_ref="$2" changed_files_set="$3" changed_files_val="$4"
    local gh_output
    gh_output=$(mktemp)
    LAST_OUT=$(
        cd "$cwd" || exit 99
        export BASE_REF="$base_ref"
        if [[ "$changed_files_set" == "1" ]]; then
            export CHANGED_FILES="$changed_files_val"
        else
            unset CHANGED_FILES
        fi
        export GITHUB_OUTPUT="$gh_output"
        zsh "$SCRIPT" 2>&1
    )
    LAST_EXIT=$?
    LAST_GH=$(cat "$gh_output" 2>/dev/null)
    rm -f "$gh_output"
}

# =========================================================================
# Group 1 (#362 item 2) — whitespace-only CHANGED_FILES
# =========================================================================

echo "=== Group 1: whitespace-only CHANGED_FILES (#362) ==="

BASE_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)

run_script "$REPO_ROOT" "$BASE_SHA" 1 "   "
expect_contains "spaces-only CHANGED_FILES: reason is 'no changed files'" "$LAST_OUT" "no changed files"
expect_contains "spaces-only CHANGED_FILES: run_all=true in \$GITHUB_OUTPUT" "$LAST_GH" $'run_all=true'
expect_contains "spaces-only CHANGED_FILES: xcb_required=true (fail-open)" "$LAST_GH" $'xcb_required=true'

run_script "$REPO_ROOT" "$BASE_SHA" 1 $'\n   \n\t\n'
expect_contains "blank-lines-only CHANGED_FILES: reason is 'no changed files'" "$LAST_OUT" "no changed files"
expect_contains "blank-lines-only CHANGED_FILES: run_all=true" "$LAST_GH" $'run_all=true'

run_script "$REPO_ROOT" "$BASE_SHA" 1 "Shared/Core/Foo.swift"
expect_contains "regression: a real single-file CHANGED_FILES still scopes normally (run_all=false)" "$LAST_GH" $'run_all=false'
expect_contains "regression: Core still shows up as a directly changed package" "$LAST_OUT" "Directly changed packages: Core"

run_script "$REPO_ROOT" "$BASE_SHA" 1 $'Shared/Core/Foo.swift\n\n\nShared/Playlist/Bar.swift'
expect_contains "regression: blank lines between real files don't eat the second file (Core)" "$LAST_OUT" "Core"
expect_contains "regression: blank lines between real files don't eat the second file (Playlist)" "$LAST_OUT" "Playlist"

# =========================================================================
# Group 2 (#362 item 3) — output() rejects multi-line values
# =========================================================================

echo ""
echo "=== Group 2: output() newline guard (#362) ==="

# The non-run_all path falls off the end of the script without calling
# exit, so sourcing it (with a plain Shared/ change that never hits a
# run_all_and_exit branch) leaves `output` defined and control returned to
# us afterward — no production refactor needed to test this in isolation.
# The guard itself does a hard `exit 1` (matching the rest of the script's
# set -e fail-fast style), so a single subprocess can only observe it in the
# subprocess's own exit code, not via a captured "$?" echoed after the call —
# that line would never run. Two separate subprocesses: good value, bad value.
gh_output=$(mktemp)
GOOD_TEST_OUT=$(
    zsh -c "
        set -uo pipefail
        cd '$REPO_ROOT' || exit 99
        export BASE_REF='$BASE_SHA'
        export CHANGED_FILES='Shared/Core/Foo.swift'
        export GITHUB_OUTPUT='$gh_output'
        source '$SCRIPT' > /dev/null 2>&1
        echo SOURCED_COMPLETED
        output good_key 'single line value'
        echo REACHED_AFTER_GOOD_VALUE
    " 2>&1
)
GOOD_EXIT=$?
rm -f "$gh_output"

gh_output=$(mktemp)
BAD_TEST_OUT=$(
    zsh -c "
        set -uo pipefail
        cd '$REPO_ROOT' || exit 99
        export BASE_REF='$BASE_SHA'
        export CHANGED_FILES='Shared/Core/Foo.swift'
        export GITHUB_OUTPUT='$gh_output'
        source '$SCRIPT' > /dev/null 2>&1
        echo SOURCED_COMPLETED
        output bad_key \$'line one\nline two'
        echo REACHED_AFTER_BAD_VALUE
    " 2>&1
)
BAD_EXIT=$?
rm -f "$gh_output"

expect_contains "sourcing the non-run_all path completes without exiting" "$GOOD_TEST_OUT" "SOURCED_COMPLETED"
expect_eq "single-line value: guard does not false-positive (subprocess exit 0)" "$GOOD_EXIT" "0"
expect_contains "single-line value: control returns after the call" "$GOOD_TEST_OUT" "REACHED_AFTER_GOOD_VALUE"
expect_not_contains "multi-line value: guard does not let control fall through" "$BAD_TEST_OUT" "REACHED_AFTER_BAD_VALUE"
expect_contains "multi-line value: guard prints a clear error to stderr" "$BAD_TEST_OUT" "contains a newline"
if [[ "$BAD_EXIT" != "0" ]]; then
    ok "multi-line value: guard fails loudly (subprocess exit $BAD_EXIT, nonzero)"
else
    fail "multi-line value: guard fails loudly (subprocess exit $BAD_EXIT, nonzero)" "expected nonzero, got 0"
fi

# =========================================================================
# Group 3 (#360) — pbxproj structural vs. cosmetic fallback
# =========================================================================

echo ""
echo "=== Group 3: pbxproj structural-vs-cosmetic (#360) ==="

PBX_REPO=$(mktemp -d)
git -C "$PBX_REPO" init -q
git -C "$PBX_REPO" config user.email "test@wxyc.org"
git -C "$PBX_REPO" config user.name "WXYC CI Test"

mkdir -p "$PBX_REPO/Fake.xcodeproj"
cat > "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PBX'
// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 56;
	objects = {

/* Begin PBXFileReference section */
		AAAA1111 /* README.md */ = {isa = PBXFileReference; lastKnownFileType = text; path = README.md; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		BBBB2222 = {
			isa = PBXGroup;
			name = "Docs";
			children = (
				AAAA1111 /* README.md */,
				CCCC3333 /* Sources */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		GGGG7777 = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				ExistingFile.swift,
				Tests/AlphaTests.swift,
				Tests/BravoTests.swift,
				Tests/CharlieTests.swift,
				Tests/DeltaTests.swift,
				Tests/EchoTests.swift,
				Tests/FoxtrotTests.swift,
				Tests/GolfTests.swift,
				Tests/HotelTests.swift,
				Tests/IndiaTests.swift,
				Tests/JulietTests.swift,
				Tests/KiloTests.swift,
				Tests/LimaTests.swift,
				Tests/MikeTests.swift,
				Tests/NovemberTests.swift,
				Tests/OscarTests.swift,
				Tests/PapaTests.swift,
				Tests/QuebecTests.swift,
				Tests/RomeoTests.swift,
				Tests/SierraTests.swift,
			);
			target = DDDD4444;
		};
		GGGG8888 = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Other/UniformTests.swift,
				Other/VictorTests.swift,
				Other/WhiskeyTests.swift,
			);
			target = EEEE5555;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin XCBuildConfiguration section */
		HHHH9999 = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MARKETING_VERSION = 3.2.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

	};
	rootObject = FFFF6666;
}
PBX
git -C "$PBX_REPO" add -A
git -C "$PBX_REPO" commit -q -m "base pbxproj fixture"
PBX_BASE_SHA=$(git -C "$PBX_REPO" rev-parse HEAD)

# --- Cosmetic: rename a PBXGroup (no isa=/membershipExceptions line touched) ---
sed -i '' 's/name = "Docs";/name = "Documentation";/' "$PBX_REPO/Fake.xcodeproj/project.pbxproj"
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "cosmetic group rename: run_all=false" "$LAST_GH" $'run_all=false'
expect_contains "cosmetic group rename: logged as ignored, not run-all" "$LAST_OUT" "ignoring cosmetic project file change"
expect_not_contains "cosmetic group rename: does not claim a structural reason" "$LAST_OUT" "structural project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Cosmetic: reorder two entries in a children array ---
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "\t\t\t\tAAAA1111 /* README.md */,\n\t\t\t\tCCCC3333 /* Sources */,\n",
    "\t\t\t\tCCCC3333 /* Sources */,\n\t\t\t\tAAAA1111 /* README.md */,\n",
)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "cosmetic reorder: run_all=false" "$LAST_GH" $'run_all=false'
expect_contains "cosmetic reorder: logged as ignored" "$LAST_OUT" "ignoring cosmetic project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: add a new PBXNativeTarget block ---
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
addition = (
    "\n/* Begin PBXNativeTarget section */\n"
    "\t\tDDDD4444 /* NewTestTarget */ = {\n"
    "\t\t\tisa = PBXNativeTarget;\n"
    "\t\t\tname = NewTestTarget;\n"
    "\t\t};\n"
    "/* End PBXNativeTarget section */\n"
)
text = text.replace("\trootObject = FFFF6666;\n", addition + "\trootObject = FFFF6666;\n")
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural new target: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural new target: reason names the file" "$LAST_OUT" "structural project file change: Fake.xcodeproj/project.pbxproj"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: add a membershipExceptions entry near the TOP of the array ---
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "\t\t\t\tExistingFile.swift,\n",
    "\t\t\t\tExistingFile.swift,\n\t\t\t\tNewlyAddedFile.swift,\n",
)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural membershipExceptions change: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural membershipExceptions change: reason names the file" "$LAST_OUT" "structural project file change: Fake.xcodeproj/project.pbxproj"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: add a membershipExceptions entry in the MIDDLE of the array.
#
# This is the case that matters most, and the reason the classifier compares
# sorted fingerprints instead of grepping the textual diff for keywords. The
# only line carrying the `membershipExceptions` keyword is the array's
# declaration, which does not change when an entry is added — so a keyword
# grep over the diff only sees it when the edit happens to land within git's
# 3 lines of context. Real arrays in WXYC.xcodeproj are 5-78 entries and are
# sorted by path, so an ordinary new test file lands mid-array and the keyword
# is nowhere in the hunk. Measured against the real project file before the
# fix: adding a test file to the WXYCTests exception set classified as
# cosmetic, i.e. silently skipped every test. Keep an assertion on a mid-array
# edit — a fixture whose array is short enough to keep the declaration line in
# context will pass while the real repo fails.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "\t\t\t\tTests/JulietTests.swift,\n",
    "\t\t\t\tTests/JulietTests.swift,\n\t\t\t\tTests/JulietteAddedTests.swift,\n",
    1,
)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural mid-array membershipExceptions ADD: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural mid-array membershipExceptions ADD: logged as structural" "$LAST_OUT" "structural project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: REMOVE an entry from the middle of the array (a file losing
# target membership — test-affecting, and never accompanied by a change to the
# .swift file itself, so nothing else in the changed-file set can cover it).
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("\t\t\t\tTests/KiloTests.swift,\n", "", 1)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural mid-array membershipExceptions REMOVE: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural mid-array membershipExceptions REMOVE: logged as structural" "$LAST_OUT" "structural project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: MOVE a file from one target's exception set to another's.
# The multiset of entry strings is unchanged by a naive whole-file comparison,
# so the fingerprint has to be keyed by the owning object's UUID for this to
# register. Without that key this reads as an identical permutation.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("\t\t\t\tTests/LimaTests.swift,\n", "", 1)
text = text.replace(
    "\t\t\t\tOther/UniformTests.swift,\n",
    "\t\t\t\tOther/UniformTests.swift,\n\t\t\t\tTests/LimaTests.swift,\n",
    1,
)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural cross-target membership MOVE: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural cross-target membership MOVE: logged as structural" "$LAST_OUT" "structural project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Cosmetic: reorder two entries within a membershipExceptions array.
# Same membership set, different order — Xcode reshuffles these freely.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "\t\t\t\tTests/MikeTests.swift,\n\t\t\t\tTests/NovemberTests.swift,\n",
    "\t\t\t\tTests/NovemberTests.swift,\n\t\t\t\tTests/MikeTests.swift,\n",
    1,
)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "cosmetic intra-array reorder: run_all=false" "$LAST_GH" $'run_all=false'
expect_contains "cosmetic intra-array reorder: logged as ignored" "$LAST_OUT" "ignoring cosmetic project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Cosmetic: bump a build setting (MARKETING_VERSION). A real, recurring
# pbxproj edit that has no bearing on which tests should run.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("MARKETING_VERSION = 3.2.0;", "MARKETING_VERSION = 3.2.1;", 1)
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "cosmetic build-setting bump: run_all=false" "$LAST_GH" $'run_all=false'
expect_contains "cosmetic build-setting bump: logged as ignored" "$LAST_OUT" "ignoring cosmetic project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: add a local Swift package to the project.
#
# Regression guard for a real gap: commit 09923949f ("on-device liked-songs
# store package") added Shared/LikedSongs to the project as a five-line diff
# containing only an XCLocalSwiftPackageReference block and its
# packageReferences entry — no PBX* object type anywhere in it. A fingerprint
# tracking only PBX* types reports that as cosmetic.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
addition = (
    "/* Begin XCLocalSwiftPackageReference section */\n"
    "\t\tPKGREF0001 /* XCLocalSwiftPackageReference \"Shared/NewPkg\" */ = {\n"
    "\t\t\tisa = XCLocalSwiftPackageReference;\n"
    "\t\t\trelativePath = Shared/NewPkg;\n"
    "\t\t};\n"
    "/* End XCLocalSwiftPackageReference section */\n\n"
)
text = text.replace("\t};\n\trootObject = FFFF6666;\n", "\t};\n" + addition + "\trootObject = FFFF6666;\n")
open(path, "w").write(text)
PY
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural: adding a local Swift package: run_all=true" "$LAST_GH" $'run_all=true'
expect_contains "structural: adding a local Swift package: logged as structural" "$LAST_OUT" "structural project file change"
git -C "$PBX_REPO" checkout -q -- Fake.xcodeproj/project.pbxproj

# --- Structural: an uncommitted working-tree edit is inspected too (the
# pre-push hook routinely runs against a dirty tree). Every case above is
# already a working-tree edit rather than a commit, which is the point — but
# assert the committed-diff path as well so both are covered.
python3 - "$PBX_REPO/Fake.xcodeproj/project.pbxproj" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("\t\t\t\tTests/RomeoTests.swift,\n", "", 1)
open(path, "w").write(text)
PY
git -C "$PBX_REPO" commit -q -am "committed structural change"
run_script "$PBX_REPO" "$PBX_BASE_SHA" 1 "Fake.xcodeproj/project.pbxproj"
expect_contains "structural change in a COMMIT (not just worktree): run_all=true" "$LAST_GH" $'run_all=true'
git -C "$PBX_REPO" reset -q --hard "$PBX_BASE_SHA"

rm -rf "$PBX_REPO"

# =========================================================================
# Summary
# =========================================================================

summarize
