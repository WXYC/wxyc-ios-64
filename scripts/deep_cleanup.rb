#!/usr/bin/env ruby
#
#  deep_cleanup.rb
#  WXYC
#
#  Deep cleanup of the Xcode project structure. Removes all empty groups
#  and consolidates synced folders.
#
#  Created by Jake Bromberg on 12/23/24.
#  Copyright © 2024 WXYC. All rights reserved.
#

require 'xcodeproj'
require 'set'
require_relative 'lib/wxyc_utils'

DRY_RUN = WXYCUtils.dry_run?
PROJECT_PATH = ARGV[0] || WXYCUtils.project_path(__FILE__)

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"
puts "[DRY RUN MODE]" if DRY_RUN

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
    sf.remove_from_project unless DRY_RUN
  else
    path_to_folder[sf.path] = sf
  end
end
  
# Recursive function to remove empty groups
def remove_empty_groups(group, depth = 0, dry_run = false)
  return unless group.respond_to?(:children)

  # First, recursively clean children
  group.children.to_a.each do |child|
    if child.isa == 'PBXGroup'
      remove_empty_groups(child, depth + 1, dry_run)
    end
  end

  # Check if this group is now empty (or only has empty name)
  if group.children.empty? && group != group.project.main_group
    name = group.name || group.path || '(unnamed)'
    puts "#{'  ' * depth}Removing empty group: #{name}"
    group.remove_from_project unless dry_run
    return true
  end

  false
end

# Clean up empty groups multiple times (nested empties)
3.times do
  project.main_group.children.to_a.each do |child|
    if child.isa == 'PBXGroup' && child.name != 'Products' && child.name != 'Packages'
      remove_empty_groups(child, 0, DRY_RUN)
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
        child.remove_from_project unless DRY_RUN
      end
    end
  end
end

# Ensure synced folders are at the main group level
path_to_folder.each do |path, sf|
  unless project.main_group.children.include?(sf)
    puts "Moving synced folder to main group: #{path}"
    project.main_group.children << sf unless DRY_RUN
  end
end

if DRY_RUN
  puts "\n[DRY RUN] Would save project to #{PROJECT_PATH}"
else
  project.save
  puts "\nProject saved."
end

# Show final structure
puts "\nFinal structure:"
project.main_group.children.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end
