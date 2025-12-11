#!/usr/bin/env ruby
# Convert file groups to synced folders (PBXFileSystemSynchronizedRootGroup)
# and add Info.plist exception sets

require 'xcodeproj'

PROJECT_PATH = ARGV[0] || '/Users/jake/Developer/wxyc-ios-64-copy/WXYC.xcodeproj'

# Folders to convert to synced folders, mapped to their target names
FOLDERS_TO_SYNC = {
  'WXYC/iOS/Assets' => 'WXYC',
  'WXYC/iOS/Views' => 'WXYC',
  'WXYC/iOS/NowPlayingWidget' => 'NowPlayingWidget',
  'WXYC/iOS/Request Share Extension' => 'Request Share Extension',
  'WXYC/iOS/Tests/WXYCTests' => 'WXYCTests',
  'WXYC/WatchXYC' => 'WatchXYC',
  'WXYC/WXYC TV' => 'WXYC TV',
  'WXYC/Configuration' => 'WXYC',
}

# Info.plist files to exclude from synced folder membership
PLIST_EXCEPTIONS = {
  'WXYC/iOS/Assets' => 'Info.plist',
  'WXYC/WatchXYC' => 'WatchXYC-Info.plist',
  'WXYC/WXYC TV' => 'WXYC-TV-Info.plist',
  'WXYC/iOS/Request Share Extension' => 'Info.plist',
}

def find_group_by_path(project, path)
  parts = path.split('/')
  group = project.main_group
  
  parts.each do |part|
    group = group.children.find { |c| c.respond_to?(:name) && c.name == part } ||
            group.children.find { |c| c.respond_to?(:path) && c.path == part }
    return nil unless group
  end
  
  group
end

def find_target(project, name)
  project.targets.find { |t| t.name == name }
end

project = Xcodeproj::Project.open(PROJECT_PATH)

puts "Opened project: #{PROJECT_PATH}"
puts "Targets: #{project.targets.map(&:name).join(', ')}"

# First, let's examine the current structure
puts "\nCurrent main group children:"
project.main_group.children.each do |child|
  puts "  - #{child.display_name} (#{child.class.name})"
  if child.respond_to?(:children)
    child.children.first(5).each do |subchild|
      puts "      - #{subchild.display_name} (#{subchild.class.name})"
    end
  end
end

# Check for existing synced folders
puts "\nExisting file system synchronized groups:"
project.root_object.main_group.recursive_children.each do |child|
  if child.isa == 'PBXFileSystemSynchronizedRootGroup'
    puts "  - #{child.path}"
  end
end

# Note: xcodeproj gem may not fully support PBXFileSystemSynchronizedRootGroup yet
# This is a newer Xcode 16 feature
puts "\nNote: The xcodeproj gem may not have full support for Xcode 16's synced folders."
puts "You may need to use the Python script with direct pbxproj manipulation instead."

project.save
puts "\nProject saved."

