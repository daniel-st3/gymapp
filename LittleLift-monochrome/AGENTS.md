# Little Lift

This is a native SwiftUI iPhone + watchOS project. The checked-in Xcode project is the user entry point. Both native targets compile the files in Sources/WorkoutCore directly into their app module; app files must not import a separate WorkoutCore module. The root Swift package builds the same portable engine and tests separately.

- Preserve pure black backgrounds, white actions, neutral gray secondary text, regular/light typography, and quiet motion. The user's current palette is monochrome; it supersedes the earlier blue/red palette. No sparkles, mascots, glass effects, gradients, or marketing slogans.
- Keep Start, Log set, rest actions, and Done in a fixed action area outside scrolling content. Workout details, previous results, undo, and early finish belong in the watch options sheet. Use an accessibility scrolling fallback for large content without hiding the fixed actions.
- Use native SwiftUI scrolling, Digital Crown focus, WatchKit haptics, and local rest notifications. GSAP and web views do not belong in the watch app.
- Read `.agents/skills/swiftui-expert-skill/SKILL.md` and the applicable bundled references for SwiftUI changes. The selected upstream references are vendored with their MIT license; other topics can be fetched from the upstream repository recorded in `docs/engineering.md`.
- WorkoutCore must remain Foundation-only and compile on Linux. Validate imported/received data. Preserve actual reps and weights rather than replacing them with targets.
- Commit state to disk before publishing UI changes or acknowledging sync. Never clear the watch outbox until the phone has persisted and acknowledged the session ID.
- Timer correctness uses persisted deadlines, never a decrementing persisted counter. Respect Reduce Motion and user haptic preferences.
- Both connection modes are real user choices. A Shortcut does not automatically inherit an existing ChatGPT conversation. Never add hidden API calls, credentials, UI scraping, or unverified subscription-sharing assumptions.
- Run `swift test` for engine changes. On macOS run `bash scripts/verify-mac.sh` for both simulator builds. Device sync, locked/background notifications, Crown focus, and physical haptics require paired-device verification.
- After adding/removing Apple source files, regenerate `LittleLift.xcodeproj` with `python3 scripts/generate_project.py`.
- Keep medical data, exported workouts, local signing settings, and credentials out of Git.
