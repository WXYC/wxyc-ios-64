#!/bin/bash
#
# Pre-commit hook that ensures Swift and Metal files have proper header comments
# with descriptions. Uses Claude to generate descriptions for files missing them.

REPO_ROOT=$(git rev-parse --show-toplevel)

# Get list of staged Swift and Metal files (excluding deleted files)
staged_files=$(git diff --cached --name-only --diff-filter=d | grep -E '\.(swift|metal)$' || true)

if [ -z "$staged_files" ]; then
    exit 0
fi

# Check if claude is available
if ! command -v claude &> /dev/null; then
    echo "Pre-commit: Warning - 'claude' CLI not found, skipping header description check"
    exit 0
fi

files_fixed=0

for file in $staged_files; do
    # Skip Package.swift files
    if [[ "$(basename "$file")" == "Package.swift" ]]; then
        continue
    fi
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        continue
    fi
    
    # Read the first 15 lines to check header structure
    header=$(head -15 "$file")
    
    # Check if file starts with a comment header
    if ! echo "$header" | head -1 | grep -q '^//$'; then
        echo "Pre-commit: Warning - $file doesn't have standard header format, skipping"
        continue
    fi
    
    # Check if there's a "Created by" line
    created_line=$(echo "$header" | grep -n "Created by" | head -1 | cut -d: -f1)
    if [ -z "$created_line" ]; then
        echo "Pre-commit: Warning - $file missing 'Created by' line, skipping"
        continue
    fi
    
    # Check if there's a description between line 4 and "Created by"
    # Line 1: //
    # Line 2: //  Filename
    # Line 3: //  Project
    # Line 4: //
    # Line 5+: Description (if present)
    # Line N: //  Created by...
    
    has_description=false
    
    # Look for non-empty comment lines between line 4 and Created by line
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip lines 1-4 (standard header prefix)
        if [ $line_num -le 4 ]; then
            continue
        fi
        
        # Stop before Created by line
        if [ $line_num -ge $created_line ]; then
            break
        fi
        
        # Check if this line has content (not just "//")
        stripped=$(echo "$line" | sed 's/^\/\///' | sed 's/^[[:space:]]*//')
        if [ -n "$stripped" ]; then
            has_description=true
            break
        fi
    done < <(head -$created_line "$file")
    
    if [ "$has_description" = true ]; then
        # File already has a description
        continue
    fi
    
    echo "Pre-commit: Adding description to $file using Claude..."
    
    # Use Claude to add a description
    # --dangerously-skip-permissions allows file modification without prompts
    # --print for non-interactive mode
    claude --dangerously-skip-permissions --print \
        "This file is missing a description in its header comment. Please read the file and add a brief 1-2 line description explaining what this file does and how it fits into its package/module. The description should go between line 4 (the blank // after the project name) and the 'Created by' line. Only modify the header - do not change any code. File: $file" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Re-stage the file if it was modified
        if git diff --quiet "$file" 2>/dev/null; then
            : # No changes
        else
            git add "$file"
            files_fixed=$((files_fixed + 1))
            echo "Pre-commit: Added description to $file"
        fi
    else
        echo "Pre-commit: Warning - Failed to add description to $file"
    fi
done

if [ $files_fixed -gt 0 ]; then
    echo "Pre-commit: Added descriptions to $files_fixed file(s)"
fi

exit 0
