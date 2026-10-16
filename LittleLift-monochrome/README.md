# Little Lift

**Your workout on your wrist. Your training history on your phone.**

A native SwiftUI workout logger for iPhone and Apple Watch. Start a routine, record the weight and reps you actually do, take your rest, and keep moving. A quiet monochrome interface keeps the next action within reach.

No backend. No ads. No API keys. No paid inference or runtime dependencies.

<p>
  <img src="docs/images/progress.png" width="280" alt="Little Lift Progress with generic recorded workouts">
  <img src="docs/images/watch-logging.png" width="210" alt="Watch logging with fixed weight, repetitions and Log set controls">
</p>

*Actual simulator captures using generic demonstration data.*

## At a glance

| On iPhone | On Apple Watch |
| --- | --- |
| Import text, screenshots or workout JSON | Start, log a set, extend or skip rest |
| Review and edit every plan before saving | Adjust actual load and reps with touch or Crown |
| Keep routines and a weekly schedule | Defer a busy exercise or choose an approved alternative |
| Explore History, Progress and factual reports | Undo, finish early and recover after relaunch |
| Share context with your existing coach chat | Keep logging offline; deliver completed workouts later |

## What’s new in Build 10

**Progress** turns confirmed logs into a simple local dashboard: four- or twelve-week activity, logged sets, training days and typical elapsed session time. Exercise records compare the same variation, unit, load convention and repetition count. Tap a point’s record to inspect its original workout. Imported history stays clearly separate.

**Stronger boundaries** require authentication for Shortcut actions, limit actual bytes read from imported files and photos, validate incoming sync records and reject altered duplicates without replacing the saved original. See [security and privacy](SECURITY.md) for the threat model and practical limits. No software can promise to be unhackable.

The Build 9 visual design remains: Apple serif titles, readable system controls, rounded figures, SF Symbols, calm native transitions and fixed Watch actions. Dynamic Type and Reduce Motion are supported.

## A normal workout

1. On iPhone, import a workout or choose a saved routine. Check its editable preview, then save and send it to Watch.
2. On Watch, tap **Start workout**. Adjust the actual weight and reps, then **Log set**. Rest controls stay visible; other actions live in **…**.
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
- **Optional Shortcut:** Prepare Workout Review → Apple’s Use Model with ChatGPT → Save Workout Review. App Intents are implemented, authenticated and bounded; reviews are tied to attempts so cancelled or stale results cannot replace a proposal. Live model execution still depends on device/account setup and has not been verified. A Shortcut does **not** inherit or target an old ChatGPT conversation.
- **Observations:** coaches may request actual-versus-target sets, trustworthy logging intervals and one optional final-set effort rating. A Log interval includes exercise time; a countdown is prescribed rest. Neither proves actual rest duration.

[Generic import examples](Examples) · [Observation schema](docs/observations.md) · [Upgrade guide](docs/upgrade-guide.md)

## Verify changes

Portable core tests and the repository-boundary check also run in GitHub Actions. Native SDK 27 builds run locally on the Mac.

```sh
swift test
bash scripts/verify-mac.sh
python3 scripts/check_repository.py
```

Build 10 has **92 engine tests** across ten suites, plus **10 launcher tests**. The Mac check also validates project generation, resources and icons, and builds both native simulator apps. See [observed verification](docs/verification.md) for simulator/device evidence and remaining limits.

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
