#!/usr/bin/env ruby
# cleanup_duplicate_groups.rb
# Removes PBXGroup entries that are redundant with existing synced folders.
# Run this after converting to synced folders to clean up leftover groups.

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"

# Get all synced folder paths
synced_paths = Set.new
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    synced_paths << obj.path
  end
end

puts "Synced folder paths: #{synced_paths.to_a.sort}"

# Find the WXYC group
wxyc = project.main_group.children.find { |c| c.isa == 'PBXGroup' && c.path == 'WXYC' }

unless wxyc
  puts "WXYC group not found"
  exit 1
end

# Helper to check if a group path corresponds to a synced folder
def has_synced_equivalent?(group, parent_path, synced_paths)
  group_path = parent_path.empty? ? (group.name || group.path) : "#{parent_path}/#{group.name || group.path}"
  synced_paths.include?(group_path)
end

# Remove groups that have synced folder equivalents
def clean_group(group, parent_path, synced_paths, indent = 0)
  return unless group.respond_to?(:children)
  
  group_path = parent_path.empty? ? (group.name || group.path || '') : "#{parent_path}/#{group.name || group.path}"
  
  to_remove = []
  
  group.children.to_a.each do |child|
    if child.isa == 'PBXGroup'
      child_path = "#{group_path}/#{child.name || child.path}"
      
      if synced_paths.include?(child_path) || synced_paths.any? { |sp| sp.start_with?(child_path + '/') && synced_paths.include?(child_path.gsub(/^WXYC\//, 'WXYC/')) }
        # This group has a synced folder equivalent - mark for removal
        puts "#{'  ' * indent}Will remove group: #{child.name || child.path} (synced: #{child_path})"
        to_remove << child
      else
        # Recursively clean this group
        clean_group(child, group_path, synced_paths, indent + 1)
        
        # If the group is now empty, remove it
        if child.children.empty?
          puts "#{'  ' * indent}Will remove empty group: #{child.name || child.path}"
          to_remove << child
        end
      end
    end
  end
  
  to_remove.each do |g|
    g.remove_from_project
  end
end

# Special handling: The Configuration group should use synced folder
# The iOS group contains both synced folders and individual files - need to migrate

puts "\nAnalyzing WXYC group structure..."

# For each top-level group in WXYC, check if we should remove it
wxyc.children.to_a.each do |child|
  next unless child.isa == 'PBXGroup'
  
  child_name = child.name || child.path
  full_path = "WXYC/#{child_name}"
  
  puts "Checking: #{full_path}"
  
  # If there's a synced folder for this exact path, the group is redundant
  if synced_paths.include?(full_path)
    puts "  -> Has synced folder equivalent, removing"
    child.remove_from_project
  else
    # Check if all files in this group are covered by synced folders
    # For now, recursively clean
    clean_group(child, 'WXYC', synced_paths, 1)
    
    # If empty after cleaning, remove
    if child.children.empty?
      puts "  -> Now empty, removing"
      child.remove_from_project
    end
  end
end

# Also remove any synced folders that are nested inside the WXYC group
# They should be at the main group level
wxyc.children.to_a.each do |child|
  if child.isa == 'PBXFileSystemSynchronizedRootGroup'
    puts "Moving synced folder from WXYC to main group: #{child.path}"
    # The synced folder should already be referenced at the main group level
    # Just remove from here
    wxyc.children.delete(child)
  end
end

# If WXYC group is now empty, we could remove it
# But it might be better to keep it as a container
if wxyc.children.empty?
  puts "\nWXYC group is now empty, removing..."
  wxyc.remove_from_project
end

project.save
puts "\nProject saved."

# Show final structure
puts "\nFinal main group structure:"
project.main_group.children.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end

