# Coach observations — Build 5

The loop is: ask your coach for a workout and optional observations → review the collection disclosure → log normally → share the evidence → review the coach's proposed next workout. No plan changes until acceptance. The existing-chat workflow remains explicit copying/importing. Shortcuts receive explicit saved context and do not inherit or target an existing chat.

## Import contract

Existing JSON is unchanged. Optional fields are demonstrated in [`Examples/observation-workout.json`](../Examples/observation-workout.json). The in-app coaching prompt includes that same generic example and validation rules. It is a schema example, not a training recommendation.

- `observationSchemaVersion`: omit or use `1`; other versions are rejected.
- Exercises may have an explicit UUID `id`. Requests must reference that ID with `exerciseID`; legacy exercises without IDs still get generated IDs.
- `observations`: up to 12 requests, each with a unique stable `id` of 1–64 ASCII letters/digits/hyphens/underscores. At most 100 total sets with observations; legacy plans retain their 200-set limit. A kind can occur once per exercise. IDs survive import, storage, session copies and sync.
- Supported `kind` values: `performance`, `loggingInterval`, `effort`. Unknown kinds or additional request properties fail with an explanation; requests are never interpreted as code or model instructions.
- `performance` covers each selected exercise's sets. It describes confirmed load/reps versus the copied prescription, including numeric differences. A missing set remains unavailable. Build 16 schema 3 `loadIsUnspecified: true` explicitly means no prescribed load; the recorded actual load is reported without a target-load delta.
- `loggingInterval` covers Log-tap timestamps and intervals between adjacent sets of the same exercise. It has no `afterSet` field.
- `effort`: at most one request per workout. `afterSet` must equal the selected exercise's final prescribed set number. The optional rating is an integer 1–10, from easy to maximal. No value is inferred for skipped or unreached sets.
- In legacy schemas, optional `comparisonID` and `loadConvention` must appear together. Build 16 schema 3 allows a known convention without a variation ID, but still requires both for comparisons. The former uses the same bounded identifier grammar and denotes the exact equipment, angle, grip and variation. Conventions: `total`, `perDumbbell`, `machineStack`, `assistance`, `bodyweight` (target weight 0). Units remain kg or lb. IDs must not be reused for different variations. Previous-result lookup requires exact variation ID, convention and units; legacy name-only matches are no longer shown.

The import preview and proposed-workout screen explain what will be collected before acceptance. Import Workout via Shortcuts stages a proposal, just like Save Workout Review. Both proposals stay separate from Today until accepted, including when no current plan exists. Ordinary explicit UI import accepts the exact previewed plan instance.

## Collection and recovery

Load/reps are the values the user confirms by tapping Log set; the app cannot measure external weight. A requested final set exposes **Rate last set · optional**. Opening it allows a brief 1–10 answer or Skip. Closing it leaves the question pending. Continuing to the next Log tap skips an unanswered question. On the final summary, Done skips and sends it. There are no extra mandatory taps in ordinary logging.

A pending final-workout rating holds the completed session locally until answered or skipped, avoiding a race where the phone could acknowledge a version without the answer. The summary explains Done's behavior. Once resolved, the immutable session uses the existing outbox and persist-before-ack protocol. The question and confirmed/skipped response survive relaunch. An unconfirmed picker selection is not evidence and resets if the sheet/process closes. Undo removes the removed set and any response attached to it; undoing a later set does not erase an earlier set's answer. As before, delivered/completed workouts do not offer retroactive Undo.

Start, Log set, rest extension/skip and Done remain in fixed Watch action areas. The rating sheet also fixes Skip/Save outside adaptable content. Controls use native SwiftUI, 44-point minimum secondary touch targets, Dynamic Type scrolling fallback, the existing motion preference and haptic settings. No capture permission or background workout mode was added to the main apps.

## Timing meaning

`completedAt` is the persisted **Log tap**, not a measured physical end of a set. Build 6 stores monotonic uptime on new Log events so future matched pace estimates can use them; legacy sets are not backfilled. An interval is available only between adjacent sets of the same exercise, with consecutive set numbers, nonnegative uptime deltas no longer than six hours, and wall/uptime deltas agreeing within two seconds. Clock changes, likely reboots and missing uptime make the interval unavailable. No timestamps or sensor samples are fabricated for older saved sessions.

The rest countdown is prescribed time. Extensions and skips control that countdown; they do not establish actual rest. A Log-tap interval includes exercise, setup and other time. No physical set-start/end events, repetition timing or actual rest are measured in this upgrade. Reports explicitly distinguish those limits.

## Reports and feedback

History has a compact observation list linking to the relevant set's prescribed values, confirmed values and Log-tap event. Missing data and skipped ratings have explicit descriptions. Shared/copied reports include request IDs and set IDs for coach reference, full evidence, load conventions and variation IDs. Prepare Workout Review includes these same reports. Feedback instructions require descriptive comparisons and prohibit unsupported causation, injury-risk or medical-readiness conclusions.

An external coach's analysis is user-supplied text, not an automatically validated conclusion. Save Workout Review stores that analysis and its proposed plan for explicit review. No live model integration is required to use observations, and no paid API or hosted backend is involved.

## Separate roadmap

Smart import, time-aware planning, and automatic review remain separate future projects. Motion replay is investigated in [`motion-feasibility.md`](motion-feasibility.md); it is not part of normal logging or an observation kind in Build 5.
