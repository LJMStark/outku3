#!/usr/bin/env ruby
# frozen_string_literal: true

require "spaceship"

ROOT = File.expand_path("../../..", __dir__)
SHOTS = File.expand_path("screenshots-en", __dir__)

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

NAME = "Kirole: E-Ink Companion"
SUBTITLE = "Calendar, Focus & Companion"
PROMO = "Connect your Kirole E-Ink device and keep calendars, tasks, and a quiet companion beside you. Focus with Joy, Silas, or Nova, then earn energy for new scenes."
KEYWORDS = "tasks,timer,schedule,planner,reminders,productivity,agenda,weather,desk,pet,day,organizer"
SUPPORT = "https://kirole.681023.xyz/"
PRIVACY = "https://kirole.681023.xyz/privacy.html"
DESCRIPTION = <<~TEXT.strip
  Let your day live beside you, not inside your phone.

  Kirole is the iPhone companion app for the Kirole E-Ink desk device. Connect calendar and task sources, choose a companion, and bring your schedule, weather, and short companion lines to the desk. A compatible Kirole device is required for the desk display and hardware controls; feature availability depends on device firmware.

  SEE YOUR DAY

  • Browse calendar events on a timeline
  • View tasks for today, upcoming tasks, and tasks without due dates
  • Bring supported calendar and task sources into one calm view
  • See local weather powered by Apple Weather

  CHOOSE YOUR COMPANION

  • Joy brings warmth, ease, and small moments of delight
  • Silas offers quiet, caring encouragement
  • Nova filters noise and protects your time
  • Receive short companion lines shaped by your schedule and tasks

  FOCUS WITH A REWARD

  • Follow elapsed time, focus phase, and energy progress
  • Earn an energy bottle for each continuous 30-minute focus block
  • Build energy to unlock Harbor, Forest, and Night City scenes

  SUPPORTED SOURCES

  • Google Calendar
  • Google Tasks
  • Apple Calendar
  • Apple Reminders

  PRIVACY BY DESIGN

  • No ads
  • No third-party analytics or tracking SDKs
  • Custom companion photos are processed on your iPhone and are not uploaded to our servers
  • Relevant calendar, task, focus, goal, work preference, and companion setting information may be sent to the AI provider when Kirole generates companion dialogue, day summaries, event categories, and short support text
  • Kirole does not sell your personal data

  COMPATIBILITY

  Requires iOS 17 or later. The desk display, focus display, scene application, and custom avatar transfer require a compatible Kirole device and supported firmware.
TEXT

NOTES = <<~TEXT.strip
  Kirole is the iPhone companion app for a paired E-ink desk device.

  Review without hardware:
  - Sign in with Sign in with Apple or Google.
  - The iPhone app is fully usable without a Kirole device: onboarding, home timeline, companion/pet page, iPhone focus, settings, and account deletion.
  - Desk display, hardware-started focus, scene application, and custom avatar transfer require a compatible Kirole device and supported firmware. Those features stay inactive until a device is paired.

  Supported sources in this release: Google Calendar, Google Tasks, Apple Calendar, Apple Reminders.

  Privacy:
  - No ads and no third-party analytics SDKs.
  - Privacy policy: #{PRIVACY}
  - In-app path: Settings → Data Sources → Privacy Policy
  - Account deletion: Settings → Delete Account

  WeatherKit: local weather is provided by Apple Weather. The Home attribution footer after Today and the Settings data-source row show the Apple Weather mark and legal attribution link.

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
abort "App not found" unless app
info = app.fetch_edit_app_info
version = Spaceship::ConnectAPI.get_app_store_versions(
  app_id: app.id,
  filter: { platform: "IOS" },
  limit: 5
).first
info_loc = info.get_app_info_localizations.find { |loc| loc.locale == "en-US" }
version_loc = version.get_app_store_version_localizations.find { |loc| loc.locale == "en-US" }

step("App name / subtitle / privacy URL") do
  info_loc.update(
    attributes: {
      name: NAME,
      subtitle: SUBTITLE,
      privacyPolicyUrl: PRIVACY
    }
  )
end

step("Primary category Productivity") do
  info.update_categories(category_id_map: { primary_category_id: "PRODUCTIVITY" })
end

step("Version 2.0 + copyright") do
  version.update(
    attributes: {
      versionString: "2.0",
      copyright: "2026 Jiaming Liang"
    }
  )
end

step("English version copy + URLs") do
  version_loc.update(
    attributes: {
      description: DESCRIPTION,
      keywords: KEYWORDS,
      promotionalText: PROMO,
      supportUrl: SUPPORT,
      marketingUrl: SUPPORT
    }
  )
end

step("Age rating (no restricted content)") do
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
      gambling: false,
      unrestrictedWebAccess: false,
      userGeneratedContent: false
    }
  )
end

step("Review notes") do
  detail = version.fetch_app_store_review_detail
  attrs = {
    contactFirstName: "Jiaming",
    contactLastName: "Liang",
    contactEmail: "xiaoyouzi2010@gmail.com",
    demoAccountRequired: false,
    notes: NOTES
  }
  if detail
    detail.update(attributes: attrs)
  else
    version.create_app_store_review_detail(attributes: attrs)
  end
end

step("Exclude mainland China (CHN)") do
  territories = Spaceship::ConnectAPI.get_territories(limit: 200).all_pages.flat_map(&:to_models)
  ids = territories.map(&:id).reject { |id| id == "CHN" }
  raise "territory list too small: #{ids.size}" if ids.size < 100
  raise "CHN still present" if ids.include?("CHN")
  app.update(attributes: { availableInNewTerritories: false }, territory_ids: ids)
end

step("Upload iPhone 6.7/6.9 screenshots") do
  display = Spaceship::ConnectAPI::AppScreenshotSet::DisplayType::APP_IPHONE_67
  sets = version_loc.get_app_screenshot_sets
  set = sets.find { |item| item.screenshot_display_type == display }
  set ||= version_loc.create_app_screenshot_set(attributes: { screenshotDisplayType: display })
  existing =
    begin
      set.app_screenshots || set.get_app_screenshots
    rescue
      []
    end
  Array(existing).each do |shot|
    Spaceship::ConnectAPI.delete_app_screenshot(app_screenshot_id: shot.id)
  rescue
    shot.delete! if shot.respond_to?(:delete!)
  end
  %w[01-home-timeline.png 02-pet-today.png 03-settings-privacy.png].each_with_index do |name, index|
    path = File.join(SHOTS, name)
    raise "missing #{path}" unless File.file?(path)
    set.upload_screenshot(path: path, wait_for_processing: true, position: index)
  end
end

puts "Done. App #{app.id}, version #{version.id}"
