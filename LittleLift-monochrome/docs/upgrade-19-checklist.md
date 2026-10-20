# Build 19 — a smaller everyday interface

The everyday navigation is Train, History and Settings. No workout schema or engine changes.

## Capability map

- [x] Train: saved workout → exercises, edit, available time and observation requests.
- [x] Train: Watch delivery status → receipt, retry and explanation of active-workout preservation.
- [x] Train: My routines → saved routines, weekly schedule, version history and approved alternatives.
- [x] Train: one primary import action → screenshot / native Paste / editable source; file and manual builder in ….
- [x] History: sessions and imported records remain separate; Progress lives here; corrections in session toolbar.
- [x] Settings: My gym chat, Preferences, My data, Help and Optional tools.
- [x] My gym chat: copy context → paste reply, with sharing controls in toolbar and explicit review before acceptance.
- [x] Preferences: language/feedback, profile, Watch controls, weekly goal.
- [x] My data: backups, history import, sharing preferences and diagnostics.
- [x] Optional tools: separate Shortcut mode/setup, review queue and opt-in motion experiment.
- [x] Watch …: contextual workout actions; preferences contain connection/retry and opt-in motion.
- [x] Fixed Watch workout controls retained. Already-selected routine becomes status rather than an inert button.
- [x] Shared rounded headings, smaller surfaces, consistent rows and existing Reduce Motion-aware native transitions.

## Verification

- [x] Full existing verification script (engine, script tests, phone and Watch SDK builds).
- [x] Native phone route/button interaction and screenshots using isolated fixtures.
- [x] Watch 46 mm: start, log, rest, undo, early finish, completion and preferences.
- [x] Large text / Reduce Motion layouts.
- [x] Original simulator data restored and compared; same simulator pairing.
- [x] Signed device build, fresh backups, in-place installation and data comparison when devices are reachable.

Physical haptics, sensor/background accuracy and live ChatGPT execution are not implied by navigation or simulator checks.

## Observed results and evidence

- 171 Swift tests / 23 suites, 13 Python checks and both simulator SDK builds passed (`BuildLogs/upgrade19-verification.log`). Final phone/calendar revision and Personal Team build also passed.
- Native simulator taps covered the listed navigation destinations, screenshot/file picker opening and cancellation, generic paste → preview → acceptance, chat context copying and report sharing sheet. This pass did not repeat live OCR extraction or a live model response.
- On the existing 46 mm paired Watch: 20.5 kg × 11 repetitions persisted, undo removed the entry, +30 added exactly 30 seconds to the deadline, skip and relaunch worked, full/early completion reached History, and duplicate replay did not duplicate History.
- Dynamic Type and Reduce Motion were enabled and inspected, then restored. A clipped History toolbar label became an accessible icon. Calendar labels now follow the app language and display Monday–Sunday without changing weekday identifiers.
- Fresh simulator backups were restored and compared: phone state matched; Watch differed only in its snapshot timestamp. Auxiliary files matched. Pairing was retained.
- Build 19 installed and launched on both physical devices with the existing Personal Team. Fresh before/after comparisons matched phone and Watch state and all 4 phone / 3 Watch auxiliary files. The final phone calendar correction was installed, launched and compared again successfully.
- Private evidence is under `.verification/upgrade-19/`; only generic screenshots in `docs/images/` are committed.

Subsequent user feedback still reports excessive start/import friction and a failed pasted reply. Build 20 addresses that feedback; Build 19's successful generic cases do not prove that missing real input worked.
