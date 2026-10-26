#!/bin/zsh
#
# test-verify-posthog-floor.sh
#
# Black-box regression tests for scripts/verify-posthog-floor.sh (#1248): the
# posthog-ios floor in Shared/Analytics/Package.swift and the minimumVersion of
# the posthog-ios XCRemoteSwiftPackageReference in WXYC.xcodeproj must agree.
# Each case writes a pair of minimal fixture files and points the script at
# them with --package / --pbxproj.
#
# Run directly:
#   zsh scripts/tests/test-verify-posthog-floor.sh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
UNDER_TEST="${REPO_ROOT}/scripts/verify-posthog-floor.sh"

if [[ ! -f "$UNDER_TEST" ]]; then
    echo "Cannot find verify-posthog-floor.sh at $UNDER_TEST" >&2
    exit 2
fi

source "${REPO_ROOT}/scripts/tests/harness.zsh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wxyc-posthog-floor-test.XXXXXX") || exit 2
trap 'rm -rf "$TMP_ROOT"' EXIT

# write_fixtures <package floor> <pbxproj floor>
write_fixtures() {
    cat > "$TMP_ROOT/Package.swift" <<PKG
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "$1")),
    ],
PKG
    cat > "$TMP_ROOT/project.pbxproj" <<PBX
		AAAA /* XCRemoteSwiftPackageReference "other-package" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/example/other-package.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 9.9.9;
			};
		};
		BBBB /* XCRemoteSwiftPackageReference "posthog-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/PostHog/posthog-ios.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = $2;
			};
		};
PBX
}

run_check() {
    out=$(zsh "$UNDER_TEST" --package "$TMP_ROOT/Package.swift" --pbxproj "$TMP_ROOT/project.pbxproj" 2>&1)
    code=$?
}

write_fixtures 3.58.0 3.58.0
run_check
expect_exit "matching floors pass" "$code" 0 "$out"

write_fixtures 3.59.0 3.58.0
run_check
expect_exit "package ahead of the project fails" "$code" 1 "$out"
expect_contains "mismatch names both versions" "$out" "3.59.0"
expect_contains "mismatch names both versions (project)" "$out" "3.58.0"

write_fixtures 3.58.0 3.60.1
run_check
expect_exit "project ahead of the package fails" "$code" 1 "$out"

: > "$TMP_ROOT/project.pbxproj"
run_check
expect_exit "a missing posthog-ios reference fails" "$code" 1 "$out"

# An exact-version pin has no minimumVersion; the scan must not run on into the
# next entry and read its value.
write_fixtures 3.58.0 3.58.0
cat > "$TMP_ROOT/project.pbxproj" <<PBX
		BBBB /* XCRemoteSwiftPackageReference "posthog-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/PostHog/posthog-ios.git";
			requirement = {
				kind = exactVersion;
				version = 3.58.0;
			};
		};
		AAAA /* XCRemoteSwiftPackageReference "other-package" */ = {
			isa = XCRemoteSwiftPackageReference;
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 3.58.0;
			};
		};
PBX
run_check
expect_exit "a posthog-ios entry without minimumVersion fails" "$code" 1 "$out"
expect_contains "the missing project floor is named" "$out" "project.pbxproj"

write_fixtures 3.58.0 3.58.0
cat > "$TMP_ROOT/Package.swift" <<PKG
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", branch: "main"),
    ],
PKG
run_check
expect_exit "an unreadable Package.swift floor fails" "$code" 1 "$out"
expect_contains "the unreadable Package.swift floor is named" "$out" "Package.swift"

summarize
