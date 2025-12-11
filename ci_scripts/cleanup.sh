#!/bin/bash
set -euo pipefail

PBX="WXYC.xcodeproj/project.pbxproj"

# Make a backup
cp "$PBX" "$PBX.bak"

# Remove PBXFileReference blocks and ProjectRef lines
# Matches both the object block and the inline references

sed -i '' '
/\/\* Algorithms.xcodeproj \*\//{
    # If this is a one-line entry, delete it
    /;/d

    # Otherwise, delete the entire multiline block
    :a
    /};/!{
        N
        ba
    }
    d
}
/ProjectRef = .*Algorithms.xcodeproj/d
' "$PBX"

echo "Cleanup complete. Original saved at $PBX.bak"