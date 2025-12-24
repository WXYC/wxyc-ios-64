#!/bin/bash
set -euo pipefail

PBX="WXYC.xcodeproj/project.pbxproj"

if [[ ! -f "$PBX" ]]; then
  echo "Error: Cannot find $PBX"
  exit 1
fi

# Create backup
BACKUP="$PBX.backup.$(date +%s)"
cp "$PBX" "$BACKUP"
echo "Backup created at: $BACKUP"

# Extract all .xcodeproj references from the PBX file
PROJECT_REFS=$(grep -oE '[A-Za-z0-9_./-]+\.xcodeproj' "$PBX" | sort -u)

if [[ -z "$PROJECT_REFS" ]]; then
  echo "No subproject references found."
  exit 0
fi

echo "Found subproject references:"
echo "$PROJECT_REFS"
echo

REMOVED=0

for REF in $PROJECT_REFS; do
  if [[ ! -d "$REF" ]]; then
    echo "❌ Missing subproject detected: $REF"
    echo "   → Removing from project.pbxproj"

    # Remove PBXFileReference blocks and inline references
    sed -i '' "
      /\/\* $(basename "$REF") \*\//{
        /;/d
        :a
        /};/!{
            N
            ba
        }
        d
      }
      /ProjectRef = .*$(basename "$REF")/d
    " "$PBX"

    ((REMOVED++))
  else
    echo "✅ Found on disk: $REF (kept)"
  fi
done

echo
echo "Cleanup complete. Removed $REMOVED missing subprojects."
echo "Project file updated: $PBX"

