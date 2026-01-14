#!/usr/bin/env python3
"""
Fix header comments in Swift and Metal files.

This script ensures all Swift and Metal files have a consistent header comment
following the template:

//
//  {filename}
//  {project}
//
//  Created by {author} on {date}.
//  Copyright © {year} WXYC. All rights reserved.
//

The creation date and author are obtained from git history.
Package.swift files are skipped as they require swift-tools-version on line 1.
"""

import os
import re
import subprocess
import sys
from pathlib import Path


def get_git_creation_info(filepath: str) -> tuple[str, str, str] | None:
    """Get the author, date, and year when a file was first added to git."""
    try:
        result = subprocess.run(
            [
                "git", "log", "--diff-filter=A", "--follow",
                "--format=%an|%ad", "--date=format:%m/%d/%y|%Y",
                "--", filepath
            ],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(filepath) or ".",
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        
        # Take the last line (earliest commit)
        lines = result.stdout.strip().split("\n")
        line = lines[-1]
        parts = line.split("|")
        if len(parts) >= 3:
            author = parts[0]
            date = parts[1]
            year = parts[2]
            return author, date, year
    except Exception:
        pass
    return None


def determine_project_name(filepath: str) -> str:
    """Determine the project name based on file location."""
    path = Path(filepath)
    parts = path.parts
    
    # Check if in Shared/ folder - use the package name
    try:
        shared_idx = parts.index("Shared")
        if shared_idx + 1 < len(parts):
            return parts[shared_idx + 1]
    except ValueError:
        pass
    
    # Default to WXYC
    return "WXYC"


def generate_header(filename: str, project: str, author: str, date: str, year: str) -> str:
    """Generate the standard header comment."""
    return f"""//
//  {filename}
//  {project}
//
//  Created by {author} on {date}.
//  Copyright © {year} WXYC. All rights reserved.
//
"""


def parse_existing_header(content: str) -> dict | None:
    """Parse an existing header to extract metadata if present."""
    lines = content.split("\n")
    
    # Check if file starts with comment
    if not lines or not lines[0].startswith("//"):
        return None
    
    # Find the end of the header block (first non-comment, non-empty line or double newline)
    header_end = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith("//"):
            header_end = i
            break
        # Check for blank line after comments
        if i > 0 and not stripped and not lines[i-1].strip().startswith("//"):
            header_end = i
            break
        header_end = i + 1
    
    header_lines = lines[:header_end]
    
    result = {
        "header_end": header_end,
        "filename": None,
        "project": None,
        "author": None,
        "date": None,
        "year": None,
    }
    
    for line in header_lines:
        # Match filename line: //  Filename.swift
        if match := re.match(r"^//\s+(\w+\.(swift|metal))$", line):
            result["filename"] = match.group(1)
        
        # Match project line: //  ProjectName
        if match := re.match(r"^//\s+([A-Z][A-Za-z]+)$", line):
            if result["filename"] and not result["project"]:
                result["project"] = match.group(1)
        
        # Match created by line: //  Created by Author on MM/DD/YY.
        if match := re.match(r"^//\s+Created by (.+?) on (\d{1,2}/\d{1,2}/\d{2})\.?$", line):
            result["author"] = match.group(1)
            result["date"] = match.group(2)
        
        # Match copyright line: //  Copyright © YYYY WXYC...
        if match := re.match(r"^//\s+Copyright © (\d{4})", line):
            result["year"] = match.group(1)
    
    return result


def has_correct_header(content: str, filename: str, project: str, author: str, date: str, year: str) -> bool:
    """Check if the file already has the correct header."""
    expected = generate_header(filename, project, author, date, year)
    return content.startswith(expected)


def fix_header(filepath: str, dry_run: bool = False) -> bool:
    """
    Fix the header of a single file.
    
    Returns True if the file was modified, False otherwise.
    """
    filename = os.path.basename(filepath)
    
    # Skip Package.swift files
    if filename == "Package.swift":
        return False
    
    # Get git creation info
    git_info = get_git_creation_info(filepath)
    if not git_info:
        print(f"  Warning: Could not get git info for {filepath}", file=sys.stderr)
        return False
    
    author, date, year = git_info
    project = determine_project_name(filepath)
    
    # Read current content
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Check if already correct
    if has_correct_header(content, filename, project, author, date, year):
        return False
    
    # Generate new header
    new_header = generate_header(filename, project, author, date, year)
    
    # Determine where the actual code starts
    existing = parse_existing_header(content)
    
    if existing and existing["header_end"] > 0:
        # Remove old header
        lines = content.split("\n")
        # Find where actual code starts (skip leading comments and blank lines)
        code_start = existing["header_end"]
        # Skip any additional blank lines
        while code_start < len(lines) and not lines[code_start].strip():
            code_start += 1
        
        new_content = new_header + "\n" + "\n".join(lines[code_start:])
    else:
        # No existing header, just prepend
        new_content = new_header + "\n" + content
    
    # Ensure single trailing newline
    new_content = new_content.rstrip() + "\n"
    
    if dry_run:
        print(f"  Would fix: {filepath}")
        return True
    
    # Write the file
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    print(f"  Fixed: {filepath}")
    return True


def find_swift_and_metal_files(root_dir: str) -> list[str]:
    """Find all Swift and Metal files in the directory."""
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        # Skip hidden directories and build directories
        if any(part.startswith(".") for part in Path(dirpath).parts):
            continue
        if "DerivedData" in dirpath or ".build" in dirpath:
            continue
        
        for filename in filenames:
            if filename.endswith(".swift") or filename.endswith(".metal"):
                files.append(os.path.join(dirpath, filename))
    
    return sorted(files)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix header comments in Swift and Metal files")
    parser.add_argument("--dry-run", action="store_true", help="Don't modify files, just show what would be done")
    parser.add_argument("--path", default=".", help="Root directory to search")
    args = parser.parse_args()
    
    root_dir = os.path.abspath(args.path)
    print(f"Scanning {root_dir} for Swift and Metal files...")
    
    files = find_swift_and_metal_files(root_dir)
    print(f"Found {len(files)} files to check")
    
    modified_count = 0
    modified_files = []
    
    for filepath in files:
        if fix_header(filepath, dry_run=args.dry_run):
            modified_count += 1
            modified_files.append(filepath)
    
    print(f"\n{'Would modify' if args.dry_run else 'Modified'} {modified_count} files")
    
    if modified_files and not args.dry_run:
        print("\nModified files:")
        for f in modified_files:
            print(f"  {f}")
    
    return modified_files


if __name__ == "__main__":
    main()
