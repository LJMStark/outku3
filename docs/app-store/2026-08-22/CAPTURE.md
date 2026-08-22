# App Store candidate archive and screenshot procedure

This is a template for the first candidate produced after the two distribution configurations exist. Build 644 is historical failure evidence only. Do not use the old shared `Kirole` / `Release` archive as an App Store candidate.

## Historical diagnosis

- Product version: Kirole 2.0
- Historical build: 644
- Source checkpoint reviewed on 2026-08-14: `fd56bf7`
- Reference simulator: iPhone 17 Pro Max, English UI, 1320 × 2868 portrait output
- Confirmed failure: `AppBuildEnvironment.showsHardwareDebugTools` was always `true`; the active focus screen displayed `Focus Debug` and the Release code path retained other hardware-debug behavior.
- Historical screenshots were withdrawn because technical dimensions did not establish UI or narrative accuracy.

Do not reproduce this old Debug build for store capture. Create a new dated candidate directory after the release boundary is implemented.

## Required candidate inputs

Before archiving, fill the copied `SUBMISSION-RECORD.md` and make sure all of these are available:

- A reviewed release tag whose commit is the current `HEAD`.
- `Kirole-Internal` / `InternalRelease` and `Kirole-AppStore` / `AppStoreRelease`.
- Explicit user acceptance of the product features in the recorded Internal TestFlight build.
- Passing paired release-gate tests for Internal-present and App-Store-absent behavior.
- Production secrets/configuration validated without printing their values.
- A clean source tree for `Config`, the app shell, Xcode project/workspace, extensions, and `KirolePackage`.
- Updated website/privacy source ready for deployment; deployed URLs are verified separately before submission.

## App Store archive gate

Run from the repository root. Replace the tag and candidate directory placeholders; never paste secrets into the record or terminal transcript.

```bash
set -euo pipefail

release_tag="REPLACE_WITH_RELEASE_TAG"
candidate_root="docs/app-store/REPLACE_WITH_CANDIDATE_DATE"
app_store_scheme="Kirole-AppStore"
app_store_configuration="AppStoreRelease"

test "$(git rev-parse --show-toplevel)" = "$PWD" || {
  printf 'Run this procedure from the repository root.\n' >&2
  exit 1
}
test "$release_tag" != "REPLACE_WITH_RELEASE_TAG" || {
  printf 'Set the reviewed release tag.\n' >&2
  exit 1
}
test "$candidate_root" != "docs/app-store/REPLACE_WITH_CANDIDATE_DATE" || {
  printf 'Set a new dated candidate directory.\n' >&2
  exit 1
}
test "$(git rev-parse "$release_tag^{commit}")" = "$(git rev-parse HEAD)" || {
  printf 'HEAD does not match the reviewed release tag.\n' >&2
  exit 1
}
test -z "$(git status --porcelain -- Config Kirole Kirole.xcodeproj Kirole.xcworkspace KiroleDeviceActivityMonitor KirolePackage)" || {
  printf 'App source paths must be clean before archiving.\n' >&2
  exit 1
}
test -f "Kirole.xcodeproj/xcshareddata/xcschemes/${app_store_scheme}.xcscheme" || {
  printf 'The App Store scheme has not been implemented.\n' >&2
  exit 1
}
grep -q 'AppStoreRelease' Kirole.xcodeproj/project.pbxproj || {
  printf 'The App Store build configuration has not been implemented.\n' >&2
  exit 1
}

build_conditions="$(
  xcodebuild \
    -workspace Kirole.xcworkspace \
    -scheme "$app_store_scheme" \
    -configuration "$app_store_configuration" \
    -showBuildSettings |
    sed -n 's/^[[:space:]]*SWIFT_ACTIVE_COMPILATION_CONDITIONS = //p'
)"
if [[ "$build_conditions" == *KIROLE_INTERNAL* ]]; then
  printf 'KIROLE_INTERNAL leaked into AppStoreRelease.\n' >&2
  exit 1
fi

archive_path="/tmp/Kirole-AppStore.xcarchive"
xcodebuild archive \
  -workspace Kirole.xcworkspace \
  -scheme "$app_store_scheme" \
  -configuration "$app_store_configuration" \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path"
```

Record the release tag, full commit, version, build number, archive path, and gate results in `SUBMISSION-RECORD.md`. A successful `xcodebuild archive` is not proof that internal code is absent.

## Archived-binary verification

Verify the archived App itself before taking screenshots:

1. `KIROLE_INTERNAL` is absent from the App Store build settings and the condition has been proven to reach `KirolePackage` in the Internal build.
2. Wi-Fi PC Debug, BLE Keep Alive, test focus sessions, Focus Debug/virtual time, raw BLE summaries, Shipping Mode, engineering OTA, and environment/source diagnostics are absent.
3. The related service behavior is disabled: no debug keep-alive default, Wi-Fi Debug query, virtual-time mutation, factory command, or debug logging remains active.
4. Production BLE/security configuration passes its fail-closed check without revealing secret values.
5. Version, build number, bundle identifier, signing team, entitlements, and archive commit are the intended App Store values.
6. App Store negative tests and a real-device smoke test pass for this exact candidate.
7. Every screen that displays WeatherKit data provides the required Apple Weather mark and legal attribution link.

Record each result explicitly. Do not use “archive succeeded” or an Internal TestFlight pass as a substitute.

## App Store simulator capture

The screenshot build must use the same release-tag commit and App Store configuration as the archive.

```bash
set -euo pipefail

release_tag="REPLACE_WITH_RELEASE_TAG"
app_store_scheme="Kirole-AppStore"
app_store_configuration="AppStoreRelease"
derived_data_path="/tmp/kirole-app-store-capture"

test "$release_tag" != "REPLACE_WITH_RELEASE_TAG" || {
  printf 'Set the same reviewed release tag used for the archive.\n' >&2
  exit 1
}
test "$(git rev-parse "$release_tag^{commit}")" = "$(git rev-parse HEAD)" || {
  printf 'HEAD does not match the reviewed release tag.\n' >&2
  exit 1
}
test -z "$(git status --porcelain -- Config Kirole Kirole.xcodeproj Kirole.xcworkspace KiroleDeviceActivityMonitor KirolePackage)" || {
  printf 'App source paths changed after the archive.\n' >&2
  exit 1
}

xcodebuild \
  -workspace Kirole.xcworkspace \
  -scheme "$app_store_scheme" \
  -configuration "$app_store_configuration" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath "$derived_data_path" \
  build
xcrun simctl install \
  'iPhone 17 Pro Max' \
  "$derived_data_path/Build/Products/AppStoreRelease-iphonesimulator/Kirole.app"
xcrun simctl launch \
  --terminate-running-process \
  'iPhone 17 Pro Max' \
  com.kirole.app
```

Use fictional English data with no personal information. Capture only pages reachable in the App Store build. Do not use hidden test launch arguments, reconstructed UI, or a Debug/Internal binary.

For each screenshot:

```bash
xcrun simctl io \
  'iPhone 17 Pro Max' \
  screenshot \
  "$candidate_root/screenshots-en/01-home.png"
sips \
  -g pixelWidth \
  -g pixelHeight \
  -g hasAlpha \
  -g format \
  -g space \
  "$candidate_root/screenshots-en/01-home.png"
shasum -a 256 "$candidate_root/screenshots-en/01-home.png"
```

Keep the complete App screen. Marketing copy may be placed outside the captured screen, but App components must not be cropped, rearranged, enlarged to hide truncation, or recreated.

## Hardware-only pages

The active focus page and other hardware-triggered states cannot be accepted from an iOS simulator. Capture them only from a physical iPhone running the exact App Store candidate and paired with accepted firmware. Record:

- iPhone model and iOS version;
- App version, build, and release commit;
- hardware model and firmware version;
- exact navigation/device event;
- debug-gate result;
- original screenshot filename and SHA-256.

Simulator output is not hardware or firmware acceptance evidence.

## Final package

1. Put approved English screenshots in `screenshots-en/`.
2. Generate `screenshots-en/SHA256SUMS` from the reviewed files.
3. Finish `SUBMISSION-RECORD.md`, change its status to exactly `READY`, and remove every `TBD`/placeholder.
4. Run `./validate-assets.sh package`.
5. Complete the manual visual-review fields in `SUBMISSION-RECORD.md`, then run `./validate-assets.sh submission`; it must pass without weakening any check. The script validates structure and recorded gates, but it cannot judge whether a screenshot visually reconstructs or misrepresents the App.
6. Re-read the deployed marketing, support, and privacy URLs. Local website files are not deployment proof.
7. Recheck App Store Connect metadata, App Privacy, entitlements, selected build, review notes, and screenshot order separately.
