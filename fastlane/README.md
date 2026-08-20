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

### ios release

```sh
[bundle exec] fastlane ios release
```

Internal TestFlight pipeline (hardware/firmware acceptance channel): increment build → archive Kirole-Internal (InternalRelease, KIROLE_INTERNAL defined) → upload → set notes → distribute to external groups. NEVER promote this binary to App Store — use the appstore lane from a tagged commit instead (AGENTS.md Release Channel Policy).

### ios appstore

```sh
[bundle exec] fastlane ios appstore
```

App Store candidate pipeline: verify release-channel boundary → increment build → archive Kirole-AppStore (AppStoreRelease, no KIROLE_INTERNAL) → upload binary to App Store Connect. No TestFlight groups, no notes, no beta review. Attaching the build to an App Store version and submitting stays manual, gated on validate-assets.sh submission passing and SUBMISSION-RECORD.md being READY.

### ios notes

```sh
[bundle exec] fastlane ios notes
```

Update TestFlight What to Test notes only (zh-Hans)

### ios finish_external

```sh
[bundle exec] fastlane ios finish_external
```

Finish a release that uploaded+processed OK but died at external distribution (e.g. SSL EOF after Internal distribution). Idempotent: notes upsert + beta-review submit both skip if already done. Operates on the latest build — no archive/upload, no build bump.

### ios status

```sh
[bundle exec] fastlane ios status
```

Verify the latest TestFlight build actually landed: processing state + beta review state. Run after every release — a fastlane 'Done' line alone is not proof (process can be killed mid-upload).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
