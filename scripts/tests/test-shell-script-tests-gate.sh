#!/bin/zsh
#
# test-shell-script-tests-gate.sh
#
# Black-box regression tests for scripts/shell-script-tests-gate.sh (#1250): the
# gate that decides whether the macOS job in shell-script-tests.yml runs. Each
# case builds a throwaway git repo, commits a change on top of a base commit,
# and asks the gate about base..HEAD.
#
# Run directly:
#   zsh scripts/tests/test-shell-script-tests-gate.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
UNDER_TEST="${REPO_ROOT}/scripts/shell-script-tests-gate.sh"

if [[ ! -f "$UNDER_TEST" ]]; then
    echo "Cannot find shell-script-tests-gate.sh at $UNDER_TEST" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wxyc-gate-test.XXXXXX") || exit 2
trap 'rm -rf "$TMP_ROOT"' EXIT

PBX=WXYC.xcodeproj/project.pbxproj

# write_pbxproj <posthog floor> <extra line>
write_pbxproj() {
    mkdir -p WXYC.xcodeproj
    cat > $PBX <<PBXEOF
		AAAA /* PBXBuildFile */ = {isa = PBXBuildFile; $2 };
		BBBB /* XCRemoteSwiftPackageReference "posthog-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/PostHog/posthog-ios.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = $1;
			};
		};
PBXEOF
}

# gate <description> <expected> <setup function run between base and head>
gate() {
    local desc="$1" expected="$2" change="$3"
    local repo="$TMP_ROOT/repo"
    rm -rf "$repo"; mkdir "$repo"; cd "$repo"
    git init -q . && git config user.email t@t && git config user.name t
    mkdir -p scripts docs Shared/Analytics
    write_pbxproj 3.58.0 "fileRef = 1;"
    echo base > scripts/a.sh; echo base > docs/a.md; echo base > Shared/Analytics/Package.swift
    git add -A && git commit -qm base
    local base=$(git rev-parse HEAD)
    eval "$change"
    git add -A && git commit -qm head
    local out; out=$(sh "$UNDER_TEST" "$base" HEAD 2>&1)
    expect_eq "$desc" "$out" "$expected"
    cd "$REPO_ROOT"
}

gate "adding a file to a target in the pbxproj does not run macOS" false 'write_pbxproj 3.58.0 "fileRef = 2;"'
gate "raising the posthog-ios requirement in the pbxproj runs macOS" true 'write_pbxproj 3.59.0 "fileRef = 1;"'
gate "a change under scripts/ runs macOS" true 'echo head > scripts/a.sh'
gate "a change to Package.swift runs macOS" true 'echo head > Shared/Analytics/Package.swift'
gate "a script change alongside an unrelated pbxproj edit runs macOS" true 'echo head > scripts/a.sh; write_pbxproj 3.58.0 "fileRef = 2;"'
gate "a change outside the filter does not run macOS" false 'echo head > docs/a.md'

summarize
