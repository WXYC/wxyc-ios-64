#!/usr/bin/env ruby
#
#  sync_folders_broad.rb
#  WXYC
#
#  Creates 4 top-level synced folders (iOS, WatchXYC, WXYC TV, Configuration)
#  and uses membership exceptions to control which files each target sees.
#  Alternative: sync_folders_granular.rb creates per-subdirectory synced folders.
#
#  Created by Jake Bromberg on 01/15/25.
#  Copyright © 2025 WXYC. All rights reserved.
#

require 'xcodeproj'
require_relative 'lib/wxyc_utils'

DRY_RUN = WXYCUtils.dry_run?
PROJECT_PATH = ARGV[0] || WXYCUtils.project_path(__FILE__)

project = Xcodeproj::Project.open(PROJECT_PATH)
puts "Opened project: #{PROJECT_PATH}"
puts "[DRY RUN MODE]" if DRY_RUN

# Remove all existing synced folders first
project.objects.to_a.each do |obj|
  if obj.isa == 'PBXFileSystemSynchronizedRootGroup'
    puts "Removing existing synced folder: #{obj.path}"
    obj.remove_from_project unless DRY_RUN
  end
end

# Define the synced folders we need
SYNCED_FOLDERS = [
  'WXYC/iOS',
  'WXYC/WatchXYC',
  'WXYC/WXYC TV',
  'WXYC/Configuration',
]

# Create synced folders
synced = {}
unless DRY_RUN
  SYNCED_FOLDERS.each do |path|
    sf = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
    sf.path = path
    sf.source_tree = '<group>'
    project.main_group.children << sf
    synced[path] = sf
    puts "Created synced folder: #{path}"
  end
else
  SYNCED_FOLDERS.each do |path|
    puts "[DRY RUN] Would create synced folder: #{path}"
  end
end

# Get targets
targets = {}
project.targets.each { |t| targets[t.name] = t }

# Assign synced folders to targets
# WXYC gets iOS and Configuration
# Extensions get iOS (but will exclude subdirs via membership exceptions)
puts "\nAssigning synced folders to targets..."

unless DRY_RUN
  # WXYC - main app
  if targets['WXYC']
    targets['WXYC'].file_system_synchronized_groups.clear
    targets['WXYC'].file_system_synchronized_groups << synced['WXYC/iOS']
    targets['WXYC'].file_system_synchronized_groups << synced['WXYC/Configuration']
    puts "  WXYC: WXYC/iOS, WXYC/Configuration"
  end

  # WatchXYC
  if targets['WatchXYC']
    targets['WatchXYC'].file_system_synchronized_groups.clear
    targets['WatchXYC'].file_system_synchronized_groups << synced['WXYC/WatchXYC']
    puts "  WatchXYC: WXYC/WatchXYC"
  end

  # WXYC TV
  if targets['WXYC TV']
    targets['WXYC TV'].file_system_synchronized_groups.clear
    targets['WXYC TV'].file_system_synchronized_groups << synced['WXYC/WXYC TV']
    puts "  WXYC TV: WXYC/WXYC TV"
  end

  # NowPlayingWidget - uses iOS folder
  if targets['NowPlayingWidget']
    targets['NowPlayingWidget'].file_system_synchronized_groups.clear
    targets['NowPlayingWidget'].file_system_synchronized_groups << synced['WXYC/iOS']
    puts "  NowPlayingWidget: WXYC/iOS"
  end

  # Request Share Extension - uses iOS folder
  if targets['Request Share Extension']
    targets['Request Share Extension'].file_system_synchronized_groups.clear
    targets['Request Share Extension'].file_system_synchronized_groups << synced['WXYC/iOS']
    puts "  Request Share Extension: WXYC/iOS"
  end

  # WXYCTests - uses iOS folder
  if targets['WXYCTests']
    targets['WXYCTests'].file_system_synchronized_groups.clear
    targets['WXYCTests'].file_system_synchronized_groups << synced['WXYC/iOS']
    puts "  WXYCTests: WXYC/iOS"
  end
else
  puts "[DRY RUN] Would assign synced folders to targets"
end

# Now create membership exceptions
# Each target needs to exclude files that don't belong to it
puts "\nCreating membership exceptions..."

unless DRY_RUN
  ios_folder = synced['WXYC/iOS']

  # For WXYC target: exclude extension subdirectories
  wxyc_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  wxyc_exceptions.target = targets['WXYC']
  wxyc_exceptions.membership_exceptions = [
    'NowPlayingWidget',
    'Request Share Extension',
    'Tests',
  ]
  ios_folder.exceptions ||= []
  ios_folder.exceptions << wxyc_exceptions
  puts "  WXYC: excluding NowPlayingWidget, Request Share Extension, Tests"

  # For NowPlayingWidget: only include NowPlayingWidget subdirectory
  widget_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  widget_exceptions.target = targets['NowPlayingWidget']
  # Exclude everything except NowPlayingWidget
  widget_exceptions.membership_exceptions = [
    'Assets',
    'Views',
    'Request Share Extension',
    'Tests',
    'CarPlaySceneDelegate.swift',
    'Intents.swift',
    'NowPlayingInfoCenterManager.swift',
    'WXYCApp.swift',
  ]
  ios_folder.exceptions << widget_exceptions
  puts "  NowPlayingWidget: including only NowPlayingWidget/"

  # For Request Share Extension
  share_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  share_exceptions.target = targets['Request Share Extension']
  share_exceptions.membership_exceptions = [
    'Assets',
    'Views',
    'NowPlayingWidget',
    'Tests',
    'CarPlaySceneDelegate.swift',
    'Intents.swift',
    'NowPlayingInfoCenterManager.swift',
    'WXYCApp.swift',
  ]
  ios_folder.exceptions << share_exceptions
  puts "  Request Share Extension: including only Request Share Extension/"

  # For WXYCTests
  test_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  test_exceptions.target = targets['WXYCTests']
  test_exceptions.membership_exceptions = [
    'Assets',
    'Views',
    'NowPlayingWidget',
    'Request Share Extension',
    'CarPlaySceneDelegate.swift',
    'Intents.swift',
    'NowPlayingInfoCenterManager.swift',
    'WXYCApp.swift',
  ]
  ios_folder.exceptions << test_exceptions
  puts "  WXYCTests: including only Tests/"

  # WatchXYC exceptions
  watch_folder = synced['WXYC/WatchXYC']
  watch_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  watch_exceptions.target = targets['WatchXYC']
  watch_exceptions.membership_exceptions = ['WatchXYC-Info.plist']
  watch_folder.exceptions ||= []
  watch_folder.exceptions << watch_exceptions
  puts "  WatchXYC: excluding WatchXYC-Info.plist"

  # WXYC TV exceptions
  tv_folder = synced['WXYC/WXYC TV']
  tv_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  tv_exceptions.target = targets['WXYC TV']
  tv_exceptions.membership_exceptions = ['WXYC-TV-Info.plist']
  tv_folder.exceptions ||= []
  tv_folder.exceptions << tv_exceptions
  puts "  WXYC TV: excluding WXYC-TV-Info.plist"
else
  puts "[DRY RUN] Would create membership exceptions"
end

if DRY_RUN
  puts "\n[DRY RUN] Would save project to #{PROJECT_PATH}"
else
  project.save
  puts "\nProject saved."
end

# Show structure
puts "\nFinal structure:"
project.main_group.children.each do |child|
  name = child.respond_to?(:name) && child.name ? child.name : child.path
  puts "  - #{name} (#{child.isa})"
end
