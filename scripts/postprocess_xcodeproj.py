#!/usr/bin/env python3
"""
Post-process the Xcode project file to add PBXFileSystemSynchronizedBuildFileExceptionSet
for Info.plist files in synced folders.

This works around XcodeGen's lack of support for this Xcode 16 feature.
"""

import re
import uuid
import sys
from pathlib import Path


def generate_pbx_id() -> str:
    """Generate a 24-character hex ID like Xcode uses."""
    return uuid.uuid4().hex[:24].upper()


def find_synced_root_groups(content: str) -> list[tuple[str, str]]:
    """Find all PBXFileSystemSynchronizedRootGroup entries and their IDs."""
    # Match paths that may contain spaces (inside /* ... */)
    pattern = r'(\w{24}) /\* ([^*]+) \*/ = \{\s*isa = PBXFileSystemSynchronizedRootGroup;'
    matches = re.findall(pattern, content)
    # Strip whitespace from paths
    return [(id, path.strip()) for id, path in matches]


def find_target_for_synced_group(content: str, group_id: str) -> tuple[str, str] | None:
    """Find the target that uses this synced group."""
    # Look for PBXNativeTarget entries that contain this group_id in fileSystemSynchronizedGroups
    # Pattern: find the target block that contains our group_id
    target_pattern = r'(\w{24}) /\* ([^*]+) \*/ = \{\s*isa = PBXNativeTarget;[^}]*?fileSystemSynchronizedGroups = \([^)]*' + group_id + r'[^)]*\);[^}]*?name = "?([^";]+)"?;'
    match = re.search(target_pattern, content, re.DOTALL)
    if match:
        return (match.group(1), match.group(3).strip())
    return None


def find_infoplist_in_folder(project_root: Path, folder_path: str) -> str | None:
    """Check if there's an Info.plist in the folder."""
    folder = project_root / folder_path
    if not folder.exists():
        return None
    
    # Look for Info.plist or *-Info.plist
    for plist in folder.glob("*Info.plist"):
        return plist.name
    
    if (folder / "Info.plist").exists():
        return "Info.plist"
    
    return None


def add_exception_sets(content: str, project_root: Path) -> str:
    """Add PBXFileSystemSynchronizedBuildFileExceptionSet for Info.plist files."""
    
    synced_groups = find_synced_root_groups(content)
    if not synced_groups:
        print("No synced folder groups found")
        return content
    
    exception_sets = []
    group_updates = {}
    
    for group_id, folder_name in synced_groups:
        # The folder_name from the comment IS the path
        folder_path = folder_name
        plist_name = find_infoplist_in_folder(project_root, folder_path)
        
        if not plist_name:
            continue
        
        # Find the target that uses this group
        target_info = find_target_for_synced_group(content, group_id)
        if not target_info:
            continue
        
        target_id, target_name = target_info
        
        # Generate exception set
        exception_id = generate_pbx_id()
        exception_set = f'''\t\t{exception_id} /* Exceptions for "{folder_name}" folder in "{target_name}" target */ = {{
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\t{plist_name},
\t\t\t);
\t\t\ttarget = {target_id} /* {target_name} */;
\t\t}};'''
        
        exception_sets.append(exception_set)
        
        # Track which groups need to reference which exceptions
        if group_id not in group_updates:
            group_updates[group_id] = []
        group_updates[group_id].append((exception_id, folder_name, target_name))
    
    if not exception_sets:
        print("No Info.plist files found in synced folders")
        return content
    
    # Add the exception set section if it doesn't exist
    exception_section = f'''/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
{chr(10).join(exception_sets)}
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

'''
    
    # Find where to insert (before PBXFileSystemSynchronizedRootGroup section)
    insert_pattern = r'/\* Begin PBXFileSystemSynchronizedRootGroup section \*/'
    if re.search(insert_pattern, content):
        content = re.sub(insert_pattern, exception_section + r'\g<0>', content)
    else:
        # Fallback: insert before PBXFrameworksBuildPhase
        insert_pattern = r'/\* Begin PBXFrameworksBuildPhase section \*/'
        content = re.sub(insert_pattern, exception_section + r'\g<0>', content)
    
    # Update each synced root group to reference its exceptions
    for group_id, exceptions in group_updates.items():
        # Find the group definition (path may contain spaces)
        group_pattern = rf'({group_id} /\* [^*]+ \*/ = \{{\s*isa = PBXFileSystemSynchronizedRootGroup;)'
        
        # Build exceptions list
        exceptions_list = ",\n".join([
            f'\t\t\t\t{exc_id} /* Exceptions for "{folder}" folder in "{target}" target */'
            for exc_id, folder, target in exceptions
        ])
        
        exceptions_block = f'''\\1
\t\t\texceptions = (
{exceptions_list},
\t\t\t);'''
        
        content = re.sub(group_pattern, exceptions_block, content)
    
    return content


def get_project_root() -> Path:
    """Detect project root from git or script location."""
    import subprocess
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, check=True
        )
        return Path(result.stdout.strip())
    except subprocess.CalledProcessError:
        # Fallback to script's directory parent
        return Path(__file__).parent.parent.resolve()
    

def main():
    if len(sys.argv) < 2:
        project_root = get_project_root()
        project_path = project_root / "WXYC.xcodeproj" / "project.pbxproj"
    else:
        project_path = Path(sys.argv[1]).resolve()
    
    # Project root is the directory containing the .xcodeproj
    project_root = project_path.parent.parent.resolve()
    
    if not project_path.exists():
        print(f"Error: {project_path} not found")
        sys.exit(1)

    content = project_path.read_text()
    
    # Check if already processed
    if "PBXFileSystemSynchronizedBuildFileExceptionSet" in content:
        print("Info.plist exception sets already present, skipping")
        return

    new_content = add_exception_sets(content, project_root)

    if new_content != content:
        project_path.write_text(new_content)
        print("Added Info.plist exception sets to synced folders")
    else:
        print("No synced folders with Info.plist files found")


if __name__ == "__main__":
    main()
