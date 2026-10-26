#!/bin/zsh
#
# verify-posthog-floor.sh
# WXYC
#
# Fails when the posthog-ios version floor in Shared/Analytics/Package.swift
# differs from the minimumVersion of the posthog-ios
# XCRemoteSwiftPackageReference in WXYC.xcodeproj/project.pbxproj (#1248). The
# Xcode project cannot read a Swift package floor, so the two are kept in step
# by this check rather than by a single source.
#
# Usage:
#   scripts/verify-posthog-floor.sh [--package <Package.swift>] [--pbxproj <project.pbxproj>]
#
# Exit codes: 0 = floors agree. 1 = they differ or one could not be found.
#

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
package="$REPO_ROOT/Shared/Analytics/Package.swift"
pbxproj="$REPO_ROOT/WXYC.xcodeproj/project.pbxproj"

while (( $# > 0 )); do
    case "$1" in
        --package) package="$2"; shift 2 ;;
        --pbxproj) pbxproj="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

package_floor=$(sed -nE '/posthog-ios/ s/.*from: "([0-9.]+)".*/\1/p' "$package" | head -1)
# Scan only the posthog-ios entry: track brace depth from its opening line so an
# entry without minimumVersion (an exact-version pin) cannot read the next one.
pbxproj_floor=$(awk '
    !in_ref && /XCRemoteSwiftPackageReference "posthog-ios"/ && /= \{/ { in_ref = 1; depth = 0 }
    in_ref {
        if (/minimumVersion/) { v = $0; gsub(/[;= \t]|minimumVersion/, "", v); print v; exit }
        n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m
        if (depth <= 0) { exit }
    }' "$pbxproj")

if [[ -z "$package_floor" ]]; then
    echo "Could not read the posthog-ios floor from $package (expected a 'from: \"x.y.z\"' requirement on the posthog-ios dependency)." >&2
    exit 1
fi

if [[ -z "$pbxproj_floor" ]]; then
    echo "Could not read the posthog-ios minimumVersion from $pbxproj (no posthog-ios XCRemoteSwiftPackageReference with a minimumVersion)." >&2
    exit 1
fi

if [[ "$package_floor" != "$pbxproj_floor" ]]; then
    echo "posthog-ios floor mismatch: Package.swift requires $package_floor, project.pbxproj requires $pbxproj_floor. Update both together." >&2
    exit 1
fi

echo "posthog-ios floor agrees: $package_floor"
