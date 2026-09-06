# Google and Apple source coexistence

## Behavior

Google Calendar, Apple Calendar, Google Tasks and Apple Reminders can remain connected together.
Connecting one source no longer disconnects another source or deletes its imported records.
Connection preferences remain separate, while authorization, sync generations and write-back
routing retain their existing provider boundaries. A disabled source is not automatically enabled
by this change.

Calendar imports remain intact in `AppState.events`. `AppState.presentationEvents` is a read-only
projection consumed by the home timeline, companion context, screensaver context and hardware
snapshot. Google Tasks and Apple Reminders are separate task collections; task titles are never
used to merge them.

An Apple occurrence and a Google occurrence are treated as equivalent only with all of the following:

- The same complete, nonempty external UID (`iCalUID` / `calendarItemExternalIdentifier`).
- Identical start, end and all-day status, keeping recurring occurrences distinct.
- Identical title, description, location, participant names and video meeting URL.

The original records, provider IDs and write-back destinations are preserved. For equivalent
mirrors, a writable Apple copy is preferred when the Google connection is read-only; otherwise
Google is preferred. The projection reads current Google write permission explicitly, so scope
upgrades or downgrades recalculate this choice without changing either original record. Missing
identifiers or divergent content remain visible. In
particular, a stale Google cache cannot hide an Apple edit made while Google is offline. Removing
Google reveals its retained Apple copy without another network fetch. Copies within one provider
and Outlook records are not folded by this policy.

The existing system calendar picker remains the explicit way to exclude overlapping imports that
cannot be matched safely. Its Google-connected state explains this choice. There is no account-name
guessing, title-based deduplication, new OAuth scope or write-back to both providers.

## Firmware boundary

The BLE coordinator freezes `presentationEvents` once, before asynchronous DayPack generation.
That exact array feeds DayPack, Schedule and the structural fingerprint in the same transaction.
The final task-action DayPack uses the same projection.

No `Core/BLE` encoder, command, field, protocol version, event capacity, task identifier, focus
reconciliation rule or firmware document changed. Schedule remains v2 with at most 8 events;
only the App-side selection of equivalent calendar mirrors changes. Existing active-focus and
`RESULT=COMMITTED` gates remain in place.

## Research basis

- [Inku's App Store listing](https://apps.apple.com/us/app/inku-smart-ai-calendar/id6742271746)
  publicly describes calendar aggregation, local calendar sync and merging/splitting duplicate
  events. Its internal matching algorithm is not public; the implementation here does not assume
  how Inku performs matching or copy its wider product scope.
- [Apple: calendarItemExternalIdentifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier?language=objc)
  documents duplicate copies across calendars/sources and shared identifiers for recurring
  occurrences. This motivates retaining source identities and checking the occurrence window.
- [Google: Events resource](https://developers.google.com/workspace/calendar/api/v3/reference/events)
  distinguishes `id` from cross-system `iCalUID`; recurring instances share the latter. Kirole
  retains its existing provider-local IDs and adds the UID only as optional matching metadata.
- [Google: Synchronize resources efficiently](https://developers.google.com/workspace/calendar/api/guides/sync)
  describes full/incremental synchronization and invalid-token recovery. Existing source-owned
  sync state and failure handling remain unchanged; presentation folding never deletes sync data.

## Acceptance boundary

Baseline coexistence verification on 2026-09-07, before the subsequent permission review fix:

- `swift test --package-path KirolePackage`: 1,377 tests across 163 suites passed.
- iPhone 17 Pro / iOS 26.2 simulator: 136 focused tests across 15 suites passed; app rebuilt,
  installed and opened successfully.
- Independent code review: no outstanding findings. `git diff --check` passed.
- UI evidence: [Classic Warm](../test/fixtures/ios-fix/google-apple-coexistence/classic-warm.png),
  [Elegant Purple](../test/fixtures/ios-fix/google-apple-coexistence/elegant-purple.png),
  [Modern Teal](../test/fixtures/ios-fix/google-apple-coexistence/modern-teal.png).

Post-review fixes on 2026-09-07:

- Permission-aware mirror selection: 34 focused regression tests across 8 suites passed on
  macOS; 26 tests across 4 suites passed on iPhone 17 Pro / iOS 26.2 simulator. Coverage includes all Google/Apple write-permission
  combinations, arrival order, scope changes, original source/reference preservation and hardware
  snapshot inputs. The original read-only regression was observed failing before the fix.
- The delivery report generator now resolves its output relative to its own checkout and creates
  the output directory. Running an isolated copy from a different working directory produced a
  readable DOCX in that copy's checkout; the existing report hash remained unchanged.
- Both fixes passed independent review and `git diff --check`. No BLE encoder or protocol changed.
- Final pre-release full run: 1,380 tests across 163 suites passed after both fixes.

One earlier full run at 00:00 hit an existing date-sensitive test:
`FocusTaskOperationPersistenceTests.launchRecoveryDoesNotDuplicateHistory` constructs a session
at `Date() - 120 seconds`, then assumes it belongs to today and indexes `todaySessions[0]`.
Within the first two minutes after midnight this assumption fails. After 00:02, the unchanged
11-test focus-persistence suite and the complete 1,377-test run passed. This test-fixture issue
remains; no focus implementation or test was changed to hide it.

Automated regression coverage includes connection ordering and preference restoration, isolated
disconnects and generations, source-specific merge/write-back, strict mirror matching, offline
content divergence, persistence of optional UID metadata, restoration after disconnect, and
Schedule/DayPack snapshot encoding. Existing BLE protocol and focus-reconnect suites are included.

The iOS test target had an existing `Foundation.Process` compilation failure. Shell-execution
security tests and their helper are now compiled only on macOS; the remaining security tests
still compile on iOS. Google credential cleanup tests require Keychain entitlements unavailable
in the standalone simulator test runner and are validated by the macOS suite.

Simulator screenshots cover the three existing themes and the calendar-selection sheet opens
successfully. The simulator has no authenticated Google/iCloud calendars or working BLE hardware;
these checks do not prove live account synchronization or physical firmware interoperability.

During internal acceptance, exercise both connection orders with real Google and Apple accounts, including
a Google calendar also imported by EventKit, recurring/all-day events, offline Apple edits,
single-source disconnect/reconnect and task completion routed to its original provider. Verify
the existing firmware receives the expected unique Schedule/DayPack data and that focus
reconnection still respects the committed-result gate. Real-account and physical-firmware
acceptance remain outstanding; automated checks alone do not close them.
