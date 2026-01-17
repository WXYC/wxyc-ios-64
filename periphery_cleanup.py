#!/usr/bin/env python3
"""
Periphery Cleanup Script

Parses periphery-results.json and applies fixes to address unused code,
redundant access modifiers, and other issues detected by Periphery.

Usage:
    python periphery_cleanup.py --dry-run                    # Preview all changes
    python periphery_cleanup.py --hint unused --kind module  # Remove unused imports only
    python periphery_cleanup.py --hint redundantPublicAccessibility  # Fix access modifiers
    python periphery_cleanup.py --hint unused                # Remove all unused code
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Issue:
    """Represents a single Periphery issue."""
    hint: str
    kind: str
    name: str
    location: str
    file_path: str
    line: int
    column: int
    modules: list[str]
    accessibility: str
    modifiers: list[str]
    
    @classmethod
    def from_json(cls, data: dict) -> "Issue":
        location = data.get("location", "")
        parts = location.split(":")
        file_path = parts[0] if parts else ""
        line = int(parts[1]) if len(parts) > 1 else 0
        column = int(parts[2]) if len(parts) > 2 else 0
        
        hints = data.get("hints", [])
        hint = hints[0] if hints else ""
        
        return cls(
            hint=hint,
            kind=data.get("kind", ""),
            name=data.get("name", ""),
            location=location,
            file_path=file_path,
            line=line,
            column=column,
            modules=data.get("modules", []),
            accessibility=data.get("accessibility", ""),
            modifiers=data.get("modifiers", []),
        )


def get_project_root() -> str:
    """Detect project root from git or script location."""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        # Fallback to script's directory
        return os.path.dirname(os.path.abspath(__file__))

    
class PeripheryCleanup:
    """Main class for applying Periphery fixes."""

    PROJECT_ROOT = get_project_root()
    XCODEPROJ = "WXYC.xcodeproj"
    
    # Paths to exclude from modifications
    EXCLUDED_PATHS = [
        "/Vendor/",
        "/LaminatedGlass/",
        "/Secrets/",  # Cannot modify Secrets module
    ]
    
    # Files to skip entirely
    EXCLUDED_FILES = [
        # None currently - use EXCLUDED_PATHS for directory-level exclusions
    ]
    
    def __init__(self, json_path: str, dry_run: bool = True, verbose: bool = False):
        self.json_path = json_path
        self.dry_run = dry_run
        self.verbose = verbose
        self.issues: list[Issue] = []
        self.changes_made: list[str] = []
        self.failed_files: list[str] = []
        self.skipped_issues: list[Issue] = []
        
    def load_issues(self) -> None:
        """Load and parse the periphery results JSON."""
        with open(self.json_path, "r") as f:
            data = json.load(f)
        
        for item in data:
            issue = Issue.from_json(item)
            
            # Filter to only project files
            if not issue.file_path.startswith(self.PROJECT_ROOT):
                continue
                
            # Skip excluded paths
            if any(excl in issue.file_path for excl in self.EXCLUDED_PATHS):
                self.skipped_issues.append(issue)
                continue
                
            # Skip excluded files
            if any(issue.file_path.endswith(excl) for excl in self.EXCLUDED_FILES):
                self.skipped_issues.append(issue)
                continue
            
            self.issues.append(issue)
        
        print(f"Loaded {len(self.issues)} issues ({len(self.skipped_issues)} skipped)")
    
    def group_by_file(self) -> dict[str, list[Issue]]:
        """Group issues by file path."""
        grouped = defaultdict(list)
        for issue in self.issues:
            grouped[issue.file_path].append(issue)
        
        # Sort issues within each file by line number descending
        # This ensures we process from bottom to top, avoiding line number shifts
        for file_path in grouped:
            grouped[file_path].sort(key=lambda x: x.line, reverse=True)
    
        return dict(grouped)
    
    def filter_issues(self, hint: Optional[str] = None, kind: Optional[str] = None) -> list[Issue]:
        """Filter issues by hint type and/or kind."""
        filtered = self.issues
        
        if hint:
            filtered = [i for i in filtered if i.hint == hint]
        if kind:
            filtered = [i for i in filtered if i.kind == kind]
        
        return filtered
    
    def read_file(self, file_path: str) -> list[str]:
        """Read a file and return its lines."""
        with open(file_path, "r") as f:
            return f.readlines()
    
    def write_file(self, file_path: str, lines: list[str]) -> None:
        """Write lines back to a file."""
        with open(file_path, "w") as f:
            f.writelines(lines)
    
    def backup_file(self, file_path: str) -> str:
        """Create a backup of the file and return backup path."""
        backup_path = file_path + ".bak"
        with open(file_path, "r") as src:
            with open(backup_path, "w") as dst:
                dst.write(src.read())
        return backup_path
    
    def restore_file(self, file_path: str, backup_path: str) -> None:
        """Restore a file from its backup."""
        with open(backup_path, "r") as src:
            with open(file_path, "w") as dst:
                dst.write(src.read())
        os.remove(backup_path)
    
    def build_project(self) -> bool:
        """Build the Xcode project and return True if successful."""
        cmd = [
            "xcodebuild",
            "-project", os.path.join(self.PROJECT_ROOT, self.XCODEPROJ),
            "-scheme", "WXYC",
            "-destination", "generic/platform=iOS Simulator",
            "-quiet",
            "build"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode == 0
    
    def fix_unused_import(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove an unused import statement."""
        line_idx = issue.line - 1  # Convert to 0-based index
        
        if line_idx >= len(lines):
            return lines, False
        
        line = lines[line_idx]
    
        # Verify this is an import line
        import_pattern = rf"^\s*import\s+{re.escape(issue.name)}\s*$"
        if not re.match(import_pattern, line):
            if self.verbose:
                print(f"  Warning: Line {issue.line} doesn't match expected import pattern")
                print(f"    Expected: import {issue.name}")
                print(f"    Found: {line.strip()}")
            return lines, False
        
        # Remove the line
        new_lines = lines[:line_idx] + lines[line_idx + 1:]
        return new_lines, True
        
    def fix_redundant_public(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove redundant 'public' access modifier."""
        line_idx = issue.line - 1
        
        if line_idx >= len(lines):
            return lines, False
        
        line = lines[line_idx]
        
        # Replace 'public ' with empty string (or 'internal ' if you prefer explicit)
        # Handle various patterns: 'public class', 'public func', 'public var', etc.
        new_line = re.sub(r'\bpublic\s+', '', line, count=1)
        
        if new_line == line:
            if self.verbose:
                print(f"  Warning: No 'public' found on line {issue.line}")
            return lines, False
        
        lines[line_idx] = new_line
        return lines, True
        
    def fix_assign_only_property(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove a property that is only assigned but never read."""
        line_idx = issue.line - 1
        
        if line_idx >= len(lines):
            return lines, False
        
        line = lines[line_idx]
        
        # Check if this is a simple single-line property
        # Pattern: (let|var) propertyName: Type = value or (let|var) propertyName: Type
        property_pattern = rf'^\s*(public\s+|private\s+|internal\s+|fileprivate\s+)?(let|var)\s+{re.escape(issue.name)}\s*[:\=]'
        
        if not re.search(property_pattern, line):
            if self.verbose:
                print(f"  Warning: Line {issue.line} doesn't match property pattern for '{issue.name}'")
            return lines, False
        
        # Check if it spans multiple lines (has an opening brace for computed property)
        if '{' in line and '}' not in line:
            # Multi-line property/computed property - find closing brace
            brace_count = line.count('{') - line.count('}')
            end_idx = line_idx + 1
            
            while end_idx < len(lines) and brace_count > 0:
                brace_count += lines[end_idx].count('{') - lines[end_idx].count('}')
                end_idx += 1
            
            new_lines = lines[:line_idx] + lines[end_idx:]
        else:
            # Single line property
            new_lines = lines[:line_idx] + lines[line_idx + 1:]
        
        return new_lines, True
    
    def fix_unused_declaration(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove an unused declaration (function, class, struct, enum, etc.)."""
        line_idx = issue.line - 1
        
        if line_idx >= len(lines):
            return lines, False
        
        line = lines[line_idx]
        kind = issue.kind
        
        # Handle different kinds of declarations
        if kind == "module":
            # This is an unused import
            return self.fix_unused_import(lines, issue)
        
        if kind in ("var.instance", "var.static", "var.global", "var.parameter"):
            # For parameters, we typically can't just remove them
            if kind == "var.parameter":
                # Prefix with _ to suppress warning instead of removing
                # This is safer than removing the parameter
                if self.verbose:
                    print(f"  Skipping parameter '{issue.name}' - consider prefixing with _")
                return lines, False
            return self.fix_assign_only_property(lines, issue)
        
        # For types and functions, we need to find the closing brace
        if kind in ("struct", "class", "enum", "protocol", "function.method.instance", 
                    "function.method.static", "function.method.class", "function.free",
                    "function.constructor", "function.operator.infix", "function.subscript"):
            
            # Find the opening brace
            brace_idx = line_idx
            while brace_idx < len(lines) and '{' not in lines[brace_idx]:
                brace_idx += 1
            
            if brace_idx >= len(lines):
                if self.verbose:
                    print(f"  Warning: Could not find opening brace for {kind} '{issue.name}'")
                return lines, False
            
            # Count braces to find the end
            brace_count = 0
            end_idx = line_idx
            
            for i in range(line_idx, len(lines)):
                brace_count += lines[i].count('{') - lines[i].count('}')
                if brace_count == 0 and '{' in lines[i]:
                    # Found a complete block that opened and closed on same line
                    end_idx = i + 1
                    break
                elif brace_count == 0 and i > brace_idx:
                    end_idx = i + 1
                    break
                end_idx = i + 1
        
            # Remove any leading blank line if present before the declaration
            start_idx = line_idx
            if start_idx > 0 and lines[start_idx - 1].strip() == '':
                start_idx -= 1
        
            new_lines = lines[:start_idx] + lines[end_idx:]
            return new_lines, True
        
        if kind == "enumelement":
            # Enum case - just remove the line
            new_lines = lines[:line_idx] + lines[line_idx + 1:]
            return new_lines, True
        
        if kind == "typealias":
            # Type alias - single line
            new_lines = lines[:line_idx] + lines[line_idx + 1:]
            return new_lines, True
        
        if self.verbose:
            print(f"  Warning: Unknown kind '{kind}' for '{issue.name}'")
        return lines, False
        
    def fix_redundant_conformance(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove a redundant protocol conformance."""
        line_idx = issue.line - 1
        
        if line_idx >= len(lines):
            return lines, False
        
        line = lines[line_idx]
        
        # Pattern: Remove ", ProtocolName" or ": ProtocolName" 
        # This is tricky because we need to handle various cases
        protocol_name = issue.name
        
        # Try removing ", ProtocolName"
        new_line = re.sub(rf',\s*{re.escape(protocol_name)}(?=\s*[,{{]|\s*$)', '', line)
        if new_line != line:
            lines[line_idx] = new_line
            return lines, True
        
        # Try removing ": ProtocolName" when it's the only conformance
        new_line = re.sub(rf':\s*{re.escape(protocol_name)}(?=\s*{{)', '', line)
        if new_line != line:
            lines[line_idx] = new_line
            return lines, True
        
        if self.verbose:
            print(f"  Warning: Could not remove conformance to '{protocol_name}'")
        return lines, False
    
    def fix_redundant_protocol(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Remove a redundant protocol definition."""
        return self.fix_unused_declaration(lines, issue)
        
    def apply_fix(self, lines: list[str], issue: Issue) -> tuple[list[str], bool]:
        """Apply the appropriate fix for an issue."""
        hint = issue.hint
        
        if hint == "unused":
            if issue.kind == "module":
                return self.fix_unused_import(lines, issue)
            else:
                return self.fix_unused_declaration(lines, issue)
        
        elif hint == "redundantPublicAccessibility":
            return self.fix_redundant_public(lines, issue)
        
        elif hint == "assignOnlyProperty":
            return self.fix_assign_only_property(lines, issue)
        
        elif hint == "redundantConformance":
            return self.fix_redundant_conformance(lines, issue)
        
        elif hint == "redundantProtocol":
            return self.fix_redundant_protocol(lines, issue)
        
        else:
            if self.verbose:
                print(f"  Unknown hint type: {hint}")
            return lines, False
        
    def process_file(self, file_path: str, issues: list[Issue]) -> bool:
        """Process all issues in a single file."""
        print(f"\nProcessing {file_path}")
        print(f"  {len(issues)} issues to fix")
        
        if not os.path.exists(file_path):
            print(f"  ERROR: File does not exist")
            return False
        
        # Read the file
        lines = self.read_file(file_path)
        original_lines = lines.copy()
        
        # Apply each fix (issues are already sorted by line descending)
        fixes_applied = 0
        for issue in issues:
            if self.verbose:
                print(f"  Fixing {issue.hint} '{issue.name}' at line {issue.line}")
            
            lines, success = self.apply_fix(lines, issue)
            if success:
                fixes_applied += 1
                self.changes_made.append(f"{file_path}:{issue.line} - {issue.hint} {issue.kind} '{issue.name}'")
            else:
                if self.verbose:
                    print(f"    Could not apply fix")
        
        if fixes_applied == 0:
            print(f"  No fixes applied")
            return True
        
        print(f"  Applied {fixes_applied}/{len(issues)} fixes")
        
        if self.dry_run:
            print(f"  [DRY RUN] Would write changes")
            return True
        
        # Write changes and verify build
        backup_path = self.backup_file(file_path)
        self.write_file(file_path, lines)
        
        print(f"  Building to verify...")
        if self.build_project():
            print(f"  Build successful")
            os.remove(backup_path)
            return True
        else:
            print(f"  Build FAILED - reverting changes")
            self.restore_file(file_path, backup_path)
            self.failed_files.append(file_path)
            return False
    
    def run(self, hint: Optional[str] = None, kind: Optional[str] = None) -> None:
        """Run the cleanup process."""
        print(f"Periphery Cleanup Script")
        print(f"========================")
        print(f"Dry run: {self.dry_run}")
        print(f"Filter - hint: {hint or 'all'}, kind: {kind or 'all'}")
        print()
        
        self.load_issues()
        
        # Filter issues if requested
        if hint or kind:
            self.issues = self.filter_issues(hint, kind)
            print(f"Filtered to {len(self.issues)} issues")
        
        # Group by file
        grouped = self.group_by_file()
        print(f"Issues span {len(grouped)} files")
        
        # Process each file
        for file_path in sorted(grouped.keys()):
            issues = grouped[file_path]
            self.process_file(file_path, issues)
        
        # Summary
        print()
        print("=" * 60)
        print("SUMMARY")
        print("=" * 60)
        print(f"Total changes made: {len(self.changes_made)}")
        print(f"Failed files: {len(self.failed_files)}")
        print(f"Skipped issues (Vendor/Secrets): {len(self.skipped_issues)}")
        
        if self.failed_files:
            print("\nFailed files:")
            for f in self.failed_files:
                print(f"  - {f}")
        
        if self.verbose and self.changes_made:
            print("\nChanges made:")
            for change in self.changes_made:
                print(f"  - {change}")
    

def main():
    parser = argparse.ArgumentParser(description="Clean up Periphery issues")
    parser.add_argument("--json", default="periphery-results.json", help="Path to periphery results JSON")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without modifying files")
    parser.add_argument("--hint", help="Filter by hint type (unused, redundantPublicAccessibility, etc.)")
    parser.add_argument("--kind", help="Filter by kind (module, function.method.instance, etc.)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

    args = parser.parse_args()

    json_path = os.path.join(get_project_root(), args.json)

    cleanup = PeripheryCleanup(json_path, dry_run=args.dry_run, verbose=args.verbose)
    cleanup.run(hint=args.hint, kind=args.kind)


if __name__ == "__main__":
    main()
