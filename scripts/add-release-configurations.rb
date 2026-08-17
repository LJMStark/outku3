#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the two distribution build configurations required by the
# AGENTS.md "Release Channel Policy":
#
#   InternalRelease  - Internal TestFlight channel, defines KIROLE_INTERNAL
#                      via Config/InternalRelease.xcconfig
#   AppStoreRelease  - App Store channel, Config/AppStoreRelease.xcconfig,
#                      must never define KIROLE_INTERNAL
#
# Both are clones of each configuration list's existing Release settings, so
# they stay Release-optimized. Only the Kirole app target swaps its base
# xcconfig; the UITests target keeps Tests.xcconfig and the DeviceActivity
# extension keeps its inline settings.
#
# Idempotent: re-running skips configurations that already exist.
#
#   bundle exec ruby scripts/add-release-configurations.rb

require "xcodeproj"

PROJECT_PATH = File.expand_path("../Kirole.xcodeproj", __dir__)
APP_TARGET = "Kirole"
NEW_CONFIG_NAMES = %w[InternalRelease AppStoreRelease].freeze
APP_XCCONFIG = {
  "InternalRelease" => "InternalRelease.xcconfig",
  "AppStoreRelease" => "AppStoreRelease.xcconfig",
}.freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

def clone_release(project, list, name, owner_label)
  if list.build_configurations.any? { |c| c.name == name }
    puts "skip  #{owner_label}: #{name} already exists"
    return nil
  end
  release = list.build_configurations.find { |c| c.name == "Release" }
  raise "#{owner_label} has no Release configuration to clone" unless release

  config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  config.name = name
  config.build_settings = release.build_settings.dup
  config.base_configuration_reference = release.base_configuration_reference
  config.base_configuration_reference_anchor = release.base_configuration_reference_anchor
  config.base_configuration_reference_relative_path = release.base_configuration_reference_relative_path
  list.build_configurations << config
  puts "add   #{owner_label}: #{name}"
  config
end

NEW_CONFIG_NAMES.each do |name|
  clone_release(project, project.build_configuration_list, name, "project")
end

project.targets.each do |target|
  NEW_CONFIG_NAMES.each do |name|
    config = clone_release(project, target.build_configuration_list, name, "target #{target.name}")
    next unless config && target.name == APP_TARGET

    config.base_configuration_reference_relative_path = APP_XCCONFIG.fetch(name)
    puts "      base xcconfig -> Config/#{APP_XCCONFIG.fetch(name)}"
  end
end

project.save
puts "saved #{PROJECT_PATH}"
