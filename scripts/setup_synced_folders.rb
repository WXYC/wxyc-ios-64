#!/usr/bin/env ruby
# Set up proper synced folders for each target with exception sets for Info.plist files

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"

# Define synced folders per target
# Each target gets synced folders for its source directories
TARGET_SYNCED_FOLDERS = {
  'WXYC' => {
    folders: ['WXYC/iOS/Assets', 'WXYC/iOS/Views'],
    # Individual swift files at WXYC/iOS/ root need to be handled separately
    # For now, we'll include them via the Assets folder or add them as file refs
  },
  'NowPlayingWidget' => {
    folders: ['WXYC/iOS/NowPlayingWidget'],
  },
  'Request Share Extension' => {
    folders: ['WXYC/iOS/Request Share Extension'],
  },
  'WXYCTests' => {
    folders: ['WXYC/iOS/Tests/WXYCTests'],
  },
  'WatchXYC' => {
    folders: ['WXYC/WatchXYC'],
  },
  'WXYC TV' => {
    folders: ['WXYC/WXYC TV'],
  },
}

# Info.plist files to exclude from each synced folder
PLIST_EXCEPTIONS = {
  'WXYC/iOS/Assets' => { target: 'WXYC', plist: 'Info.plist' },
  'WXYC/iOS/NowPlayingWidget' => { target: 'NowPlayingWidget', plist: 'Info.plist' },
  'WXYC/iOS/Request Share Extension' => { target: 'Request Share Extension', plist: 'Info.plist' },
  'WXYC/WatchXYC' => { target: 'WatchXYC', plist: 'WatchXYC-Info.plist' },
  'WXYC/WXYC TV' => { target: 'WXYC TV', plist: 'WXYC-TV-Info.plist' },
}

# Remove the WXYC/iOS synced folder if it exists (we're using subdirectories instead)
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup' && obj.path == 'WXYC/iOS'
    puts "Removing WXYC/iOS synced folder (using subdirectories instead)"
    obj.remove_from_project
  end
end

# Get or create synced folders
synced_folders = {}
project.objects.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    synced_folders[obj.path] = obj
  end
end

# Create missing synced folders
all_folders = TARGET_SYNCED_FOLDERS.values.flat_map { |v| v[:folders] }.uniq
all_folders += ['WXYC/Configuration']  # Also keep Configuration

all_folders.each do |path|
  unless synced_folders[path]
    puts "Creating synced folder: #{path}"
    synced = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
    synced.path = path
    synced.source_tree = '<group>'
    project.main_group.children << synced
    synced_folders[path] = synced
  end
end

# Find targets
targets_by_name = {}
project.targets.each { |t| targets_by_name[t.name] = t }

# Update each target's synced folders
TARGET_SYNCED_FOLDERS.each do |target_name, config|
  target = targets_by_name[target_name]
  next unless target
  
  folders = config[:folders]
  synced_objs = folders.map { |f| synced_folders[f] }.compact
  
  # Add Configuration for WXYC target
  if target_name == 'WXYC' && synced_folders['WXYC/Configuration']
    synced_objs << synced_folders['WXYC/Configuration']
  end
  
  puts "Setting #{target_name} synced folders: #{synced_objs.map(&:path).join(', ')}"
  
  target.file_system_synchronized_groups.clear
  synced_objs.each do |sf|
    target.file_system_synchronized_groups << sf
  end
end

# Now add exception sets for Info.plist files
puts "\nAdding Info.plist exception sets..."

PLIST_EXCEPTIONS.each do |folder_path, config|
  synced = synced_folders[folder_path]
  next unless synced
  
  target = targets_by_name[config[:target]]
  next unless target
  
  plist_name = config[:plist]
  
  # Check if exception set already exists
  existing_exception = nil
  if synced.respond_to?(:exceptions) && synced.exceptions
    synced.exceptions.each do |exc|
      if exc.respond_to?(:membership_exceptions) && exc.membership_exceptions&.include?(plist_name)
        existing_exception = exc
        break
      end
    end
  end
  
  unless existing_exception
    puts "  Adding exception for #{plist_name} in #{folder_path} for target #{target.name}"
    
    # Create exception set
    exception = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
    exception.membership_exceptions = [plist_name]
    exception.target = target
    
    # Link to synced folder
    synced.exceptions ||= []
    synced.exceptions << exception
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

