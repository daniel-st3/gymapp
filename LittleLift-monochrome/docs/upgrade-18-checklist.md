# Build 18 · recovering the gym-start flow

Triggered by the user's report that their chat chose legs while Little Lift showed
upper body, and screenshot import prevented starting. The exact failed screenshot
was not provided. Generic fixtures cannot establish what happened in that image.

## Implementation checklist

- [x] Make Today's saved plan secondary and explicitly distinguish it from a new
  coach recommendation. Put bringing the chat's workout in the primary action.
- [x] Put Screenshot and Paste first in import; move context setup and advanced
  options below. Keep the existing correlated chat and Shortcut flows.
- [x] Handle `3 series × 10` / `2 sets x 12` and wrapped numbered exercise names.
- [x] Retain incomplete numbered exercises for review instead of dropping them.
- [x] Keep unrecognized text editable, explain what is missing and offer a
  copyable formatting request for the existing chat. Never invent a leg routine.
- [x] Keep review/acceptance, original history, signed bundle IDs and pairing.
- [x] Run engine/script tests and both native builds.
- [x] Exercise actual Vision and native paired simulator import → Watch → History.
- [x] Inspect normal/large-text layouts and restore original simulator data.
- [x] Free-signed build, device backup, install and readback when available.

## Verification

- **171 Swift tests / 23 suites and 13 Python tests pass**, plus project checks,
  iPhone/watchOS simulator builds and free-signed device builds. New regression
  cases cover wrapped names, series × reps, incomplete lists with/without a title,
  prose-only recovery, legacy JSON and timed activity compatibility.
- Actual Apple Vision read a generated Spanish chat screenshot with a wrapped
  “Prensa de piernas”, `2 series x 10`, 20 kg, 60 s, and a second exercise. Native
  Photos selection opened the editable preview with those values. Today stayed
  Torso until acceptance; its old plan was retained in routines. Accepted Pierna
  reached the existing paired 46 mm Watch with matching IDs and quantities.
- Native Start, actual 20.5 kg × 11 reps, Log, undo/relog, rest extension/skip,
  next exercise, Summary/Done and History were exercised. Relaunch retained all
  three entries. Replayed delivery was acknowledged without a second record.
- Native Paste of “Hoy toca pierna.” kept the source editable and explained the
  missing exercise details. Copy recovery message produced the Spanish plain-text
  request. It does not send to ChatGPT or target a conversation automatically.
- Actual Today, import, review, recovery, Watch Start/Log/rest/summary and History
  screenshots were inspected. Phone accessibility-medium and Watch XXXL layouts
  kept actions readable/reachable. This increment adds no new animation path;
  the existing Reduce Motion handling remains. No new physical animation/haptic test.
- Original simulator app-owned state/checkpoints/motion files were restored and
  compared: phone unchanged; Watch only snapshot metadata changed. Original text
  size restored, Watch trait override cleared, clipboard cleared, generic photo
  removed from the six-photo library. Pairing never changed.
- Physical iPhone and Watch installed/launched Build 18 using the existing Personal
  Team. Readback matched phone state; Watch only snapshot metadata changed. Four
  additional phone and three Watch app-owned files matched byte for byte. Apple's
  WatchConnectivity transport files are expected to change during communication;
  they are not workout records.

Private logs/fixtures are in `.verification/upgrade-18/` and `BuildLogs/upgrade18-*`;
no personal device data is committed.

## Remaining limits

The user's exact failed image was not supplied; this verifies a representative
format and a recovery path, not every screenshot. The copied formatting request
was checked locally but not executed in live ChatGPT. Existing-chat exchange still
requires explicit copy/paste or screenshot import. Optional Shortcut integration,
physical haptics, motion accuracy and background reliability have no new claims.
No workout is generated from “legs”, and no imported plan replaces Today silently.
