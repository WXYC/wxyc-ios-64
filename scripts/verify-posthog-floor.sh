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
pbxproj_floor=$(awk '/XCRemoteSwiftPackageReference "posthog-ios"/ && /= \{/ { in_ref = 1 }
    in_ref && /minimumVersion/ { gsub(/[;= \t]|minimumVersion/, ""); print; exit }' "$pbxproj")

if [[ -z "$package_floor" || -z "$pbxproj_floor" ]]; then
    echo "Could not read the posthog-ios floor (Package.swift: '${package_floor}', project.pbxproj: '${pbxproj_floor}')." >&2
    exit 1
fi

if [[ "$package_floor" != "$pbxproj_floor" ]]; then
    echo "posthog-ios floor mismatch: Package.swift requires $package_floor, project.pbxproj requires $pbxproj_floor. Update both together." >&2
    exit 1
fi

echo "posthog-ios floor agrees: $package_floor"
