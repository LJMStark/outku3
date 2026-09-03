# App Store submission record

Status: BLOCKED

The candidate is blocked on the candidate-device smoke test and final App Privacy verification. No pending item below may be changed to PASS without its named evidence.

> **2026-09-03 addendum — Builds 651 and 655 are not releasable.** Both were archived with a non-empty `BLE_SHARED_SECRET` (from `fastlane/.env`) and therefore run in `.secure` mode. Firmware 1.3.1 has never received that secret (BLE protocol §3.3 / §4.17: secure handshake is a second-phase item, never confirmed with the hardware team), so these binaries cannot pair with any device — the "Real-device smoke test: PENDING" line below can never pass. The fail-closed rule was replaced by the firmware-readiness switch `BLE_SECURE_CHANNEL_ENABLED` (currently `0`, AGENTS.md "Release Channel Policy"); the next customer candidate must come from `fastlane ios external`, be verified by external testers on real devices, and be promoted to the App Store by build number.

## Candidate identity

- Candidate date: 2026-08-22
- Release tag: PENDING — create and push the Build 651 tag only after separate approval; `release/appstore-2.0-build-650` is obsolete
- Source commit: `545150129037f196748d744387c56ced1ffc5530`
- Marketing version: 2.0
- App Store build number: 651 — uploaded and processed as VALID
- Bundle identifier: `com.kirole.app`
- Signing team: 93SL23NPNG

## Internal acceptance

- Internal TestFlight build number: 649
- Internal source commit: `8a9c6e3`
- Product features accepted by user: connection, synchronization, and current customer features reported healthy
- Acceptance date: 2026-08-21
- Hardware model: Kirole 7.3-inch E-ink device
- Firmware version: 1.3.1
- Acceptance evidence: user confirmation in the release task; App Store-only exclusions still require the separate candidate smoke test below

## App Store build

- Scheme: `Kirole-AppStore`
- Configuration: `AppStoreRelease`
- Archive path/hash: `/Users/demon/Library/Developer/Xcode/Archives/2026-08-22/Kirole 2026-08-22 10.44.37.xcarchive`; IPA SHA-256 `ba83252763640c8388ea22acb71eef118bcfe0cae879f371ab428e1685584a81`
- `KIROLE_INTERNAL` absent: PASS
- App-target compile-time boundary verified: PASS
- Paired release-gate tests: PASS
- Archived internal-symbol/behavior scan: PASS
- Production security fail-closed check: PASS — empty secret stopped the first attempt; Build 651 uses the current mode-0600, Git-ignored `fastlane/.env` value, whose Base64 text decodes to exactly 32 bytes. Build 650 used an obsolete key and is expired.
- Entitlements checked: PASS — the exported/uploaded IPA includes Apple Sign In, Family Controls, WeatherKit, Hotspot Configuration, Wi-Fi Info, app groups, push, and keychain access; `get-task-allow` is false and `aps-environment` is production. The pre-export `.xcarchive` carries a development signature and is not used as distribution-signature evidence.

## Debug exclusion gates

- Wi-Fi PC Debug absent: PASS
- BLE Keep Alive debug toggle absent: PASS
- Test focus session absent: PASS
- Focus Debug and virtual time absent: PASS
- Raw BLE diagnostic summaries absent: PASS
- Shipping Mode/Wi-Fi factory coordinators and call sites absent: PASS
- Engineering OTA and environment diagnostics absent: PASS

The customer BLE link-retention behavior remains enabled by product policy; only its internal override control is excluded.

## App Store candidate verification

- Automated test command/result: PASS — `swift test --no-parallel`; 1286 tests in 157 suites
- Simulator smoke test: PASS — AppStoreRelease build on iPhone 17 Pro; screenshot flow on iPhone 17 Pro Max
- Real-device smoke test: PENDING — firmware 1.3.1 must first be provisioned with Build 651's current secret; the paired iPhone was also offline at the verification point. Do not use expired Build 650.
- iPhone model and iOS: PENDING — record after candidate-device test
- Hardware model and firmware: Kirole 7.3-inch E-ink device / firmware 1.3.1

## Storefront and policy

- Marketing URL deployed and re-read: PASS — HTTP 200 on 2026-08-22
- Support URL deployed and re-read: PASS — HTTP 200 on 2026-08-22
- Privacy policy deployed and re-read: PASS — HTTP 200 on 2026-08-22; terms also returned HTTP 200
- Enabled provider list matches the binary: PASS
- App Privacy questionnaire matches code and policy: PENDING — final questionnaire check remains
- Apple Weather mark and legal attribution verified: PASS
- Review notes list every new customer-visible feature: PASS — corrected Weather attribution location and read back from App Store Connect on 2026-08-22
- China mainland content/licensing decision: PASS — mainland China remains excluded

## Screenshots

- UI language: English
- Simulator/device details: iPhone 17 Pro Max simulator, iOS 26.2, AppStoreRelease from the candidate source
- Fictional data set: deterministic fictional Apple/Google calendar and task entries dated 2026-08-22; no real account data
- Navigation paths: Home; Kirole companion; Settings scrolled to Focus Protection and Data Sources
- Screenshot filenames and SHA-256 (`<hash><two spaces><filename>`):
  - 3891a8a43cc8c5c304dea56abbcd5073524bd507a7f000c0d97330d752a831d3  01-home-timeline.png
  - 5fe2ec681a0cc06458606051ffc899d05eca11b5668cc7c65817c4fdab35096f  02-pet-today.png
  - 4d07990577a61140ddad7636556f136034c610658de35d8885859a32400a89eb  03-settings-privacy.png
- Screenshot order approved: PASS
- Human visual review (no internal UI or reconstructed components): PASS
- App Store Connect upload/read-back: PASS — 3 screenshots in APP_IPHONE_67

## TestFlight separation note

- Build 651 external TestFlight groups: 0
- Build 651 internal TestFlight groups: 0
- Hardware TestFlight visibility: Build 649 remains assigned to the manual `Kirole Hardware Internal` group (5 testers) and external `kirole` group (4 testers)
- Group policy: the old internal group that automatically accepted every upload was replaced with a manual internal group; Build 651 was removed without changing the external hardware group
- App Store lane behavior: `skip_submission: true` prevents explicit tester distribution, and manual group assignment prevents App Store candidates from replacing the hardware TestFlight build
- Internal release lane behavior: the exact uploaded build number is explicitly assigned to `Kirole Hardware Internal` before external distribution; notes and status read only from that hardware group
- Obsolete build: Build 650 is expired and has zero internal and zero external group relationships
