#!/bin/zsh
#
# test-api-types-contract-version.sh
#
# Black-box regression tests for the contract-version.json <-> api.yaml
# version assertion in scripts/regenerate-api-types.sh (#923).
#
# The script under test normally clones wxyc-shared over the network, runs
# `npm ci`, and drives a JVM code generator -- none of which this suite wants
# or needs, because the assertion it covers fires between the checkout and
# `npm ci`. So the fixture replaces both ends:
#
#   * a local git repo standing in for wxyc-shared, containing nothing but an
#     api.yaml with a chosen `  version:` line, passed via --remote (git is
#     perfectly happy cloning a path), and
#   * a PATH-prepended stub dir holding `npm` and `java`, so the preflight
#     tool check passes on any runner and the first post-assertion step
#     (`npm ci`) fails with a marker this suite can recognize.
#
# That marker is what makes the MATCH case testable at all: a matching label
# cannot be asserted by "the script succeeded" without a real codegen run, but
# it can be asserted by "the script got past the version gate and on to npm".
#
# The script resolves its own repo root as the parent of its directory, so
# copying it into a temp tree is enough to redirect which contract-version.json
# it reads -- the same redirection trick test-pre-push-hook.sh uses.
#
# Run directly:
#   zsh scripts/tests/test-api-types-contract-version.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
UNDER_TEST="${REPO_ROOT}/scripts/regenerate-api-types.sh"

if [[ ! -f "$UNDER_TEST" ]]; then
    echo "Cannot find regenerate-api-types.sh at $UNDER_TEST" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wxyc-contract-version-test.XXXXXX") || exit 2
trap 'rm -rf "$TMP_ROOT"' EXIT

# -------------------------------------------------------------------------
# Fixture: stub npm/java on PATH
# -------------------------------------------------------------------------

STUB_BIN="$TMP_ROOT/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/npm" <<'STUB'
#!/bin/zsh
echo "STUB_NPM_REACHED $*"
exit 17
STUB
cat > "$STUB_BIN/java" <<'STUB'
#!/bin/zsh
echo "STUB_JAVA_REACHED $*"
exit 17
STUB
chmod +x "$STUB_BIN/npm" "$STUB_BIN/java"
export PATH="$STUB_BIN:$PATH"

# -------------------------------------------------------------------------
# Fixture: a local stand-in for wxyc-shared, with two commits carrying
# different api.yaml versions so a pin can point at either.
# -------------------------------------------------------------------------

FAKE_SHARED="$TMP_ROOT/wxyc-shared"
git init -q -b main "$FAKE_SHARED"
git -C "$FAKE_SHARED" config user.email "test@wxyc.org"
git -C "$FAKE_SHARED" config user.name "WXYC CI Test"

write_api_yaml() {
    cat > "$FAKE_SHARED/api.yaml" <<YAML
openapi: 3.0.3
info:
  title: WXYC Backend API
  version: $1
paths: {}
components:
  schemas:
    Thing:
      type: object
      properties:
        version:
          type: string
YAML
}

write_api_yaml "9.9.0"
git -C "$FAKE_SHARED" add api.yaml
git -C "$FAKE_SHARED" commit -q -m "api.yaml 9.9.0"
SHA_OLD=$(git -C "$FAKE_SHARED" rev-parse HEAD)

write_api_yaml "10.0.0"
git -C "$FAKE_SHARED" add api.yaml
git -C "$FAKE_SHARED" commit -q -m "api.yaml 10.0.0"
SHA_NEW=$(git -C "$FAKE_SHARED" rev-parse HEAD)

# -------------------------------------------------------------------------
# Fixture: a temp "wxyc-ios-64" holding a copy of the script under test and a
# contract-version.json the test controls.
# -------------------------------------------------------------------------

FAKE_REPO="$TMP_ROOT/ios"
mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/Shared/WXYCAPIModels"
cp "$UNDER_TEST" "$FAKE_REPO/scripts/regenerate-api-types.sh"
chmod +x "$FAKE_REPO/scripts/regenerate-api-types.sh"

# run_with <contract-json> -- writes the manifest, runs the script against the
# fake remote with a scratch dir of its own, and leaves combined output in
# $out and the exit status in $RUN_STATUS.
#
# Deliberately NOT `out=$(run_with ...)`: a command substitution runs the whole
# function in a subshell, so RUN_STATUS would be assigned in a child and every
# exit-status assertion would read a stale 0 from the parent -- which is
# exactly how the first draft of this suite passed its message assertions while
# silently checking nothing about exit codes. Output goes through a file for
# the same reason.
typeset -g RUN_STATUS=0
typeset -g out=""
typeset -gi RUN_SEQ=0
run_with() {
    print -r -- "$1" > "$FAKE_REPO/Shared/WXYCAPIModels/contract-version.json"
    RUN_SEQ=$((RUN_SEQ + 1))
    "$FAKE_REPO/scripts/regenerate-api-types.sh" \
        --remote "$FAKE_SHARED" \
        --work-dir "$TMP_ROOT/work-$RUN_SEQ" \
        --dest-dir "$TMP_ROOT/dest-$RUN_SEQ" \
        > "$TMP_ROOT/run-$RUN_SEQ.log" 2>&1
    RUN_STATUS=$?
    out=$(<"$TMP_ROOT/run-$RUN_SEQ.log")
}

# -------------------------------------------------------------------------
# Case 1: label disagrees with the pinned commit -> fails, naming both values
# -------------------------------------------------------------------------

run_with "{\"wxycSharedTag\": \"v10.0.0\", \"wxycSharedSha\": \"$SHA_OLD\", \"apiYamlVersion\": \"10.0.0\"}"
expect_exit "mismatched apiYamlVersion exits non-zero" "$RUN_STATUS" "1" "$out"
expect_contains "mismatch names the declared version" "$out" "apiYamlVersion: 10.0.0"
expect_contains "mismatch names the pinned commit's version" "$out" "info.version: 9.9.0"
expect_contains "mismatch names the sha it read" "$out" "$SHA_OLD"
expect_contains "mismatch offers both remedies" "$out" "or move wxycSharedSha"
expect_not_contains "mismatch stops before npm ci" "$out" "STUB_NPM_REACHED"

# -------------------------------------------------------------------------
# Case 2: the reverse mismatch (stale sha, advanced label) is caught too --
# the check is equality, not "the label is at least as new"
# -------------------------------------------------------------------------

run_with "{\"wxycSharedTag\": \"main\", \"wxycSharedSha\": \"$SHA_NEW\", \"apiYamlVersion\": \"9.9.0\"}"
expect_exit "reverse mismatch exits non-zero" "$RUN_STATUS" "1" "$out"
expect_contains "reverse mismatch names the declared version" "$out" "apiYamlVersion: 9.9.0"
expect_contains "reverse mismatch names the pinned commit's version" "$out" "info.version: 10.0.0"

# -------------------------------------------------------------------------
# Case 3: label matches -> the gate passes and the run proceeds to codegen
# -------------------------------------------------------------------------

run_with "{\"wxycSharedTag\": \"v10.0.0\", \"wxycSharedSha\": \"$SHA_NEW\", \"apiYamlVersion\": \"10.0.0\"}"
expect_contains "matching label logs the agreed version" "$out" "Contract label matches the pinned commit (api.yaml info.version: 10.0.0)"
expect_not_contains "matching label does not report a sync error" "$out" "out of sync with the commit it pins"
expect_contains "matching label proceeds to npm ci" "$out" "STUB_NPM_REACHED ci"

# -------------------------------------------------------------------------
# Case 4: apiYamlVersion absent -> refused, rather than silently unchecked
# -------------------------------------------------------------------------

run_with "{\"wxycSharedTag\": \"v10.0.0\", \"wxycSharedSha\": \"$SHA_NEW\"}"
expect_exit "missing apiYamlVersion exits non-zero" "$RUN_STATUS" "1" "$out"
expect_contains "missing apiYamlVersion says which field" "$out" "apiYamlVersion missing or empty"
expect_not_contains "missing apiYamlVersion stops before cloning" "$out" "Cloning"

# -------------------------------------------------------------------------
# Case 5: the sha is still the authority -- an unresolvable one fails at
# checkout, and never reaches the version comparison
# -------------------------------------------------------------------------

run_with "{\"wxycSharedTag\": \"v10.0.0\", \"wxycSharedSha\": \"0000000000000000000000000000000000000000\", \"apiYamlVersion\": \"10.0.0\"}"
expect_exit "unresolvable sha exits non-zero" "$RUN_STATUS" "1" "$out"
expect_contains "unresolvable sha fails at checkout" "$out" "checkout of 0000000000000000000000000000000000000000"
expect_not_contains "unresolvable sha never claims a version match" "$out" "Contract label matches"

summarize
