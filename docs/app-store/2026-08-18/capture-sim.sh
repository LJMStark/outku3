#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CANDIDATE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$CANDIDATE/fixtures"
SHOTS="$CANDIDATE/screenshots-en"
APP="/tmp/kirole-app-store-capture/Build/Products/AppStoreRelease-iphonesimulator/Kirole.app"
SIM_NAME="iPhone 17 Pro Max"
BUNDLE="com.kirole.app"

[[ -d "$APP" ]] || {
  printf 'Missing AppStoreRelease simulator build at %s\n' "$APP" >&2
  exit 1
}

python3 "$CANDIDATE/generate-fixtures.py"

xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$SIM_NAME"
UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone 17 Pro Max/ {print $2; exit}')"
[[ -n "$UDID" ]] || {
  printf 'iPhone 17 Pro Max did not boot\n' >&2
  exit 1
}
open -a Simulator --args -CurrentDeviceUDID "$UDID"

# Wait until SpringBoard is up.
for _ in $(seq 1 30); do
  if xcrun simctl spawn "$UDID" launchctl print system 2>/dev/null | grep -q com.apple.SpringBoard; then
    break
  fi
  sleep 1
done

xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
DOCS="$DATA/Documents"
mkdir -p "$DOCS"
cp "$FIXTURES/pet.json" "$DOCS/pet.json"
cp "$FIXTURES/tasks.json" "$DOCS/tasks.json"
cp "$FIXTURES/events.json" "$DOCS/events.json"
cp "$FIXTURES/user_profile.json" "$DOCS/user_profile.json"
cp "$FIXTURES/haiku_cache.json" "$DOCS/haiku_cache.json"
cp "$FIXTURES/shared_companion_dialogue.json" "$DOCS/shared_companion_dialogue.json"

xcrun simctl spawn "$UDID" defaults write "$BUNDLE" isOnboardingCompleted -bool true
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" developmentStorageSchemaVersion -int 6
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array en
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale -string en_US

xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --cellularMode active \
  --operatorName "" \
  --batteryState charged \
  --batteryLevel 100

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE"
sleep 4

dismiss_system_alerts() {
  local tree
  tree="$(axe describe-ui --udid "$UDID" 2>/dev/null || true)"
  if printf '%s' "$tree" | grep -q 'Allow'; then
    axe tap --label "Don’t Allow" --udid "$UDID" 2>/dev/null \
      || axe tap --label "Don't Allow" --udid "$UDID" 2>/dev/null \
      || true
    sleep 1
  fi
}

flatten_png() {
  local src="$1"
  local dest="$2"
  sips -s format jpeg -s formatOptions 100 "$src" --out /tmp/kirole-shot.jpg >/dev/null
  sips -s format png /tmp/kirole-shot.jpg --out "$dest" >/dev/null
  rm -f /tmp/kirole-shot.jpg
}

mkdir -p "$SHOTS"
dismiss_system_alerts
sleep 1

take_shot() {
  local name="$1"
  local raw="/tmp/${name}.raw.png"
  xcrun simctl io "$UDID" screenshot "$raw"
  flatten_png "$raw" "$SHOTS/${name}.png"
  rm -f "$raw"
  sips -g pixelWidth -g pixelHeight -g hasAlpha -g format -g space "$SHOTS/${name}.png"
}

take_shot "01-home-timeline"
axe tap --id "appHeader.petTab" --udid "$UDID"
sleep 1.5
dismiss_system_alerts
take_shot "02-pet-today"
axe tap --id "appHeader.settingsTab" --udid "$UDID"
sleep 1.5
dismiss_system_alerts
take_shot "03-settings"

# Scroll settings to integrations / about if those ids exist.
if axe describe-ui --udid "$UDID" 2>/dev/null | grep -q 'Settings_PrivacyPolicy'; then
  :
fi
axe gesture scroll-down --udid "$UDID" || true
sleep 0.8
take_shot "04-settings-sources"

(cd "$SHOTS" && shasum -a 256 *.png > SHA256SUMS)
printf 'Captured screenshots in %s\n' "$SHOTS"
