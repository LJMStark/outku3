# Kirole 2.0.2 screenshot update

Status: WAITING_FOR_REVIEW

## Authorized scope

The user requested redesigned screenshots, replacement after dimension verification, and App Review submission. This release preserves the features of already approved version 2.0.1. It does not promote the Outlook work currently on main. Build 660 is INTERNAL_ONLY and is excluded from submission.

## Source and candidate

- Baseline: `f314175157e6cf38592d94ddedbcc57133786a56`, recorded release source for 2.0.1 (659).
- Baseline archive: `/Users/demon/Library/Developer/Xcode/Archives/2026-09-04/Kirole 2026-09-04 13.03.40.xcarchive`.
- Baseline archive identity: 2.0.1 / 659 / `Kirole-AppStore`; corresponding gym log confirms `AppStoreRelease` and `BLE_SECURE_CHANNEL_ENABLED=0`.
- Source provenance is based on the release commit, archive identity and build log; no embedded Git SHA was found in the old archive.
- Isolated checkout: `/Users/demon/vibecoding/outku3-worktrees/app-store-screenshots-2.0.2`, branch `codex/app-store-screenshots-2.0.2`.
- Intended changes from the approved source: marketing version and build number only. No App feature implementation changes.
- Reverified on 2026-09-07 against live ASC 2.0.1 (659): the candidate commit changes only `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` in `Kirole.xcodeproj/project.pbxproj` and `CFBundleVersion` in `KiroleDeviceActivityMonitor/Info.plist`. Application source, package source, tracked configuration, dependencies, entitlements and workspace contents have no diff.
- Candidate channel: `Kirole-AppStore` / `AppStoreRelease`.
- Candidate build: 2.0.2 (661).
- Candidate source commit: `88e7a60f7a5e1fc95e99bd99ac26dcdcbc57d417`.
- Local release tag: `release/appstore-2.0.2-build-661`. No Git push performed.
- Candidate archive: `/Users/demon/Library/Developer/Xcode/Archives/2026-09-07/Kirole 2026-09-07 01.43.33.xcarchive`.

## Verified

- Baseline package tests: 1306 tests in 157 suites passed with `swift test --no-parallel` on 2026-09-07.
- Three replacement PNGs: 1320×2868, RGB, no alpha; file checksums in `screenshots-en/SHA256SUMS`.
- Source screenshots match the three live 2.0.1 screenshot checksums. The surrounding layout is new; App components were not reconstructed.
- User authorized replacement after reviewing the delivered preview and requesting dimension verification.
- ASC 2.0.2 screenshot set: exactly three replacement files, intended order, all `COMPLETE`, all MD5 checksums match local output. Identifiers in `asc-readback.json`.
- Support, privacy and terms endpoints: HTTP 200.
- en-US What's New and App Review notes explicitly describe a screenshot-only update with unchanged features and data sources.

## Checks before submission

- Paired release-channel build and boundary gate: PASS; both distribution configurations built, Internal markers and factory implementations present only in Internal, approved FocusReconnect anomaly category retained, engineering resources excluded from AppStore.
- Customer archive identity, signing and absence of internal capabilities: PASS. Main app and extension are 2.0.2/661; strict signature verification passed; both have get-task-allow=false; main app push environment is production. Internal markers, specified factory symbols and engineering resources are absent. IPA/dSYM UUIDs match.
- IPA SHA-256: `0c683a01664e047209199db0ca8f47c2e32687fa4d7e289bace766c2cf0bcb37`.
- ASC customer build processing and binding: PASS. Build `60fcb5e8-6a26-4803-a529-ece0981f0424` is 661, VALID, APP_STORE_ELIGIBLE, non-exempt encryption false, and bound to 2.0.2.
- Candidate real-device smoke: WAIVED BY USER on 2026-09-07 after verifying application code is unchanged from approved 2.0.1 (659). The user explicitly instructed that no new real-device acceptance is needed if code is unchanged. The complete Git diff satisfies that condition. No installation or application data changes were made on the connected iPhone 12 Pro Max; its Build 662 remains installed. This is a scoped acceptance exception, not a PASS result for a real-device test.
- Candidate simulator smoke: PASS for launch and Home / Companion / Settings navigation on iPhone 17 Pro, iOS 26.2, AppStoreRelease 2.0.2(661). No crash observed; Settings accessibility tree exposes the four approved sources, focus modes and weather attribution without internal tools. Simulator source accounts show permission/sync errors, so successful calendar sync is not claimed. This is not real-device or BLE evidence.
- Apple review submission: `0352112a-ed0a-4047-a3ba-0d83ca5ddc4a`; its only item is 2.0.2.
- Final App Review request: PASS. Submitted at 2026-09-07 08:24:47 Asia/Shanghai. Independent GET read-back confirms both version 2.0.2 and its review submission are `WAITING_FOR_REVIEW`, with Build 661 still bound. All three screenshots remain COMPLETE with exact checksums. See `submission-readback.json` for current evidence; `asc-readback.json` retains the earlier screenshot-upload snapshot.

## Historical validator scope

The 2026-08-22 validator hard-codes the eight-file shape of its historical package and exact historical metadata headings. This editable-artwork package uses a different structure. Its old release record is not updated or marked READY. Current submission evidence is recorded here, including the real existing release-boundary script; no historical acceptance result is fabricated or used as proof of a new candidate's device behavior.
