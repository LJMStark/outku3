#!/usr/bin/env bash

set -euo pipefail

mode="${1:-package}"
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
asset_root="${KIROLE_APP_STORE_ASSET_ROOT:-$script_root}"
repo_root="${KIROLE_REPO_ROOT:-$(git -C "$script_root" rev-parse --show-toplevel)}"
metadata_file="$asset_root/metadata-en.md"
record_file="$asset_root/SUBMISSION-RECORD.md"
capture_file="$asset_root/CAPTURE.md"
screenshots_dir="$asset_root/screenshots-en"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

case "$mode" in
  package | submission) ;;
  *) fail "usage: $0 [package|submission]" ;;
esac

[[ -d "$asset_root" ]] || fail "asset directory does not exist: $asset_root"
[[ -f "$metadata_file" ]] || fail "metadata-en.md is missing"
[[ -f "$record_file" ]] || fail "SUBMISSION-RECORD.md is missing"
[[ -f "$capture_file" ]] || fail "CAPTURE.md is missing"

if [[ -d "$screenshots_dir" ]]; then
  expected_entries=(
    "CAPTURE.md"
    "README.md"
    "SUBMISSION-RECORD.md"
    "design-philosophy.md"
    "metadata-en.md"
    "screenshots-en"
    "validate-assets.sh"
    "voice-profile.md"
  )
else
  expected_entries=(
    "CAPTURE.md"
    "README.md"
    "SUBMISSION-RECORD.md"
    "design-philosophy.md"
    "metadata-en.md"
    "validate-assets.sh"
    "voice-profile.md"
  )
fi

actual_entries=()
while IFS= read -r entry; do
  actual_entries+=("$entry")
done < <(find "$asset_root" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)

[[ ${#actual_entries[@]} -eq ${#expected_entries[@]} ]] || \
  fail "expected ${#expected_entries[@]} package entries, found ${#actual_entries[@]}: ${actual_entries[*]}"

for index in "${!expected_entries[@]}"; do
  [[ "${actual_entries[$index]}" == "${expected_entries[$index]}" ]] || \
    fail "unexpected package entries: ${actual_entries[*]}"
done

extract_text_block() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == heading { found_heading = 1; next }
    found_heading && $0 == "```text" { in_block = 1; next }
    in_block && $0 == "```" { exit }
    in_block { print }
  ' "$metadata_file"
}

byte_count() {
  LC_ALL=C printf '%s' "$1" | wc -c | tr -d ' '
}

assert_max_bytes() {
  local label="$1"
  local heading="$2"
  local limit="$3"
  local value
  local size

  value="$(extract_text_block "$heading")"
  [[ -n "$value" ]] || fail "$label value is missing"
  size="$(byte_count "$value")"
  (( size <= limit )) || fail "$label is $size bytes; limit is $limit"
}

assert_max_bytes "App name" "## App name — 23 / 30 characters" 30
assert_max_bytes "Subtitle" "## Subtitle — 27 / 30 characters" 30
assert_max_bytes "Promotional text" "## Promotional text — 158 / 170 characters" 170
assert_max_bytes "Keywords" "## Keywords — 89 / 100 bytes" 100

grep -Eq 'https://kirole\.681023\.xyz/' "$metadata_file" || fail "marketing/support URL is missing"
grep -Eq 'https://kirole\.681023\.xyz/privacy\.html' "$metadata_file" || fail "privacy policy URL is missing"
if grep -Eqi 'private beta|Wi-Fi PC Debug|BLE Keep Alive|Focus Debug|Shipping Mode' "$metadata_file"; then
  fail "storefront metadata contains internal or beta wording"
fi

if [[ "$mode" == "package" ]]; then
  if [[ -d "$screenshots_dir" ]]; then
    printf 'PASS: package structure and metadata limits are valid; screenshot presence is not submission approval\n'
  else
    printf 'PASS: metadata-only package is valid; screenshots and submission approval remain blocked\n'
  fi
  exit 0
fi

grep -qx 'Status: READY' "$record_file" || fail "submission record status is not READY"
if grep -Eq ': TBD$|: REPLACE_' "$record_file"; then
  fail "submission record still contains placeholder values"
fi

required_pass_fields=(
  'Compilation condition reaches `KirolePackage`'
  'Paired release-gate tests'
  'Archived internal-symbol/behavior scan'
  'Production security fail-closed check'
  'Wi-Fi PC Debug absent'
  'BLE Keep Alive UI and behavior absent'
  'Test focus session absent'
  'Focus Debug and virtual time absent'
  'Raw BLE diagnostic summaries absent'
  'Shipping Mode/factory commands absent'
  'Engineering OTA and environment diagnostics absent'
  'Real-device smoke test'
  'Enabled provider list matches the binary'
  'App Privacy questionnaire matches code and policy'
  'Apple Weather mark and legal attribution verified'
  'Human visual review (no internal UI or reconstructed components)'
)
for field in "${required_pass_fields[@]}"; do
  grep -Fqx -- "- $field: PASS" "$record_file" || fail "$field is not recorded as PASS"
done

scheme_root="$repo_root/Kirole.xcodeproj/xcshareddata/xcschemes"
app_store_scheme_file="$scheme_root/Kirole-AppStore.xcscheme"
internal_scheme_file="$scheme_root/Kirole-Internal.xcscheme"
project_file="$repo_root/Kirole.xcodeproj/project.pbxproj"
release_gate_script="$repo_root/scripts/verify-release-boundary.sh"
[[ -f "$app_store_scheme_file" ]] || fail "Kirole-AppStore scheme is missing"
[[ -f "$internal_scheme_file" ]] || fail "Kirole-Internal scheme is missing"
[[ -x "$release_gate_script" ]] || \
  fail "scripts/verify-release-boundary.sh is missing or not executable"
grep -q 'name = AppStoreRelease;' "$project_file" || fail "AppStoreRelease configuration is missing"
grep -q 'name = InternalRelease;' "$project_file" || fail "InternalRelease configuration is missing"

app_store_archive_configuration="$(xmllint --xpath 'string(/Scheme/ArchiveAction/@buildConfiguration)' "$app_store_scheme_file")"
internal_archive_configuration="$(xmllint --xpath 'string(/Scheme/ArchiveAction/@buildConfiguration)' "$internal_scheme_file")"
[[ "$app_store_archive_configuration" == "AppStoreRelease" ]] || \
  fail "Kirole-AppStore ArchiveAction uses $app_store_archive_configuration"
[[ "$internal_archive_configuration" == "InternalRelease" ]] || \
  fail "Kirole-Internal ArchiveAction uses $internal_archive_configuration"

read_build_conditions() {
  local scheme="$1"
  local configuration="$2"

  xcodebuild \
    -workspace "$repo_root/Kirole.xcworkspace" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -showBuildSettings 2>/dev/null |
    sed -n 's/^[[:space:]]*SWIFT_ACTIVE_COMPILATION_CONDITIONS = //p'
}

app_store_conditions="$(read_build_conditions "Kirole-AppStore" "AppStoreRelease")"
internal_conditions="$(read_build_conditions "Kirole-Internal" "InternalRelease")"
[[ "$app_store_conditions" != *KIROLE_INTERNAL* ]] || \
  fail "KIROLE_INTERNAL is present in AppStoreRelease build settings"
[[ "$internal_conditions" == *KIROLE_INTERNAL* ]] || \
  fail "KIROLE_INTERNAL is absent from InternalRelease build settings"

"$release_gate_script" || fail "release-channel validation failed"
grep -q 'Kirole-AppStore' "$capture_file" || fail "capture procedure does not use Kirole-AppStore"
grep -q 'AppStoreRelease' "$capture_file" || fail "capture procedure does not use AppStoreRelease"

website_index="$repo_root/website/index.html"
website_privacy="$repo_root/website/privacy.html"
website_terms="$repo_root/website/terms.html"
[[ -f "$website_index" && -f "$website_privacy" && -f "$website_terms" ]] || \
  fail "website source is missing"
if grep -Eqi 'private beta' "$website_index" "$website_terms"; then
  fail "website source still advertises a private beta"
fi
if grep -Eqi 'No location data|exactly two cases' "$website_privacy"; then
  fail "privacy source contains a known-false data-flow claim"
fi

expected_providers=("Google Calendar" "Google Tasks" "Apple Calendar" "Apple Reminders")
disabled_providers=("Outlook Calendar" "Microsoft To Do" "Todoist" "TickTick" "Notion" "Taskade")

metadata_providers="$(awk '
  /^SUPPORTED SOURCES$/ { in_sources = 1; next }
  in_sources && /^$/ { if (found_source) exit; next }
  in_sources && /^• / { sub(/^• /, ""); print; found_source = 1 }
' "$metadata_file")"
expected_provider_block="$(printf '%s\n' "${expected_providers[@]}")"
[[ "$metadata_providers" == "$expected_provider_block" ]] || \
  fail "metadata supported-source list must contain only the four approved providers"

for provider in "${expected_providers[@]}"; do
  grep -Fq "$provider" "$website_index" || fail "website is missing approved provider: $provider"
  grep -Fq "$provider" "$website_privacy" || fail "privacy policy is missing approved provider: $provider"
done
for provider in "${disabled_providers[@]}"; do
  if grep -Fiq "$provider" "$website_index" "$website_privacy" "$website_terms" "$metadata_file"; then
    fail "storefront source advertises disabled provider: $provider"
  fi
done

[[ -d "$screenshots_dir" ]] || fail "screenshots-en is missing"
checksum_file="$screenshots_dir/SHA256SUMS"
[[ -f "$checksum_file" ]] || fail "screenshots-en/SHA256SUMS is missing"

while IFS= read -r entry; do
  case "$entry" in
    SHA256SUMS | *.png) ;;
    *) fail "unexpected screenshot package entry: $entry" ;;
  esac
done < <(find "$screenshots_dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)

shopt -s nullglob
screenshots=("$screenshots_dir"/*.png)
shopt -u nullglob
(( ${#screenshots[@]} >= 1 )) || fail "at least one English screenshot is required"
(( ${#screenshots[@]} <= 10 )) || fail "App Store screenshot limit exceeded"

for index in "${!screenshots[@]}"; do
  screenshot_name="$(basename "${screenshots[$index]}")"
  expected_prefix="$(printf '%02d-' "$((index + 1))")"
  [[ "$screenshot_name" == "$expected_prefix"*.png ]] || \
    fail "$screenshot_name is out of sequence; expected prefix $expected_prefix"
  [[ "$screenshot_name" =~ ^[0-9][0-9]-[a-z0-9-]+\.png$ ]] || \
    fail "$screenshot_name must use NN-lowercase-kebab-case.png"
done

checksum_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$checksum_file")"
(( checksum_count == ${#screenshots[@]} )) || \
  fail "SHA256SUMS contains $checksum_count entries for ${#screenshots[@]} screenshots"

(
  cd "$screenshots_dir"
  shasum -a 256 -c SHA256SUMS
) || fail "screenshot checksum verification failed"

for screenshot in "${screenshots[@]}"; do
  width="$(sips -g pixelWidth "$screenshot" | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$screenshot" | awk '/pixelHeight/ { print $2 }')"
  alpha="$(sips -g hasAlpha "$screenshot" | awk '/hasAlpha/ { print $2 }')"
  format="$(sips -g format "$screenshot" | awk '/format/ { print $2 }')"
  color_space="$(sips -g space "$screenshot" | awk '/space/ { print $2 }')"

  [[ "$width" == "1320" && "$height" == "2868" ]] || \
    fail "$(basename "$screenshot") is ${width}x${height}; expected 1320x2868"
  [[ "$alpha" == "no" ]] || fail "$(basename "$screenshot") contains an alpha channel"
  [[ "$format" == "png" ]] || fail "$(basename "$screenshot") is not PNG"
  [[ "$color_space" == "RGB" ]] || fail "$(basename "$screenshot") is not in an RGB color space"

  screenshot_name="$(basename "$screenshot")"
  screenshot_hash="$(shasum -a 256 "$screenshot" | awk '{ print $1 }')"
  grep -Eq "^${screenshot_hash} [ *]${screenshot_name}$" "$checksum_file" || \
    fail "$screenshot_name is missing from SHA256SUMS"
  grep -Fq "$screenshot_hash  $screenshot_name" "$record_file" || \
    fail "$screenshot_name and its checksum are missing from SUBMISSION-RECORD.md"
done

printf 'PASS: automated submission structure and recorded release gates passed; deployed URLs, App Store Connect, and visual truth still require separate live review\n'
