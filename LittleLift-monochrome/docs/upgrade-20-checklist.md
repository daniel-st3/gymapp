# Build 20 — get from a chat reply to a workout

User feedback: starting/importing remained too difficult, Open ChatGPT opened the browser, and a copied workout failed. The original failed reply is unavailable; reproductions must be described as generic cases.

- [x] Put Paste and Screenshot directly on Train; open the editable preview directly.
- [x] Accept plain-text code blocks and a single workout block surrounded by commentary.
- [x] Recover incomplete ordinary JSON into a draft, without inventing missing targets or dropping advanced requests.
- [x] Replace the generic import alert with an actionable, source-preserving recovery screen.
- [x] Make the everyday chat request ask for a simple, supported text format; retain legacy correlated JSON and the independent Shortcut review contract.
- [x] Open ChatGPT through its official app link, with an optional private conversation link and no automatic browser fallback.
- [x] Run parser/security/compatibility checks and both SDK builds.
- [x] Exercise direct paste, screenshot, incomplete fields, recovery, acceptance, Watch start and real logging on the existing paired simulators.
- [x] Inspect actual layouts; restore original simulator data and settings.
- [x] Back up and install the verified update with existing free signing when devices are available; compare data.

Live model compliance, the unavailable original failed reply, physical haptics and automatic selection of an unknown chat are not verified by generic fixtures.

## Verification observed on 20 October 2026

- **178 Swift tests / 24 suites + 13 Python checks passed.** Both simulator SDK builds and the final Personal Team build passed. Logs: `BuildLogs/upgrade20-verification.log`, `upgrade20-ui-build.log`, `upgrade20-signed.log`.
- Regression cases include fenced ordinary text, commentary around one JSON/text block, missing units/rest/load, explicit rep ranges, malformed/duplicate JSON fields, bounds, preserved advanced requests, correlation rejection, acceptance/history preservation and restricted private-chat URLs.
- Native **Train → Paste** with a generic `text` code block opened the compact Pierna preview. Torso stayed saved until explicit acceptance. Accepted Pierna reached the existing paired 46 mm Watch; one Start tap opened logging.
- Native **Train → Screenshot → selected image** ran local Vision and opened two correct exercises, sets, reps, loads and rest. No intermediate import menu was required. The one added generic photo was removed from the simulator library afterwards; its six original images remained.
- Partial ordinary JSON opened a draft with known sets/reps preserved. Choosing kg and 90 s enabled acceptance; the already-active Watch session and its recorded set stayed unchanged.
- A valid reply bearing an unknown/older handoff ID showed a clear explanation and fixed **Review exercises** action. That explicit separate-import path opened a preview and accepted only after another explicit confirmation. It did not mark a current chat request answered.
- Watch recorded actual **40.5 kg × 11 reps**, retained the set after relaunch, completed three sets, displayed Summary/Done and delivered exactly one History session. Replayed delivery was acknowledged without adding a second History entry.
- Copying the updated chat message produced the new ordinary-text instructions. The ChatGPT button stayed in Little Lift with a clear failure explanation when the simulator lacked ChatGPT; it did not fall back to Safari. The optional private-link form opened. Unit checks reject share links, foreign hosts, credentials, query/fragment overrides and non-HTTPS URLs.
- Real devices: fresh app-owned data backups preceded in-place installation. Build **20** installed and launched on both. Phone state matched exactly; Watch differed only in its expected snapshot timestamp. All four phone and three Watch auxiliary files matched byte for byte. Existing identifiers, free signing and pairing were retained.

- Phone empty/start and preview layouts were inspected at normal and accessibility-medium text size. The fixed Paste/Screenshot and acceptance controls remained visible. Reduce Motion was read back enabled and then disabled; text size returned to Large. Original simulator app files/preferences were restored and compared: phone state matched, Watch only changed its snapshot timestamp, auxiliary files matched. The same pair was retained.
- The final friendlier error wording was rebuilt, installed and launched on iPhone after another fresh backup/readback comparison.

Private logs/screenshots and backup comparisons are under `.verification/upgrade-20/` (ignored by Git). Public screenshots contain only generic fixtures.

## Specific limitations

- The user's failed original reply is unavailable. These are reproductions of identifiable parser failures and generic end-to-end cases, not proof that the missing input was reproduced verbatim.
- The official ChatGPT app-link routes were checked against OpenAI's published association file. A successful physical ChatGPT app/conversation opening and a live response to the new prompt were not observed in this pass. No private conversation URL was supplied; Little Lift cannot infer it. See [the source links and setup explanation](gym-chat.md).
- A system Paste button follows iOS's interface language; the simulator's OS renders it as **Paste** even when Little Lift's selected language is Spanish. It remains the system permission-preserving paste control.
- Unknown targets still need explicit confirmation. Unsupported structured observations and malformed content are not silently stripped or guessed. Shortcut review remains separate and its existing receipt/error safeguards are unchanged.
- Physical haptics, sensor accuracy/background capture and live Shortcut execution were not reverified by this UI/import pass.
