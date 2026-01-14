#!/bin/bash
#
# Pre-commit hook that reverts whitespace-only line changes.
# If a line was pure whitespace (spaces, tabs, or empty) and is being
# changed to different pure whitespace, this hook reverts that change.

# Get list of staged files (excluding deleted files)
staged_files=$(git diff --cached --name-only --diff-filter=d)

if [ -z "$staged_files" ]; then
    exit 0
fi

# Track if we made any changes
made_changes=0

for file in $staged_files; do
    # Skip binary files
    if ! git diff --cached --numstat "$file" | grep -q "^[0-9]"; then
        continue
    fi

    # Skip if file doesn't exist in HEAD (new file)
    if ! git cat-file -e HEAD:"$file" 2>/dev/null; then
        continue
    fi

    # Get the staged content and HEAD content
    staged_content=$(git show :"$file")
    head_content=$(git show HEAD:"$file")

    # Create temp files for comparison
    staged_tmp=$(mktemp)
    head_tmp=$(mktemp)
    result_tmp=$(mktemp)

    echo "$staged_content" > "$staged_tmp"
    echo "$head_content" > "$head_tmp"

    # Process line by line using awk
    # For each line: if HEAD line is whitespace-only AND staged line is whitespace-only
    # AND they differ, use the HEAD version
    awk '
    BEGIN {
        # Read HEAD file into array
        line_num = 0
        while ((getline line < "'"$head_tmp"'") > 0) {
            line_num++
            head_lines[line_num] = line
        }
        head_count = line_num
    }
    {
        staged_line = $0
        head_line = head_lines[NR]

        # Check if both lines are whitespace-only (empty or only spaces/tabs)
        staged_is_ws = (staged_line ~ /^[[:space:]]*$/)
        head_is_ws = (head_line ~ /^[[:space:]]*$/)

        if (staged_is_ws && head_is_ws && staged_line != head_line) {
            # Both are whitespace-only but different - use HEAD version
            print head_line
            changed = 1
        } else {
            print staged_line
        }
    }
    END {
        # Handle case where staged file is shorter than HEAD
        # (lines were deleted - not our concern for whitespace)
    }
    ' "$staged_tmp" > "$result_tmp"

    # Check if result differs from staged
    if ! diff -q "$staged_tmp" "$result_tmp" > /dev/null 2>&1; then
        # Content was modified - update the staged file
        cp "$result_tmp" "$file"
        git add "$file"
        made_changes=1
        echo "Pre-commit: Reverted whitespace-only line changes in $file"
    fi

    # Clean up temp files
    rm -f "$staged_tmp" "$head_tmp" "$result_tmp"
done

if [ "$made_changes" -eq 1 ]; then
    echo "Pre-commit: Some whitespace-only line changes were reverted."
fi

exit 0
