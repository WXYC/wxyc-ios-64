#!/usr/bin/env python3
"""
Batch add descriptions to file headers.
Takes a file mapping descriptions to files and updates them.
"""

import re
import sys


def add_description_to_file(filepath: str, description: str) -> bool:
    """Add a description to a file's header."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"  Warning: File not found: {filepath}", file=sys.stderr)
        return False
    
    lines = content.split("\n")
    
    # Find the "Created by" line
    created_by_idx = None
    for i, line in enumerate(lines[:15]):
        if "Created by" in line:
            created_by_idx = i
            break
    
    if created_by_idx is None:
        print(f"  Warning: No 'Created by' line in {filepath}", file=sys.stderr)
        return False
    
    # Check if there's already a description (content between project line and Created by)
    # Look for lines between index 3 and created_by_idx that aren't just "//"
    has_description = False
    for i in range(4, created_by_idx):
        if lines[i].strip() not in ["//", ""]:
            has_description = True
            break
    
    if has_description:
        # Already has description, skip
        return False
    
    # Build description lines
    desc_lines = []
    for desc_line in description.split("\n"):
        if desc_line:
            desc_lines.append(f"//  {desc_line}")
        else:
            desc_lines.append("//")
    desc_lines.append("//")  # Blank line after description
    
    # Insert description before "Created by" line
    new_lines = lines[:created_by_idx] + desc_lines + lines[created_by_idx:]
    new_content = "\n".join(new_lines)
    
    # Ensure single trailing newline
    new_content = new_content.rstrip() + "\n"
    
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    return True


def main():
    # Read file descriptions from stdin or file
    # Format: filepath|description
    # Multi-line descriptions use \n
    
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            mapping_lines = f.readlines()
    else:
        mapping_lines = sys.stdin.readlines()
    
    updated_count = 0
    for line in mapping_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        
        parts = line.split("|", 1)
        if len(parts) != 2:
            continue
        
        filepath, description = parts
        description = description.replace("\\n", "\n")
        
        if add_description_to_file(filepath.strip(), description.strip()):
            print(f"  Updated: {filepath}")
            updated_count += 1
    
    print(f"\nUpdated {updated_count} files")


if __name__ == "__main__":
    main()
