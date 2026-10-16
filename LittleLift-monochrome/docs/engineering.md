# Engineering choices

The user wants a small, native watch workout logger that fits an existing ChatGPT coaching workflow. The implementation has no third-party runtime dependencies and no backend.

## Guidance and skills

- [AvdLee SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill): selected references bundled in `.agents/skills/swiftui-expert-skill` under the upstream MIT license. Consulted for owned vs injected observable state, small invalidation boundaries, native scroll views, scoped animations, Reduce Motion, and accessible controls. This is an upstream snapshot taken on 2026-10-15, not a claim that the entire remote skill package is bundled.
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/wcsession): application context for the current plan and receipts; background user-info transfers for completed workouts.
- [Apple haptics](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)): set logged, workout start/end, and rest-finished cues.
- [Apple local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app): rest cues while the app is not in the foreground. Delivery depends on notification permissions and system settings.
- [Apple App Intents](https://developer.apple.com/documentation/appintents): Shortcuts actions expose workout context and save a proposed review. No direct OpenAI networking exists in this app.
- [Apple Shortcuts Use Model](https://support.apple.com/guide/shortcuts/use-apple-intelligence-in-shortcuts-tpg3vrvwmclv/ios): users configure the ChatGPT extension model in their own Shortcut. It is not replaced with a developer-billed API.

GSAP is a browser animation library. Adding a web runtime to a watch logger would add complexity without helping the native controls. Animations here are short SwiftUI press/number transitions, disabled under Reduce Motion. The rest clock is an isolated TimelineView rather than a timer that invalidates the whole app every second.

## Compact monochrome layout

The current user preference supersedes the earlier blue/red palette: the app uses white and neutral gray on black. Main watch screens share `WatchPage`, whose fixed action row is a sibling of the adaptable content, outside any ScrollView. `ViewThatFits` shows compact content directly when it fits; an internal scrolling fallback supports larger text while keeping the action row visible. The full exercise list, previous results, undo, and early finish live in a neutral **…** options sheet. Rest progress is a two-point gray line, with no system-tinted progress capsule or always-visible destructive toolbar control.

The phone uses a bottom safe-area inset for Send to watch and Import workout, above its native tab bar. Self-contained Xcode previews exercise the real set and rest panels without starting a store or a WatchConnectivity session. These previews and the target watch layout still require rendering on the Mac; Linux syntax/structure checks do not prove their measured fit.

Apple references: [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits) and [watchOS toolbar placement](https://developer.apple.com/documentation/watchos-apps/creating-an-intuitive-and-effective-ui-in-watchos-10).

## Build 6 update

The current project was built and tested on this Mac with Xcode 27 and installed in place using the existing Personal Team. See [the delivery checklist](upgrade-checklist.md) and [verification](verification.md) for measured results. The Foundation-only core now includes compatible observation schemas, routines/history/context, adaptive execution, review receipts and experimental motion file validation. HealthKit is enabled only for explicit motion tests; ordinary logging remains independent. Setup and analysis stay on iPhone, and Watch options are short links to secondary controls.

## Structure

- `Sources/WorkoutCore`: value models, validation, session state machine, atomic JSON storage, reports, prompts, and transport encoding.
- `Apps/Shared`: styling and the WatchConnectivity delegate.
- `Apps/iPhone`: import/preview, history/export, training profile, proposed-review approval, and App Intents.
- `Apps/Watch`: workout/rest/summary views, persisted session recovery, Crown input, haptics, local notifications, and durable outbound queue.
- `Tests/WorkoutCoreTests`: meaningful state transitions and failure scenarios, including the complete portable import → log → persist/relaunch → transfer → deduplicate → acknowledge → report flow.

The iPhone and watch targets compile the same `Sources/WorkoutCore` files directly. The root Swift package remains the standalone test harness; it is not an Xcode package dependency. This avoids the original generated project's unresolved `WorkoutCore` module and removes package-resolution steps from first launch. No source files are duplicated.

## Delivery invariants

1. Each session takes an immutable snapshot of its plan. Receiving a new plan cannot change an in-progress workout.
2. A store saves a candidate state atomically before assigning it to observable UI state.
3. The watch persists completed sessions to an outbox. WatchConnectivity may deliver a packet multiple times; iPhone deduplicates by session ID.
4. iPhone persists the received workout before sending its receipt through a live reply or application-context update. Only that receipt clears the watch outbox.
5. If data cannot be decoded, the app blocks writes and reports the error rather than overwriting history with an empty state.
6. Rest expiry is derived from an absolute Date, so suspension does not reset or stretch a timer. The app uses a local notification for background delivery rather than promising that a suspended Task always runs.
7. Notification identifiers are unique so a canceled asynchronous registration cannot remove a newer rest reminder.
8. Live sync returns a snapshot in the request's reply. A plan receipt is returned only after watch persistence, and completed-workout receipts only after phone persistence. Request timeouts and transport errors are visible.
9. Timestamped snapshots prevent a delayed background message from overwriting a newer plan. Existing saved watch data and old cached snapshots remain decodable.

## Simulator launch and sync

`Run Little Lift.command` runs `scripts/run_simulators.py` on the Mac. It selects a pair from simctl's existing pair list, verifies the app bundle identities, builds both simulator SDK targets, installs both, then launches them separately from Xcode's debugger. It does not erase/unpair devices or uninstall apps. The explicit debug-only demo argument seeds the generic sample only when the phone has no saved plan.

After launching, it reads the app data containers returned by simctl and waits up to about 20 seconds for the complete phone plan to match the watch's saved plan, with a sync timestamp newer than this launch. This prevents an old cached plan from producing a false success. No plan contents are printed. This check verifies plan persistence when run on a Mac; it does not prove workout uploads, notifications, Crown behavior, or frame pacing.

The transport uses live replies for simulator workout uploads, rather than relying on background user-info delivery there. On real devices, the persisted outbox retains both background and live delivery. A successful local send alone never clears the outbox.

## Historical Build 4 limits (superseded where noted in Build 6 guide)

The first version uses one prescription per exercise entry; split warm-up and working sets or different rep targets into separate entries. Logging is sequential, with undo and early finish. Weights use the plan's unit and are not silently converted. Load conventions, including per dumbbell or assistance, belong in exercise names and the profile.

This version does not record Apple Health workouts, read heart rate, count reps automatically, include subscriptions/payments, scrape notifications, or run a hosted MCP service. Apple Health is a separate implementation that needs the HealthKit entitlement, authorization handling, and a real-device workout-session lifecycle. It must not be presented as already working.

HealthKit is not enabled, so an ongoing workout does not keep this app running indefinitely in the background. The session and deadlines persist; a permitted local notification provides the rest cue and the UI catches up on foreground. OS settings, Focus, and physical-watch behavior still need device verification.

## Original authoring boundary (historical)

The authoring workspace is Linux. Foundation-only Swift tests and Swift parsing can run here, and the OpenStep project structure can be checked. These are not substitutes for Apple SDK type checking, simulator execution, paired-device sync, and haptic checks. `scripts/verify-mac.sh` and the GitHub Actions workflow perform the native build steps when run on a Mac. No successful Apple build or physical-device test should be claimed until observed.
