#!/usr/bin/env ruby
# frozen_string_literal: true

require "spaceship"
require "json"

ROOT = File.expand_path("../../..", __dir__)
File.foreach(File.join(ROOT, "fastlane/.env")) do |line|
  next if line.strip.empty? || line.start_with?("#")
  key, value = line.split("=", 2)
  next unless key && value
  ENV[key.strip] ||= value.strip
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"),
  issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  filepath: ENV.fetch("ASC_KEY_PATH")
)

NOTES = <<~TEXT.strip
  Kirole is the iPhone companion app for a paired E-ink desk device.

  Review without hardware:
  - Sign in with Sign in with Apple or Google.
  - The iPhone app is fully usable without a Kirole device: onboarding, home timeline, companion/pet page, iPhone focus, settings, and account deletion.
  - Desk display, hardware-started focus, scene application, and custom avatar transfer require a compatible Kirole device and supported firmware. Those features stay inactive until a device is paired.

  Supported sources in this release: Google Calendar, Google Tasks, Apple Calendar, Apple Reminders.

  Privacy:
  - No ads and no third-party analytics SDKs.
  - Privacy policy: https://kirole.681023.xyz/privacy.html
  - In-app path: Settings -> Data Sources -> Privacy Policy
  - Account deletion: Settings -> Delete Account

  WeatherKit: local weather is provided by Apple Weather. The home header and Settings show the Apple Weather mark and legal attribution link.

  Family Controls / Screen Time: used only for optional Deep Focus interruption detection and temporary blocking of apps the user selects during a user-started focus session. Standard focus does not block apps.

  This version is not available on the mainland China storefront.

  Please review on iPhone. A Kirole E-ink device is not required to complete app review.
TEXT

def step(title)
  print "#{title} ... "
  yield
  puts "OK"
rescue => error
  puts "FAIL: #{error.class}: #{error.message}"
end

app = Spaceship::ConnectAPI::App.find("com.kirole.app")
info = app.fetch_edit_app_info
version = Spaceship::ConnectAPI.get_app_store_versions(
  app_id: app.id,
  filter: { platform: "IOS" },
  limit: 5
).first

step("Age rating remaining fields") do
  rating = info.fetch_age_rating_declaration
  none = Spaceship::ConnectAPI::AgeRatingDeclaration::Rating::NONE
  rating.update(
    attributes: {
      alcoholTobaccoOrDrugUseOrReferences: none,
      contests: none,
      gamblingSimulated: none,
      gunsOrOtherWeapons: none,
      horrorOrFearThemes: none,
      matureOrSuggestiveThemes: none,
      medicalOrTreatmentInformation: none,
      profanityOrCrudeHumor: none,
      sexualContentGraphicAndNudity: none,
      sexualContentOrNudity: none,
      violenceCartoonOrFantasy: none,
      violenceRealistic: none,
      violenceRealisticProlongedGraphicOrSadistic: none,
      advertising: false,
      ageAssurance: false,
      gambling: false,
      healthOrWellnessTopics: false,
      lootBox: false,
      messagingAndChat: false,
      parentalControls: false,
      unrestrictedWebAccess: false,
      userGeneratedContent: false
    }
  )
end

step("Review notes") do
  attrs = {
    contactFirstName: "Jiaming",
    contactLastName: "Liang",
    contactEmail: "xiaoyouzi2010@gmail.com",
    demoAccountRequired: false,
    notes: NOTES
  }
  begin
    detail = version.fetch_app_store_review_detail
  rescue RuntimeError
    detail = nil
  end
  if detail
    detail.update(attributes: attrs)
  else
    version.create_app_store_review_detail(attributes: attrs)
  end
end

step("Read current availability") do
  avail = app.get_app_availabilities(limit: { "territoryAvailabilities" => 50 })
  puts
  puts "  availability id=#{avail&.id} newTerritories=#{avail&.available_in_new_territories}"
  territories = avail&.territory_availabilities || []
  puts "  first page territories=#{territories.size}"
  chn = territories.find { |item| item.id.to_s.include?("CHN") || item.inspect.include?("CHN") }
  puts "  CHN sample=#{chn.inspect.to_s[0, 240]}"
end

step("Exclude CHN via v2 appAvailabilities") do
  client = Spaceship::ConnectAPI
  all = []
  resp = client.get_territories(limit: 200)
  loop do
    all.concat(resp.to_models)
    break unless resp.respond_to?(:next_page?) && resp.next_page?
    resp = resp.next_page
  end
  ids = all.map(&:id).uniq.reject { |id| id == "CHN" }
  raise "too few territories: #{ids.size}" if ids.size < 100

  included = ids.each_with_index.map do |id, index|
    {
      type: "territoryAvailabilities",
      id: "${territory#{index}}",
      relationships: {
        territory: {
          data: { type: "territories", id: id }
        }
      }
    }
  end
  body = {
    data: {
      type: "appAvailabilities",
      attributes: {
        availableInNewTerritories: false
      },
      relationships: {
        app: {
          data: { type: "apps", id: app.id }
        },
        territoryAvailabilities: {
          data: included.map { |row| { type: "territoryAvailabilities", id: row[:id] } }
        }
      }
    },
    included: included
  }
  client.tunes_request_client.post("v2/appAvailabilities", body)
end
