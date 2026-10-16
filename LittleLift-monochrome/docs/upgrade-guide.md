# Build 6 guide

Setup, editing and analysis stay on iPhone. Watch Start, Log set, rest controls and Done remain fixed; optional controls live under ….

## Import and routines

Import accepts text, JSON and screenshots/files. Vision OCR runs locally. Ordinary extraction understands common `3 x 8 @ 40 kg rest 90 sec` notation; other formats remain editable drafts. Apple Intelligence extraction is an explicit optional action when the local system model is available. Missing fields and ranges need a user decision, never a guessed target. Model drafts are labelled experimental and need checking against the original source.

Review every exercise, target, unit, rest and collection request before accepting. An explicit load convention also needs an exact variation ID for later comparisons. Mixed kg/lb plans must be split into separate routines; no hidden unit conversion. Existing JSON and stored sessions remain compatible. [Text fixture](../Examples/workout-text.txt), [old JSON](../Examples/example-workout.json), [observation JSON](../Examples/observation-workout.json).

Routines supports multiple saved workouts, preserved prior revisions and one scheduled routine per weekday. Today offers the scheduled routine as an explicit choice; a schedule never silently changes an active workout. Editing a routine preserves session copies and prior library revisions. Approved alternatives are added to each exercise in its routine, with explicit targets, units, load convention and distinct variation identity.

Import historical records uses [this JSON example](../Examples/historical-workouts.json). Edit/paste, preview the actual sets, confirm their provenance, then import. Stable record IDs prevent repeated imports; conflicting records cannot overwrite originals. External records stay separate from Little Lift's collected observations. Settings contains an editable training profile and a compact context export for the user's chosen existing conversation; progression uses only suitably matched recorded variations and units.

## Available time and busy equipment

Choose a duration or finish time in Today → Available time before starting. Estimates show a range and whether matched history is available. Watch … → Adjust workout refreshes the estimate during the session. Log-tap intervals include work/setup/rest and are not measured rest. Old sessions receive no invented monotonic timestamps.

Mark optional work and priorities explicitly in the iPhone routine editor (1 is highest). Watch offers a shorter remainder by dropping lower-priority untouched optional exercises until its conservative estimate fits, when possible. It never changes load, reps, completed sets or required rest. Review the listed changes and confirm; Undo adjustment is available until another set is logged. It may still be impossible to meet the time target without changing required work; no finish time is promised.

Defer moves the current exercise behind remaining work and returns to its next unlogged set. Only approved alternatives are offered, and only before any sets of that original exercise have been logged. Substitutions keep their own variation history. The original prescription and changes remain in reports; original observation requests do not silently move onto a different machine.

## Watch controls

The installed WidgetKit extension provides a monochrome launcher in circular, rectangular, inline and corner complication families. A face slot must be chosen in Apple's face editor. The native double-tap primary action is opt-in in iPhone Settings and applies only to the visible Log action, with modal/rest/completion and rapid-repeat guards. Hardware gesture execution and haptic feel are not simulator-verifiable. Crown and touch controls remain available.

## Coach review

The explicit existing-chat workflow remains: export context/report, paste into the chosen gym chat, then import and accept its plan. No Shortcut inherits that conversation.

Completed sessions are durably saved before the phone creates a review job or optional notification. The review queue has one job per session and one running attempt, rejects stale/cancelled responses and blocks duplicate saved reviews. Failed or cancelled Shortcuts remain visible for explicit retry. A new plan always remains a proposal until accepted.

A signed local three-action template can be opened from Settings → Set up review Shortcut when the prepared file is installed. It connects Prepare Workout Review → Use Model (Text output) → Save Workout Review. The template asks for the model explicitly. Choose the ChatGPT extension only when Apple offers it; cancel otherwise. After a successful account-specific test, the user can select that provider permanently in Apple's editor. No API key, subscription scraping or paid fallback is used. The reproducible preparer is `scripts/prepare_review_shortcut.py`; signing is Apple's local `shortcuts sign` command. Signing/preparing a file is not proof of model execution.

Apple's [iOS 27 model guide](https://support.apple.com/en-mide/guide/shortcuts/tpg3vrvwmclv/10.0/ios/27) distinguishes On-Device, Cloud, Cloud Pro and the ChatGPT extension. The simulator exposed the first three, but no ChatGPT. Account/provider setup and live analysis remain a separate verification gate.

Apple's [notification trigger](https://support.apple.com/en-lamr/guide/shortcuts/apd932ff833f/10.0/ios/27) can filter by app and notification content. After a working review Shortcut exists, an iOS 27 automation can select Little Lift and title `Little Lift workout ready`. Run Immediately, authentication and model confirmation depend on the OS/account. No unattended execution is claimed. The app's one-tap review launch and explicit report sharing remain available. Turning off notifications cancels pending review notices; it does not delete saved workouts.

## Motion experiment

Off by default. iPhone Settings → Motion test holds the enable switch and exercise choice (dumbbell curl or lateral raise). Watch … → Motion test has full-size movement text and fixed Start/Stop/Send controls. Permission waits, cancellation and missing sensor samples are visible. If Workouts access is off, the app directs the user to Watch Settings → Health → Apps → Little Lift; Apple requires the user to grant access. It requests Apple workout authorization, uses a temporary HealthKit session for runtime and records bounded local wrist rotation for at most three minutes. Do not run alongside another workout app. Little Lift saves no Health workout and reads no Health history; system workout/activity side effects remain possible and are disclosed.

Stopped recordings are queued automatically for iPhone; Send retries if queueing fails. On iPhone, scrub the native timing trace and separately confirm/edit a suggested count. Raw samples, gaps and estimates remain distinct from confirmation and ordinary logged sets. This cannot measure external load, certify technique, diagnose risk or infer readiness. No fabricated training data or trained model is included. See [feasibility evidence and limitations](motion-feasibility.md).

The physical user test initially reached the missing-Workouts-authorization error. Enabling Workouts in Watch Health settings resolved it. A stopped real recording contains 587 samples over 23.39 seconds at about 25 Hz with no sample gaps over 160 ms. Automatic delivery to the real iPhone preserved the entire original recording. This short run does not establish wrist-down continuity, battery cost or repetition accuracy. Start/stop haptic calls now respect the existing preference; their physical feel is not yet observed. The simulator replay was verified using an explicitly synthetic 450-sample fixture; an edited count of seven persisted without changing those samples.
