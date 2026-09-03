fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios internal

```sh
[bundle exec] fastlane ios internal
```

Internal TestFlight pipeline (hardware/firmware acceptance channel): increment build → archive Kirole-Internal (InternalRelease, KIROLE_INTERNAL defined) → upload → set notes → assign to the manual 'Kirole Hardware Internal' group ONLY. Never reaches external testers and is NEVER promoted to App Store (AGENTS.md Release Channel Policy).

### ios external

```sh
[bundle exec] fastlane ios external
```

External TestFlight pipeline (customer-candidate channel): secure-channel gate → release-boundary gate → increment build → archive Kirole-AppStore (AppStoreRelease, no KIROLE_INTERNAL, internal tools compiled out) → upload → set notes → distribute to every external group + submit Beta App Review. Same configuration as the App Store candidate: submit this build number to the App Store instead of archiving again.

### ios appstore

```sh
[bundle exec] fastlane ios appstore
```

App Store candidate pipeline: secure-channel gate → release-boundary gate → increment build → archive Kirole-AppStore (AppStoreRelease, no KIROLE_INTERNAL) → upload binary to App Store Connect. No TestFlight groups, no notes, no beta review. Prefer promoting the build external testers verified; use this lane only when a fresh archive is required. Attaching the build to an App Store version and submitting stays manual, gated on validate-assets.sh submission passing and SUBMISSION-RECORD.md being READY.

### ios notes

```sh
[bundle exec] fastlane ios notes
```

Update TestFlight What to Test notes only (zh-Hans). Targets build:<number>, else the most recently uploaded build.

### ios finish_external

```sh
[bundle exec] fastlane ios finish_external
```

Finish an external release that uploaded+processed OK but died before distribution (e.g. SSL EOF). Idempotent: notes upsert + beta-review submit both skip if already done. Targets build:<number>, else the most recently uploaded build — no archive/upload, no build bump.

### ios status

```sh
[bundle exec] fastlane ios status
```

Verify the latest TestFlight builds actually landed, per channel: processing state + beta review state for the newest internal-group build and the newest external-group build. Run after every release — a fastlane 'Done' line alone is not proof (process can be killed mid-upload).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
