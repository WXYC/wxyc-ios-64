#!/usr/bin/env ruby
# Set up per-target synced folders with Info.plist exceptions
# Each target gets its own specific synced folders

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"

# Remove all existing synced folders
project.objects.to_a.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    puts "Removing: #{obj.path}"
    obj.remove_from_project
  end
end

# Remove any remaining WXYC group if it exists
project.main_group.children.to_a.each do |child|
  if child.isa == 'PBXGroup' && child.path == 'WXYC'
    puts "Removing WXYC group"
    child.remove_from_project
  end
end

# Define synced folders for each target
TARGET_FOLDERS = {
  'WXYC' => ['WXYC/iOS/Assets', 'WXYC/iOS/Views', 'WXYC/Configuration'],
  'NowPlayingWidget' => ['WXYC/iOS/NowPlayingWidget'],
  'Request Share Extension' => ['WXYC/iOS/Request Share Extension'],
  'WXYCTests' => ['WXYC/iOS/Tests'],
  'WatchXYC' => ['WXYC/WatchXYC'],
  'WXYC TV' => ['WXYC/WXYC TV'],
}

# Also need to add the root iOS swift files for WXYC
# These will be added as file references since they're not in a subdirectory
ROOT_SWIFT_FILES = [
  'WXYC/iOS/CarPlaySceneDelegate.swift',
  'WXYC/iOS/Intents.swift',
  'WXYC/iOS/NowPlayingInfoCenterManager.swift',
  'WXYC/iOS/WXYCApp.swift',
]

# Info.plist exceptions per folder
PLIST_EXCEPTIONS = {
  'WXYC/iOS/Assets' => 'Info.plist',
  'WXYC/iOS/NowPlayingWidget' => 'Info.plist',
  'WXYC/iOS/Request Share Extension' => 'Info.plist',
  'WXYC/WatchXYC' => 'WatchXYC-Info.plist',
  'WXYC/WXYC TV' => 'WXYC-TV-Info.plist',
}

# Get targets
targets = {}
project.targets.each { |t| targets[t.name] = t }

# Create all synced folders
all_folders = TARGET_FOLDERS.values.flatten.uniq
synced = {}

all_folders.each do |path|
  sf = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  sf.path = path
  sf.source_tree = '<group>'
  project.main_group.children << sf
  synced[path] = sf
  puts "Created synced folder: #{path}"
end

# Assign folders to targets
TARGET_FOLDERS.each do |target_name, folders|
  target = targets[target_name]
  next unless target
  
  target.file_system_synchronized_groups.clear
  folders.each do |path|
    if synced[path]
      target.file_system_synchronized_groups << synced[path]
    end
  end
  puts "Assigned to #{target_name}: #{folders.join(', ')}"
end

# Add Info.plist exceptions
puts "\nAdding Info.plist exceptions..."
PLIST_EXCEPTIONS.each do |folder_path, plist_name|
  sf = synced[folder_path]
  next unless sf
  
  # Find the target that owns this folder
  owner = TARGET_FOLDERS.find { |t, folders| folders.include?(folder_path) }
  next unless owner
  
  target = targets[owner[0]]
  next unless target
  
  exception = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  exception.target = target
  exception.membership_exceptions = [plist_name]
  sf.exceptions ||= []
  sf.exceptions << exception
  puts "  #{folder_path}: excluding #{plist_name} from #{target.name}"
end

# Add root Swift files to WXYC target as file references
puts "\nAdding root Swift files to WXYC target..."
wxyc_target = targets['WXYC']
if wxyc_target
  # Create an iOS group for the root swift files
  ios_group = project.main_group.new_group('iOS', 'WXYC/iOS')
  
  ROOT_SWIFT_FILES.each do |path|
    filename = File.basename(path)
    file_ref = ios_group.new_file(filename)
    
    # Add to WXYC target's sources
    wxyc_target.source_build_phase.add_file_reference(file_ref)
    puts "  Added #{filename}"
  end
end

project.save
puts "\nProject saved."

# Show final structure
puts "\nFinal structure:"
project.main_group.children.sort_by { |c| c.respond_to?(:path) ? c.path.to_s : c.name.to_s }.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end

puts "\nTarget assignments:"
project.targets.each do |target|
  synced_list = target.file_system_synchronized_groups.map(&:path).join(', ')
  puts "  #{target.name}: #{synced_list.empty? ? '(none)' : synced_list}"
end

