#
#  wxyc_utils.rb
#  WXYC
#
#  Shared utilities for WXYC build scripts. Provides portable path detection
#  and common CLI argument handling (like --dry-run).
#
#  Created by Claude on 01/16/26.
#  Copyright © 2026 WXYC. All rights reserved.
#

# Shared utilities for WXYC build scripts
module WXYCUtils
  # Detect project root from script location or git.
  #
  # @param script_path [String] The path of the calling script (__FILE__)
  # @return [String] Absolute path to the project root directory
  def self.project_root(script_path = __FILE__)
    # Try git first
    git_root = `git rev-parse --show-toplevel 2>/dev/null`.strip
    return git_root unless git_root.empty?

    # Fallback: assume script is in scripts/ or scripts/lib/
    script_dir = File.dirname(File.expand_path(script_path))
    if File.basename(script_dir) == 'lib'
      File.dirname(File.dirname(script_dir))
    else
      File.dirname(script_dir)
    end
  end

  # Get the path to the WXYC.xcodeproj file.
  #
  # @param script_path [String] The path of the calling script (__FILE__)
  # @return [String] Absolute path to WXYC.xcodeproj
  def self.project_path(script_path = __FILE__)
    File.join(project_root(script_path), 'WXYC.xcodeproj')
  end

  # Check if --dry-run flag was passed and remove it from ARGV.
  #
  # @return [Boolean] true if --dry-run was present
  def self.dry_run?
    if ARGV.include?('--dry-run')
      ARGV.delete('--dry-run')
      true
    else
      false
    end
  end

  # Print a message only in dry-run mode.
  #
  # @param message [String] The message to print
  # @param dry_run [Boolean] Whether we're in dry-run mode
  def self.dry_run_notice(message, dry_run)
    puts "[DRY RUN] #{message}" if dry_run
  end
end
