# Build 21 · usable workout acceptance

23 October 2026. Continued the current local Build 20 without replacing the project.
User feedback: missing pounds, unclear incomplete fields, an acceptance button that
appeared inactive, and manually supplying the date. The exact failed reply was not
available; generic regressions reproduce the identified parser and UI failures.

## Completed

- [x] Preserve `lb`, `lbs`, pounds/libras, comma decimals and labelled loads with a missing unit. Negative/range/out-of-bounds values remain visibly invalid rather than disappearing.
- [x] Keep numeric loads when Vision reads `lbs` as `Ibs`/`1bs`; request unit confirmation instead of silently guessing.
- [x] Allow an omitted load to be entered directly in review or chosen on Watch. An unspecified load is not a prescribed zero.
- [x] List all pending exercise decisions. Tapping one or **Review what’s missing** reveals its editable row. The primary button becomes **Use this workout** when valid; storage failures retain error feedback.
- [x] Keep unit selection visible, provide keyboard Done, highlight invalid inputs and preserve the fixed primary action with large text.
- [x] Include the current local date and timezone in the copied coach message. Ask for every previously confirmed load/unit/convention without inventing missing information.
- [x] Treat supported date metadata as source text, not an extra exercise or fabricated historical completion. Actual workout dates come from Start.
- [x] Preserve legacy import/session compatibility, explicit acceptance, original plans, local storage and acknowledgement-based duplicate protection.
- [x] Verify both native builds, actual paired simulator interaction and generic image import.
- [x] Restore original simulator data/preferences, keep pairing, remove the added image and clear fixture clipboard text.
- [x] Install Build 21 with the existing free Personal Team and verify data preservation on both real devices.

## Automated evidence

`BuildLogs/upgrade21-verification.log`: **188 Swift tests in 25 suites + 13 Python tests = 201**, both simulator builds pass. `upgrade21-signed-watch.log` and `upgrade21-signed.log`: both device builds pass. Project regeneration and `git diff --check` pass.

Ten new import-readiness tests cover aliases/decimal loads, unknown load versus missing unit, incomplete JSON and unit conflicts, labelled loads, ambiguous OCR units, date metadata and actual start dates, every invalid row and repair, invalid/mixed targets, persistence/original-plan archiving, and local dates across a UTC boundary, and refreshing an unchanged copied request on another day. The existing negative-load expectation now verifies retention plus rejection rather than erasure. Existing recovery, undo, schema compatibility, evidence and duplicate-delivery tests still pass.

## Observed native simulator flow

Fresh backups and isolated generic fixtures used the existing paired iPhone and 46 mm Watch.

1. Paste opened a three-exercise Pierna preview. The saved Torso plan stayed unchanged. The preview listed all three decisions: a repetition range and two missing units. The existing 80 lb and the explicit 30 with no unit were retained.
2. Confirmed pounds once, tapped **Review what’s missing**, chose 12 reps, and entered the missing third load as 22.5. Keyboard Done and the fixed acceptance action remained accessible. Acceptance saved exactly three exercises with 80/30/22.5 lb and delivered the exact plan to Watch.
3. Start required one tap. Native controls changed the first actual set to **81 lb × 11**, distinct from its **80 lb × 12** target. Relaunch retained it. Rest extension added 30 seconds; skip resumed logging. Three sets completed and Done stayed visible.
4. Phone History displayed one session with all actual values and an automatic date. Replaying the completed session through the Watch outbox cleared after acknowledgement and left exactly one record. Relaunch preserved that result.
5. Actual Apple Vision first exposed the `Ibs` OCR case. After the fix, both the standalone Vision check and native iPhone Photos selection → preview → unit confirmation → acceptance preserved the generic image's **80 and 30 lb**. Existing fixture History remained intact.
6. Accessibility-medium text showed stacked fields, readable repair hints and the fixed primary button. System Reduce Motion was enabled/read back; repair navigation was exercised with it enabled. The prior size and Reduce Motion setting were restored. This is simulator interaction evidence, not a physical animation or haptic measurement.

Selected actual captures (generic data only):

- [Pending fields and repair actions](images/import-missing-build21.png)
- [Screenshot loads retained and ready to accept](images/import-ready-build21.png)
- [46 mm Watch logging](images/watch-log-build21.png)

Additional private captures include input/keyboard, rest, summary, actual History values and large text. Private evidence lives under `.verification/upgrade-21` and `.verification/screenshots`; it is intentionally excluded from Git.

## Preservation and physical delivery

Fresh backups were taken before installation. Xcode initially had no account and expired profiles. After the user's sign-in, both builds signed successfully with the existing Personal Team. The user authorized the renewed developer signature on iPhone; launch then succeeded. Build 21 was read back from both installed apps. No identifier, pairing, enrollment, icon or private refresh script was changed.

The Watch container was recreated during installation. The first listing had no Application Support; after phone sync, a new state had no active session. Work stopped before replacing anything: that new container was backed up and verified to contain no new logged work. The fresh pre-install state, checkpoint and motion files were restored. Read-back confirmed the original active session exactly, with only `lastSnapshotDate` changed; all three auxiliary files matched byte for byte. The phone's final state and four auxiliary files were also compared. Both apps were launched successfully after recovery.

Simulator restoration compared phone state exactly and allowed only the Watch snapshot timestamp to change. Auxiliary files matched. Six original simulator Photos remain; the added generic image was removed. Pair identifiers were compared, and the latest simulator apps were relaunched.

## Limits

- The unavailable original ChatGPT reply/image was not reproduced verbatim. Different screenshots and unsupported formats can still require correction. The source stays available in review.
- The improved prompt cannot force ChatGPT to include a value. Little Lift cannot retrieve omitted values from a private conversation it does not read. Missing loads stay editable or explicitly unspecified.
- Ordinary workout date is automatic; importing historical records still requires the actual historical date. A date printed in a proposed routine is not proof it was completed then.
- Mixed strength units still require an explicit consistent choice; no silent conversion was added.
- No new claim of physical haptics, wrist-down capture, exact existing-chat opening, live model compliance or unattended Shortcut automation. The two ChatGPT workflows remain separate and explicit.
- Free signing remains time-limited. Renewed profiles in this delivery expire on 30 October 2026. Back up app-owned data before future refreshes and read it back afterward; an install success alone does not prove preservation.
