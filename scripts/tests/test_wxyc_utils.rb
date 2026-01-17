#!/usr/bin/env ruby
#
#  test_wxyc_utils.rb
#  WXYC
#
#  Unit tests for the shared WXYCUtils module. Tests path detection and
#  CLI argument handling without requiring an actual Xcode project.
#
#  Created by Claude on 01/16/26.
#  Copyright © 2026 WXYC. All rights reserved.
#

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/wxyc_utils'

class TestWXYCUtils < Minitest::Test
  # Test fallback path detection (outside of git repo)
  def test_project_root_fallback_from_scripts_dir
    Dir.mktmpdir do |tmp|
      # Create a fake project structure outside of git
      scripts_dir = File.join(tmp, 'scripts')
      Dir.mkdir(scripts_dir)

      # Run from temp dir (not a git repo)
      Dir.chdir(tmp) do
        root = WXYCUtils.project_root(File.join(scripts_dir, 'cleanup.rb'))
        assert_equal tmp, root
      end
    end
  end

  def test_project_root_fallback_from_lib_dir
    Dir.mktmpdir do |tmp|
      # Create a fake project structure outside of git
      scripts_dir = File.join(tmp, 'scripts')
      lib_dir = File.join(scripts_dir, 'lib')
      Dir.mkdir(scripts_dir)
      Dir.mkdir(lib_dir)

      Dir.chdir(tmp) do
        root = WXYCUtils.project_root(File.join(lib_dir, 'utils.rb'))
        assert_equal tmp, root
      end
    end
  end

  def test_project_path_appends_xcodeproj
    Dir.mktmpdir do |tmp|
      scripts_dir = File.join(tmp, 'scripts')
      Dir.mkdir(scripts_dir)

      Dir.chdir(tmp) do
        path = WXYCUtils.project_path(File.join(scripts_dir, 'cleanup.rb'))
        assert_equal File.join(tmp, 'WXYC.xcodeproj'), path
      end
    end
  end

  # Test git detection (in actual git repo)
  def test_project_root_uses_git_when_available
    # When running in a git repo, git rev-parse should be used
    Dir.chdir('/Users/jake/Developer/wxyc-ios-64-copy') do
      root = WXYCUtils.project_root(__FILE__)
      assert_equal '/Users/jake/Developer/wxyc-ios-64-copy', root
    end
  end

  # Test dry-run flag handling
  def test_dry_run_flag_when_present
    original_argv = ARGV.dup
    begin
      ARGV.replace(['--dry-run', 'other_arg', 'another'])
      result = WXYCUtils.dry_run?

      assert result, "dry_run? should return true when --dry-run is present"
      assert_equal ['other_arg', 'another'], ARGV, "ARGV should have --dry-run removed"
    ensure
      ARGV.replace(original_argv)
    end
  end

  def test_dry_run_flag_when_absent
    original_argv = ARGV.dup
    begin
      ARGV.replace(['some_arg', 'another_arg'])
      result = WXYCUtils.dry_run?

      refute result, "dry_run? should return false when --dry-run is absent"
      assert_equal ['some_arg', 'another_arg'], ARGV, "ARGV should be unchanged"
    ensure
      ARGV.replace(original_argv)
    end
  end

  def test_dry_run_removes_all_occurrences
    original_argv = ARGV.dup
    begin
      ARGV.replace(['--dry-run', 'arg', '--dry-run'])
      result = WXYCUtils.dry_run?

      assert result, "dry_run? should return true"
      # Ruby's delete removes ALL occurrences
      assert_equal ['arg'], ARGV, "All --dry-run flags should be removed"
    ensure
      ARGV.replace(original_argv)
    end
  end

  def test_dry_run_with_empty_argv
    original_argv = ARGV.dup
    begin
      ARGV.replace([])
      result = WXYCUtils.dry_run?

      refute result, "dry_run? should return false with empty ARGV"
      assert_empty ARGV
    ensure
      ARGV.replace(original_argv)
    end
  end
end
