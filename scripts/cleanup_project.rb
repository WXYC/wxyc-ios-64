#!/usr/bin/env ruby
# Clean up duplicate groups in the Xcode project
# Remove regular PBXGroup entries where synced folders exist

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)

puts "Opened project: #{PROJECT_PATH}"

# Find all synced folder paths
synced_paths = Set.new
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    synced_paths << obj.path
    puts "Found synced folder: #{obj.path}"
  end
end

# Find the main WXYC group
wxyc_group = project.main_group.children.find { |c| c.respond_to?(:name) && c.name == 'WXYC' }

if wxyc_group
  puts "\nCleaning up WXYC group..."
  
  # Groups to remove (those that have synced folder equivalents)
  groups_to_remove = []
  
  wxyc_group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      # Check if this group's path matches a synced folder
      full_path = "WXYC/#{child.name || child.path}"
      if synced_paths.include?(full_path) || synced_paths.any? { |p| p.start_with?(full_path + '/') }
        puts "  Will remove duplicate group: #{child.display_name}"
        groups_to_remove << child
      end
    end
  end
  
  # Remove the duplicate groups
  groups_to_remove.each do |group|
    group.remove_from_project
    puts "  Removed: #{group.display_name}"
  end
end

# Remove duplicate synced folders from main group (keep only under their proper parent)
main_group_synced = project.main_group.children.select do |c| 
  c.isa == 'PBXFileSystemSynchronizedRootGroup'
end

puts "\nSynced folders in main group: #{main_group_synced.count}"
main_group_synced.each do |sf|
  puts "  - #{sf.path}"
end

# The synced folders should ideally be organized, but for now let's just ensure
# they're not duplicated

# Save the project
project.save
puts "\nProject saved."

# Show final structure
puts "\nFinal main group structure:"
project.main_group.children.each do |child|
  puts "  - #{child.display_name} (#{child.isa})"
end

