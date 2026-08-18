#!/usr/bin/env ruby
# frozen_string_literal: true

require "spaceship"

env_path = File.expand_path("../../../fastlane/.env", __dir__)
File.foreach(env_path) do |line|
  next if line.strip.empty? || line.start_with?("#")
  key, value = line.split("=", 2)
  next unless key && value
  ENV[key.strip] ||= value.strip
end

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"),
  issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  filepath: ENV.fetch("ASC_KEY_PATH")
)
Spaceship::ConnectAPI.token = token

app = Spaceship::ConnectAPI::App.find("com.kirole.app")
abort "App com.kirole.app not found" unless app

puts "APP id=#{app.id} name=#{app.name} bundle=#{app.bundle_id}"
puts "APP methods sample: #{(app.methods - Object.methods).grep(/avail|territor|local|privacy|primary|category|info|price/).sort.first(40).join(', ')}"

begin
  infos = app.fetch_edit_app_info || app.fetch_live_app_info
  puts "APP INFO: #{infos.inspect[0, 800]}"
rescue => e
  puts "APP INFO error: #{e.class}: #{e.message}"
end

begin
  versions = Spaceship::ConnectAPI.get_app_store_versions(
    app_id: app.id,
    filter: { platform: "IOS" },
    includes: "appStoreVersionLocalizations",
    limit: 10
  ).all_pages.flat_map(&:to_models)
  versions.each do |v|
    puts "VERSION #{v.version_string} state=#{v.app_store_state} id=#{v.id}"
  end
rescue => e
  puts "VERSION error: #{e.class}: #{e.message}"
end

puts "ConnectAPI methods: #{Spaceship::ConnectAPI.methods.grep(/avail|territor|privacy|age|review/).sort.join(', ')}"
