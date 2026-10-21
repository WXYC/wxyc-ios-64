#!/bin/zsh
#
# test-upload-dsyms-posthog.sh
#
# Black-box regression test for scripts/upload-dsyms-posthog.sh — the script
# the "Upload Debug Symbols to PostHog" build phase runs (#1165).
#
# The contract is warn-never-fail: whatever goes wrong — no posthog-cli, no API
# key, a rejected upload — the script prints a `warning:` line and exits 0, and
# the build continues. The stub posthog-cli records its argv and whether the
# API key reached it, never the key itself.
#
# HOME is always a throwaway directory so a developer's real
# ~/.posthog-cli.env cannot decide the outcome of any case.
#
# Run directly:
#   zsh scripts/tests/test-upload-dsyms-posthog.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
REAL_SCRIPT="${REPO_ROOT}/scripts/upload-dsyms-posthog.sh"

if [[ ! -f "$REAL_SCRIPT" ]]; then
    echo "Cannot find scripts/upload-dsyms-posthog.sh at $REAL_SCRIPT" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

DSYM_DIR="$FIXTURE/dsyms"
mkdir -p "$DSYM_DIR/WXYC.app.dSYM/Contents/Resources/DWARF"

# Stub posthog-cli. Records argv, the project ID, and whether the key reached
# it (and whether it equals $EXPECTED_KEY) without ever writing the key out.
make_stub() {
    local stub_dir="${1:-$CASE_BIN}"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/posthog-cli" <<'STUB'
#!/bin/sh
{
    echo "argv: $*"
    echo "POSTHOG_CLI_PROJECT_ID=${POSTHOG_CLI_PROJECT_ID:-}"
    if [ -z "${POSTHOG_CLI_API_KEY:-}" ]; then
        echo "key: absent"
    elif [ "${POSTHOG_CLI_API_KEY}" = "${EXPECTED_KEY:-}" ]; then
        echo "key: expected"
    else
        echo "key: other"
    fi
} >> "$STUB_LOG"
if [ -n "${STUB_FAIL:-}" ]; then
    echo "upload rejected" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$stub_dir/posthog-cli"
}

new_case() {
    local name="$1"
    CASE_HOME="$FIXTURE/$name/home"
    CASE_BIN="$FIXTURE/$name/bin"
    mkdir -p "$CASE_HOME" "$CASE_BIN"
    STUB_LOG="$FIXTURE/$name/stub.log"
    : > "$STUB_LOG"
    STUB_FAIL=""
    CASE_SEARCH_DIRS=""
    CASE_KEY=""
    EXPECTED_KEY="env-key"
}

write_env_file() {
    print -r -- "POSTHOG_CLI_API_KEY=$1" > "$CASE_HOME/.posthog-cli.env"
}

# PATH is narrowed and POSTHOG_CLI_SEARCH_DIRS emptied so a real posthog-cli in
# /opt/homebrew/bin or /usr/local/bin cannot satisfy a "not installed" case.
run_script() {
    local -a key=()
    [[ -n "$CASE_KEY" ]] && key=("POSTHOG_CLI_API_KEY=$CASE_KEY")
    env -i \
        PATH="$CASE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$CASE_HOME" \
        DWARF_DSYM_FOLDER_PATH="$DSYM_DIR" \
        POSTHOG_CLI_SEARCH_DIRS="$CASE_SEARCH_DIRS" \
        STUB_LOG="$STUB_LOG" \
        STUB_FAIL="$STUB_FAIL" \
        EXPECTED_KEY="$EXPECTED_KEY" \
        "${key[@]}" \
        /bin/zsh "$REAL_SCRIPT" 2>&1
}

# =========================================================================
new_case "cli-missing"
CASE_KEY="env-key"
OUT=$(run_script); RC=$?
expect_exit "a missing posthog-cli exits 0" "$RC" "0" "$OUT"
expect_contains "a missing posthog-cli warns" "$OUT" "warning: posthog-cli not found"
expect_contains "the warning names the install command" "$OUT" "brew install posthog/tap/posthog-cli"
expect_eq "a missing posthog-cli calls nothing" "$(<"$STUB_LOG")" ""

new_case "cli-in-search-dir"
CASE_KEY="env-key"
make_stub "$FIXTURE/cli-in-search-dir/brew-bin"
CASE_SEARCH_DIRS="$FIXTURE/cli-in-search-dir/brew-bin"
OUT=$(run_script); RC=$?
expect_exit "a posthog-cli outside PATH but in the search dirs exits 0" "$RC" "0" "$OUT"
expect_contains "it is found and called" "$(<"$STUB_LOG")" "argv: dsym upload"

new_case "no-key-no-file"
make_stub
OUT=$(run_script); RC=$?
expect_exit "no API key exits 0" "$RC" "0" "$OUT"
expect_contains "no API key warns" "$OUT" "warning:"
expect_contains "the warning names the credential file" "$OUT" "~/.posthog-cli.env"
expect_eq "no API key calls nothing" "$(<"$STUB_LOG")" ""

new_case "key-only-in-file"
make_stub
write_env_file "env-key"
OUT=$(run_script); RC=$?
expect_exit "a key in the env file exits 0" "$RC" "0" "$OUT"
expect_contains "the key is loaded from the env file" "$(<"$STUB_LOG")" "key: expected"
expect_not_contains "the key is never echoed" "$OUT" "env-key"

new_case "env-key-wins"
make_stub
CASE_KEY="env-key"
write_env_file "file-key"
OUT=$(run_script); RC=$?
expect_exit "a key in both places exits 0" "$RC" "0" "$OUT"
expect_contains "the environment key beats the env file's" "$(<"$STUB_LOG")" "key: expected"

new_case "upload-shape"
make_stub
CASE_KEY="env-key"
OUT=$(run_script); RC=$?
expect_contains "upload argv is exactly dsym upload --directory <dir> --include-source" "$(<"$STUB_LOG")" "argv: dsym upload --directory $DSYM_DIR --include-source"$'\n'
expect_contains "the project ID is exported" "$(<"$STUB_LOG")" "POSTHOG_CLI_PROJECT_ID=134292"

new_case "upload-fails"
make_stub
CASE_KEY="env-key"
STUB_FAIL=1
OUT=$(run_script); RC=$?
expect_exit "a rejected upload exits 0" "$RC" "0" "$OUT"
expect_contains "a rejected upload warns" "$OUT" "warning:"
expect_contains "the warning carries the CLI's message" "$OUT" "upload rejected"

summarize
