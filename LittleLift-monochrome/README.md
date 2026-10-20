# Little Lift

**Your workout on your wrist. Your training history on your phone.**

A native SwiftUI workout logger for iPhone and Apple Watch. Start a routine, record the weight and reps you actually do, take your rest, and keep moving. A quiet monochrome interface keeps the next action within reach.

No backend. No ads. No API keys. No paid inference or runtime dependencies.

<p>
  <img src="docs/images/progress.png" width="280" alt="Little Lift Progress with generic recorded workouts">
  <img src="docs/images/watch-logging.png" width="210" alt="Watch logging with fixed weight, repetitions and Log set controls">
</p>

*Actual simulator captures from Build 10 using generic demonstration data. Current verification is documented below.*

## At a glance

| On iPhone | On Apple Watch |
| --- | --- |
| Import text, screenshots or workout JSON | Start, log a set, extend or skip rest |
| Review and edit every plan before saving | Adjust actual load and reps with touch or Crown |
| Keep routines and a weekly schedule | Defer a busy exercise or choose an approved alternative |
| Explore History, Progress and factual reports | Undo, finish early and recover after relaunch |
| Share context with your existing coach chat | Keep logging offline; deliver completed workouts later |

## What’s new in Build 18

**Today → Bring workout from chat** puts Screenshot and Paste first. Today and
Watch label the stored workout explicitly; an old upper-body plan is not presented
as a new recommendation from a chat. Advanced setup stays below the import actions.

Screenshot/text extraction now accepts `3 series × 10` and wrapped numbered names.
Incomplete numbered exercises stay in review, including when there is no title.
When the source contains only something like “today is legs”, the app keeps the
text editable and offers a copyable request for a simpler response from the same
chat. It does not invent the routine. Saving still requires review and acceptance.

**Verified:** 171 engine tests / 23 suites, 13 script tests, both simulator builds
and free-signed device builds. Actual local Vision and native photo selection →
review → Watch start/log/rest/undo → single History delivery/relaunch passed with
isolated data. Duplicate delivery, recovery feedback and large text were checked.
Both real apps installed/opened with app-owned data preservation checked. The exact
failed gym screenshot and a live response to the new formatting prompt remain
unverified. [Build 18 evidence and limits](docs/upgrade-18-checklist.md).

## What’s new in Build 17

**Today → My gym chat** prepares a context message for the gym conversation you already
use. Copy it there, bring back the reply, review/edit the workout, then accept and send
to Watch. The app shows copied, accepted and new-data states without claiming to read
or message your conversation. Linked replies reject stale or repeated requests;
ordinary text/image/JSON imports remain available.

Fixed blank first-paste presentation, disappearing import errors, Add routine replacing
Today, nested import/proposal navigation, Shortcut retry feedback, and action errors
hidden behind sheets. Watch actions and monochrome styling stay intact.

**Verified:** 167 engine tests / 22 suites, 13 script tests, both simulator builds and
free-signed device builds. Native phone/46 mm Watch import, editing, acceptance, logging,
rest, undo, early finish, History, duplicate delivery and relaunch passed with isolated
fixtures. Build 17 installed and opened on both real devices with data preservation
checked. A fresh live ChatGPT prompt test was blocked by Apple's Shortcut signing 502;
that result is not claimed as verified. [Chat guide](docs/gym-chat.md) ·
[full action coverage and limits](docs/upgrade-17-checklist.md).

## What’s new in Build 16

The gym-start flow now makes the **saved workout** explicit. If your coach says
“legs” and the app still holds “upper body”, **Change workout → Screenshot or
Paste → Review → Use workout** brings the coach’s message into Today and sends
it to Watch. Little Lift does not read or synchronize a private chat automatically.

- Screenshots and Paste open a compact editable preview directly. Multiline,
  numbered Spanish/English exercise blocks keep names and explicit targets.
- Choose missing units/rest once; resolve repetition ranges in place. An absent
  load can be chosen during ordinary Watch logging, without inventing a zero
  target or requiring technical variation identifiers.
- A new plan offers an explicit switch from a Watch session with no recorded
  work. Logged work stays attached to its original plan. Previous Today remains
  available as a routine.

**Verified:** 161 engine tests / 21 suites, 13 script tests, both simulator builds,
free-signed device build, real Vision on a generic chat image, and native import →
accept → Watch logging → single History delivery → relaunch. Phone accessibility
text and 46 mm Watch layouts were inspected. Build 16 is installed and opened on
both physical devices; backed-up workout/checkpoint/motion data was preserved.
The exact failed gym screenshot was not supplied; arbitrary screenshots and
physical haptics/background behavior are not certified by these tests.
[Build 16 checklist](docs/upgrade-16-checklist.md) · [verification](docs/verification.md).

## What’s new in Build 15

- Switch the **remaining sets** to a previously approved machine after starting an exercise. Keep the original sets, rest and prescription; separate variation history, undo and recovery stay intact.
- Import labelled tables and multiline Spanish workout text. Review ranges and missing values explicitly. OCR preserves empty columns instead of shifting numbers; the editor names fields needing a decision. [Examples](docs/smart-import.md).
- Reject ambiguous/deep JSON, oversized files, forged substitutions and stale replies. On-device model extraction cannot silently supply unsupported numeric targets. [Security boundaries](SECURITY.md).
- Test the optional coach connection with **fictional data only**. The prepared ChatGPT Shortcut returned a validated receipt on the real iPhone after user authorization. The same screen shows the result; personal history and Today remain unchanged.

**Verified:** 153 engine tests, 13 script tests, native iPhone/46 mm Watch flows, real Vision OCR, both simulator builds and free-signed device builds. Build 15 is installed and opened on both actual devices with data preservation checked. Notification-driven unattended review, wrist-down reliability, haptic feel and sensor accuracy remain separate unverified checks. See the [Build 15 checklist](docs/upgrade-15-checklist.md) and [verification record](docs/verification.md).

## What’s new in Build 14

Keep a portable backup from **Settings → Backups**, preview what restoration will add, and retain current records when IDs conflict. Repeating a restore does not duplicate workouts. Today stays unchanged; the archived plan becomes a routine. A damaged local file can be recovered explicitly while its original bytes are preserved separately. Backups contain personal training data and are not encrypted by Little Lift; experimental motion recordings and Apple permissions are excluded.

Correct an accidental load or repetition entry from **History → workout → Correct record**. The original Watch record, targets and timing remain intact. Reports, Progress and local comparisons use the corrected values and show the audit trail. Older coach responses remain available but are marked outdated; in-flight review receipts are revoked. Reversing a correction means recording another correction, not deleting the original.

Today now separates **Saved on iPhone**, **Received on Watch** and **Workout saved · review ready**. A saved-plan receipt is not a claim of a live connection. Setup stays on iPhone; ordinary Watch logging needs no new taps.

**Verified:** 142 engine tests in 19 suites, 12 script tests, both simulator builds, free-signed device builds, and native phone/46 mm Watch flows using isolated generic data. Native Files export/import, duplicate/conflict handling, correction persistence, damaged-file recovery and future-format refusal were exercised. Original simulator data and accessibility settings were restored. Build 14 is installed and opened on both real devices with the existing free signing; post-launch readback preserved original workout, checkpoint and motion data. See the [Build 14 checklist](docs/reliability-14-checklist.md) and [verification record](docs/verification.md).

## What’s new in Build 13

Coach responses now stay with their workout after a proposed plan is accepted or discarded. Imported responses without a workout receipt remain clearly separate. Another result cannot silently replace a proposal you are reviewing. Opening a workout text/JSON file takes you directly to an editable preview; saving remains explicit.

Time estimates no longer count the current rest twice or add rest after the final set. Watch runtime resume/recovery and experimental motion interruption handling are more robust. Review input now includes original exercise identifiers, matched comparisons and recorded logging intervals, keeping them distinct from actual rest.

**Verified:** 130 engine tests, 12 script tests, both simulator builds, native paired 46 mm Watch workflows and a real ChatGPT extension response on this Mac using generic data. The response passed Little Lift’s receipt, duplicate, acceptance and persistence checks. The prepared Shortcut now explicitly selects ChatGPT; its signed file is available in the real phone’s setup screen.

Build 13 was installed and launched on both real devices, with backed-up workout/checkpoint/motion data checked afterward. See the [Build 13 audit](docs/audit-13-checklist.md), [delivery evidence](docs/verification.md) and [all 27 requirements](docs/feedback-27.md) for the final artifact status and remaining limits. Mac model execution does not establish unattended iPhone execution, search access or delivery to an existing chat. Physical wrist-down/haptic/sensor claims remain unverified.

## What’s new in Build 12

Every completed workout now has an automatic review inside Little Lift: prescribed targets, actual logged values, coach observations and exact matching earlier sets. It is calculated from your saved records, works offline and needs no account or Shortcut setup. Missing evidence stays explicit; logging intervals are never called actual rest. Open it from Today, History or Workout reviews.

Search exercises from your own plan and routines alongside the local guide. Optional ChatGPT attempts expire safely if no result returns; the local review remains available. A rapid second Log touch no longer dismisses the newly opened Watch summary, and a review stays on the selected workout when another arrives.

Rhythm pulses can remain eligible while an actual HealthKit workout is running, including when the scene is inactive. Pause, interruption, completion, changed sets and disabled haptics stop them. Physical wrist-down behavior and haptic feel still require observation. This is a metronome, not a repetition detector.

Build 12 was installed and launched on the real iPhone and paired Watch with the existing free signing. Post-launch readback preserved the original state, active Watch session and motion files; no restore was needed.

See the [Build 12 checklist](docs/in-app-12-checklist.md) and [all 27 requirements](docs/feedback-27.md). The local factual review does not represent a ChatGPT response or an automatic connection to your existing conversation.

## What’s new in Build 11

Workouts can mix strength, walking, running and mobility. Cardio has its own Start/Pause/Resume/Done flow, optional machine readings and explicit timing; it never asks for invented repetitions or load. The editable importer accepts schema 2 and continues to read existing JSON. Try the [generic mixed workout](Examples/mixed-workout.json), marked as practice.

On Watch, defer partly completed exercises, choose the next one, confirm an approved substitute, or use a separate machine-change timer. The original prescription and actual results remain distinct. A real HealthKit workout session supports the official workout runtime; manual logging still works when permission or runtime fails. Wrist-raise return still needs physical verification.

Spanish and English, sober native system typography, compact progress and fixed primary actions keep the interface readable. iPhone adds editable coach context, a small exercise-help catalog, a local [getting-started guide](docs/onboarding/index.html), optional weekly goals and planned pauses. Optional rhythm pulses are a metronome, **not** repetition detection. Water reminders and factual feedback can be disabled.

Build 10’s local Progress dashboard, authenticated Shortcut actions and bounded input validation remain. Versioned storage refuses unknown future formats and preserves a protected pre-upgrade checkpoint. See [security and privacy](SECURITY.md); no software can promise to be unhackable.

Every requirement has its own status and evidence in [F01–F27](docs/feedback-27.md). Live ChatGPT, exact-thread delivery, physical haptics and repetition accuracy are not claimed verified. No app, site or personal data was published.

Build 11 was installed and launched on the real iPhone and paired Watch with free Personal Team signing on 17 October. Post-launch comparison confirmed data preservation after a Watch backup restoration; see the [delivery evidence and remaining limits](docs/verification.md).

## A normal workout

1. On iPhone, import a workout or choose a saved routine. Check its editable preview, then save and send it to Watch.
2. On Watch, tap **Start workout**. For strength, adjust actual weight/reps and **Log set**. For cardio, **Start activity**, pause when stopped, then **Done**. Rest controls stay visible; the branch button changes exercise and **…** holds details, undo and early finish.
3. Tap **Done** after finishing. The phone saves the completed workout before acknowledging it. History, Progress and coach reports then use the actual logged values.

No workout is silently shortened or replaced. Optional-work changes and approved substitutions preserve the original prescription. Coach proposals require acceptance.

## Run the project

Open `LittleLift.xcodeproj` in Xcode. The current source is verified with **Xcode 27**; deployment targets are iOS 18 and watchOS 11. Newer OS features are availability-gated. The optional Foundation Models path needs a compatible Apple Intelligence device; ordinary parsing, local Vision OCR and manual editing remain available without it.

For an existing paired simulator setup, double-click **Run Little Lift.command**, or run:

```sh
python3 scripts/run_simulators.py
```

The launcher preserves pairing and app data. Its explicit demo option populates only an empty phone install with a generic example.

For real devices, use Xcode’s free Personal Team signing. Keep private bundle/team overrides in `Config/Local.xcconfig`, based on the example file. Existing installations must keep their original identifiers and signing configuration. Refresh expiring personal profiles by updating in place; **do not uninstall**, because uninstalling removes local data. No paid developer enrollment or app publication is required. The owner’s private refresh script is deliberately excluded from this repository.

## Coach workflows

- **Existing conversation:** share a workout report or compact context export into your chosen chat, then import its proposed workout for review. This preserves continuity through explicit sharing.
- **Optional Shortcut:** Prepare Workout Review → Apple’s Use Model with ChatGPT → Save Workout Review. App Intents are implemented, authenticated and bounded; reviews are tied to attempts so cancelled or stale results cannot replace a proposal. The native simulator ran Prepare, then Use Model reported “This action is not currently available.” Live model execution and unattended automation remain unverified on the physical account. A Shortcut does **not** inherit or target an old ChatGPT conversation.
- **Observations:** coaches may request actual-versus-target sets, trustworthy logging intervals and one optional final-set effort rating. A Log interval includes exercise time; a countdown is prescribed rest. Neither proves actual rest duration.

[Generic import examples](Examples) · [Observation schema](docs/observations.md) · [Upgrade guide](docs/upgrade-guide.md)

## Verify changes

Portable core tests and the repository-boundary check also run in GitHub Actions. Native SDK 27 builds run locally on the Mac.

```sh
swift test
bash scripts/verify-mac.sh
python3 scripts/check_repository.py
```

Build 12 passes **121 engine tests** across sixteen suites, plus **10 launcher tests**. The Mac check also validates project generation, resources and icons, and builds both native simulator apps. See [observed verification](docs/verification.md) for simulator/device evidence and remaining limits.

After adding or removing native Swift files:

```sh
python3 scripts/generate_project.py
```

## Project map

```text
Apps/iPhone/          Import, routines, History, Progress, coach review
Apps/Watch/           Fixed workout controls, rest, recovery, optional motion
Apps/WatchLauncher/   Watch-face launcher
Apps/Shared/          Visual components and paired-device transport
Sources/WorkoutCore/  Foundation-only engine, validation, storage, analytics
Tests/                Portable engine regression tests
Config/               Public defaults and ignored local signing overrides
Examples/             Generic workout and historical-record fixtures
scripts/              Build checks, simulator launcher and project generation
docs/                 Design decisions, verification and feature status
```

## Privacy and experimental features

Workout files remain in app-local protected storage; normal device backup settings may include them. Data leaves Little Lift when you explicitly share it or run an external Shortcut. Motion recordings are excluded from backup. There is no telemetry service behind the Progress screen.

Motion replay is **opt-in and experimental**, limited to short captures for a few exercises. Suggestions require confirmation. Wrist-down reliability, battery use and repetition accuracy remain unvalidated; motion cannot measure external weight or certify safe technique. Physical haptics, hardware double tap, locked notifications and live ChatGPT are not claimed as verified by simulator testing.

[Feature checklist](docs/upgrade-checklist.md) · [Motion feasibility](docs/motion-feasibility.md) · [Engineering invariants](docs/engineering.md)

## Credits

Native system fonts and SF Symbols are provided by Apple; the monochrome app icon is preserved in `Design/Brand`. The vendored SwiftUI expert guidance retains its upstream MIT license. Project source uses the [MIT license](LICENSE).
