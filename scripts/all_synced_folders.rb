#!/usr/bin/env ruby
# Convert the entire project to use only synced folders
# Remove all file groups and file references, keep only synced folders

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"

# Define the synced folders we want (one per target's source directory)
DESIRED_SYNCED_FOLDERS = [
  'WXYC/iOS',
  'WXYC/WatchXYC', 
  'WXYC/WXYC TV',
  'WXYC/Configuration',
]

# Get existing synced folders
existing_synced = {}
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    existing_synced[obj.path] = obj
  end
end

puts "Existing synced folders: #{existing_synced.keys.sort}"

# Find targets
targets_by_name = {}
project.targets.each { |t| targets_by_name[t.name] = t }

# Create missing synced folders
DESIRED_SYNCED_FOLDERS.each do |path|
  unless existing_synced[path]
    puts "Creating synced folder: #{path}"
    
    # Create the PBXFileSystemSynchronizedRootGroup
    synced = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
    synced.path = path
    synced.source_tree = '<group>'
    
    # Add to main group
    project.main_group.children << synced
    existing_synced[path] = synced
  end
end

# Remove nested synced folders that are subdirectories of WXYC/iOS
# (since WXYC/iOS synced folder will include everything)
subdirs_to_remove = ['WXYC/iOS/Assets', 'WXYC/iOS/Views', 'WXYC/iOS/NowPlayingWidget', 
                     'WXYC/iOS/Request Share Extension', 'WXYC/iOS/Tests/WXYCTests']

subdirs_to_remove.each do |path|
  if existing_synced[path]
    puts "Removing subdirectory synced folder (covered by parent): #{path}"
    existing_synced[path].remove_from_project
    existing_synced.delete(path)
  end
end

# Remove the WXYC PBXGroup and all its contents
wxyc_group = project.main_group.children.find { |c| c.isa == 'PBXGroup' && c.path == 'WXYC' }
if wxyc_group
  puts "Removing WXYC file group (replaced by synced folders)"
  wxyc_group.remove_from_project
end

# Update target source build phases to use synced folders
# Map targets to their synced folders
TARGET_TO_SYNCED = {
  'WXYC' => ['WXYC/iOS', 'WXYC/Configuration'],
  'WatchXYC' => ['WXYC/WatchXYC'],
  'WXYC TV' => ['WXYC/WXYC TV'],
  'NowPlayingWidget' => ['WXYC/iOS'],  # Uses iOS folder
  'Request Share Extension' => ['WXYC/iOS'],  # Uses iOS folder
  'WXYCTests' => ['WXYC/iOS'],  # Uses iOS folder
}

# Update fileSystemSynchronizedGroups for each target
TARGET_TO_SYNCED.each do |target_name, synced_paths|
  target = targets_by_name[target_name]
  next unless target
  
  # Get synced folder objects
  synced_objects = synced_paths.map { |p| existing_synced[p] }.compact
  
  if synced_objects.any?
    puts "Updating #{target_name} to use synced folders: #{synced_paths.join(', ')}"
    
    # Clear existing and set new
    target.file_system_synchronized_groups.clear
    synced_objects.each do |sf|
      target.file_system_synchronized_groups << sf unless target.file_system_synchronized_groups.include?(sf)
    end
  end
end

project.save
puts "\nProject saved."

# Show final structure
puts "\nFinal main group structure:"
project.main_group.children.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end

puts "\nTarget synced folder assignments:"
project.targets.each do |target|
  synced = target.file_system_synchronized_groups.map(&:path).join(', ')
  puts "  #{target.name}: #{synced.empty? ? '(none)' : synced}"
end

