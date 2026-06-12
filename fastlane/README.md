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

Full pipeline: increment build → archive → upload → set notes → distribute to external groups

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
