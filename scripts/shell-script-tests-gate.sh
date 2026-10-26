#!/bin/sh
#
# shell-script-tests-gate.sh
#
# Prints "true" when the macOS job in .github/workflows/shell-script-tests.yml
# should run for the changes between <base> and <head>, "false" otherwise (#1250).
# The workflow's path filter admits every pbxproj edit so a posthog-ios
# requirement change is seen; this gate drops the ones that leave that
# requirement alone. Plain POSIX sh so the ubuntu pre-job can run it.
#
# Usage:
#   scripts/shell-script-tests-gate.sh <base> <head>

set -eu

base="$1"
head="$2"
pbxproj=WXYC.xcodeproj/project.pbxproj

files=$(git diff --name-only "$base" "$head")

# Everything in the workflow's filter except the pbxproj.
if printf '%s\n' "$files" | grep -Eq '^(\.github/scripts/|scripts/|ci_scripts/|Shared/Analytics/Package\.swift$|\.github/workflows/shell-script-tests\.yml$)'; then
    echo true
    exit 0
fi

# The posthog-ios reference entry, which ends at the first "};" at entry depth.
posthog_entry() {
    git show "$1:$pbxproj" 2>/dev/null | sed -n '/XCRemoteSwiftPackageReference "posthog-ios" \*\/ = {/,/^\t\t};/p' || true
}

if printf '%s\n' "$files" | grep -Fxq "$pbxproj" && [ "$(posthog_entry "$base")" != "$(posthog_entry "$head")" ]; then
    echo true
else
    echo false
fi
