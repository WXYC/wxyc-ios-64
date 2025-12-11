#!/usr/bin/env ruby
# Deep cleanup of the Xcode project structure
# Removes all empty groups and consolidates synced folders

require 'xcodeproj'
require 'set'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"

# Collect all synced folders
synced_folders = []
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    synced_folders << obj
  end
end

puts "\nFound #{synced_folders.length} synced folders:"
synced_folders.each { |sf| puts "  - #{sf.path}" }

# Collect all unique synced folder paths
unique_paths = synced_folders.map(&:path).uniq
puts "\nUnique synced folder paths: #{unique_paths.length}"

# Remove duplicate synced folders (keep one of each path)
path_to_folder = {}
synced_folders.each do |sf|
  if path_to_folder[sf.path]
    puts "Removing duplicate synced folder: #{sf.path}"
    sf.remove_from_project
  else
    path_to_folder[sf.path] = sf
  end
end

# Recursive function to remove empty groups
def remove_empty_groups(group, depth = 0)
  return unless group.respond_to?(:children)
  
  # First, recursively clean children
  group.children.to_a.each do |child|
    if child.isa == 'PBXGroup'
      remove_empty_groups(child, depth + 1)
    end
  end
  
  # Check if this group is now empty (or only has empty name)
  if group.children.empty? && group != group.project.main_group
    name = group.name || group.path || '(unnamed)'
    puts "#{'  ' * depth}Removing empty group: #{name}"
    group.remove_from_project
    return true
  end
  
  false
end

# Clean up empty groups multiple times (nested empties)
3.times do
  project.main_group.children.to_a.each do |child|
    if child.isa == 'PBXGroup' && child.name != 'Products' && child.name != 'Packages'
      remove_empty_groups(child)
    end
  end
end

# Also remove top-level empty or unnamed groups
project.main_group.children.to_a.each do |child|
  if child.isa == 'PBXGroup'
    if child.children.empty? || (child.name.nil? || child.name.empty?) && child.name != 'Products'
      # Check if it only contains empty groups
      only_empty = child.children.all? do |c|
        c.isa == 'PBXGroup' && (c.children.empty? || (c.name.nil? || c.name.empty?))
      end
      
      if only_empty || child.children.empty?
        puts "Removing top-level empty/unnamed group"
        child.remove_from_project
      end
    end
  end
end

# Ensure synced folders are at the main group level
path_to_folder.each do |path, sf|
  unless project.main_group.children.include?(sf)
    puts "Moving synced folder to main group: #{path}"
    project.main_group.children << sf
  end
end

project.save
puts "\nProject saved."

# Show final structure
puts "\nFinal structure:"
project.main_group.children.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end

