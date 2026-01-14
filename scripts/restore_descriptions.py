#!/usr/bin/env python3
"""
Restore descriptions to header comments that were lost during standardization.

This script:
1. Reads the old version of each file from HEAD^
2. Extracts any description lines from the original header
3. Updates the current file to include the description between project and "Created by"
"""

import os
import re
import subprocess
import sys
from pathlib import Path


def get_old_file_content(filepath: str) -> str | None:
    """Get the content of a file from the commit before HEAD."""
    try:
        # Get relative path from repo root
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(filepath) or ".",
        )
        repo_root = result.stdout.strip()
        rel_path = os.path.relpath(filepath, repo_root)
        
        result = subprocess.run(
            ["git", "show", f"HEAD^:{rel_path}"],
            capture_output=True,
            text=True,
            cwd=repo_root,
        )
        if result.returncode == 0:
            return result.stdout
    except Exception as e:
        print(f"  Error getting old content: {e}", file=sys.stderr)
    return None


def extract_description_from_old_header(content: str) -> list[str]:
    """
    Extract description lines from an old-style header.
    
    Old headers might look like:
    //
    //  Filename.swift
    //  Project
    //
    //  Description line 1.
    //  Description line 2.
    //
    
    Or:
    //
    //  Filename.swift
    //  Project
    //
    //  Created by Author on date.
    //  Some other info
    //
    
    We want to extract description lines that aren't "Created by" or "Copyright" or "Translated from".
    """
    lines = content.split("\n")
    
    # Find the header block
    if not lines or not lines[0].strip() == "//":
        return []
    
    description_lines = []
    in_header = True
    found_project = False
    past_first_blank = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # End of header block
        if stripped and not stripped.startswith("//"):
            break
        
        # Skip first line (just //)
        if i == 0:
            continue
            
        # Skip filename line (//  Something.swift or //  Something.metal)
        if re.match(r"^//\s+\w+\.(swift|metal)$", line):
            continue
        
        # Check for project line (//  ProjectName - single capitalized word)
        if re.match(r"^//\s+[A-Z][A-Za-z0-9]+$", line) and not found_project:
            found_project = True
            continue
        
        # Skip empty comment lines before description
        if stripped == "//" and not past_first_blank and found_project:
            past_first_blank = True
            continue
        
        # Skip "Created by" lines
        if "Created by" in line:
            continue
        
        # Skip "Copyright" lines
        if "Copyright" in line:
            continue
            
        # Skip "Translated from" lines (but we might want to keep these as descriptions)
        # Actually, let's keep these as they're useful context
        
        # Skip trailing empty comment line
        if stripped == "//" and i > 0:
            # Check if next non-empty line is not a comment
            for j in range(i + 1, min(i + 3, len(lines))):
                next_stripped = lines[j].strip()
                if next_stripped and not next_stripped.startswith("//"):
                    break
                if next_stripped.startswith("//") and next_stripped != "//":
                    # More comment content coming, this is just a separator
                    break
            else:
                continue
        
        # If we have content after finding project, it's a description
        if found_project and past_first_blank:
            # Extract the comment content
            if stripped.startswith("//"):
                content_part = line[2:].strip() if len(line) > 2 else ""
                if content_part or (description_lines and stripped == "//"):
                    # Keep non-empty lines or blank lines in the middle of description
                    if content_part:
                        description_lines.append(content_part)
                    elif description_lines:  # blank line in middle
                        description_lines.append("")
    
    # Remove trailing empty lines from description
    while description_lines and not description_lines[-1]:
        description_lines.pop()
    
    return description_lines


def update_file_with_description(filepath: str, description_lines: list[str]) -> bool:
    """
    Update a file's header to include description lines.
    
    Current format:
    //
    //  Filename.swift
    //  Project
    //
    //  Created by Author on date.
    //  Copyright © year WXYC. All rights reserved.
    //
    
    New format:
    //
    //  Filename.swift
    //  Project
    //
    //  Description line 1.
    //  Description line 2.
    //
    //  Created by Author on date.
    //  Copyright © year WXYC. All rights reserved.
    //
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    lines = content.split("\n")
    
    # Find the structure of current header
    # Line 0: //
    # Line 1: //  Filename.swift
    # Line 2: //  Project
    # Line 3: //
    # Line 4: //  Created by...
    # Line 5: //  Copyright...
    # Line 6: //
    
    # We need to insert description after line 3 (the blank //) and before line 4 (Created by)
    
    # Find the "Created by" line
    created_by_idx = None
    for i, line in enumerate(lines[:10]):  # Only check first 10 lines
        if "Created by" in line:
            created_by_idx = i
            break
    
    if created_by_idx is None:
        print(f"  Warning: Could not find 'Created by' line in {filepath}", file=sys.stderr)
        return False
    
    # Build description comment block
    desc_block = []
    for desc_line in description_lines:
        if desc_line:
            desc_block.append(f"//  {desc_line}")
        else:
            desc_block.append("//")
    desc_block.append("//")  # Blank line after description
    
    # Insert description before "Created by" line
    new_lines = lines[:created_by_idx] + desc_block + lines[created_by_idx:]
    
    new_content = "\n".join(new_lines)
    
    # Ensure single trailing newline
    new_content = new_content.rstrip() + "\n"
    
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    return True


def find_modified_files() -> list[str]:
    """Find all Swift and Metal files modified in the last commit."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD^", "HEAD", "--", "*.swift", "*.metal"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    
    files = []
    for line in result.stdout.strip().split("\n"):
        if line and (line.endswith(".swift") or line.endswith(".metal")):
            files.append(line)
    return files


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Restore descriptions to header comments")
    parser.add_argument("--dry-run", action="store_true", help="Don't modify files")
    args = parser.parse_args()
    
    # Get repo root
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    repo_root = result.stdout.strip()
    os.chdir(repo_root)
    
    print("Finding modified files...")
    files = find_modified_files()
    print(f"Found {len(files)} modified files")
    
    restored_count = 0
    no_description_files = []
    
    for filepath in files:
        if os.path.basename(filepath) == "Package.swift":
            continue
            
        full_path = os.path.join(repo_root, filepath)
        if not os.path.exists(full_path):
            continue
        
        # Get old content
        old_content = get_old_file_content(full_path)
        if not old_content:
            continue
        
        # Extract description
        description = extract_description_from_old_header(old_content)
        
        if description:
            if args.dry_run:
                print(f"  Would restore description in: {filepath}")
                for line in description:
                    print(f"    {line}")
            else:
                if update_file_with_description(full_path, description):
                    print(f"  Restored description in: {filepath}")
                    restored_count += 1
        else:
            no_description_files.append(filepath)
    
    print(f"\n{'Would restore' if args.dry_run else 'Restored'} descriptions in {restored_count} files")
    print(f"Files without original descriptions: {len(no_description_files)}")
    
    if no_description_files and not args.dry_run:
        print("\nFiles that need descriptions added:")
        for f in no_description_files[:20]:
            print(f"  {f}")
        if len(no_description_files) > 20:
            print(f"  ... and {len(no_description_files) - 20} more")
    
    return no_description_files


if __name__ == "__main__":
    main()
