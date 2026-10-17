# Security and privacy

Little Lift is a local-first personal workout logger. This is a defensive code review and tested hardening pass, not an independent penetration test or a guarantee that the app cannot be compromised.

## Data boundaries

- The app has no backend, remote model API, analytics SDK, ads, embedded browser, downloadable executable code or account credentials. Progress calculations, OCR and optional Foundation Models extraction run locally. A user-invoked ChatGPT Shortcut or shared report leaves the app through the chosen external service and is subject to that service’s policies.
- Workout imports and model responses are untrusted data. Typed schemas, byte/count/value limits, stable IDs and reference checks reject malformed plans. Preview and explicit acceptance remain required; a model response cannot execute commands or silently replace today’s plan. A model can still misunderstand text, so editable review is essential.
- Text plans/reviews are capped at 64 KB; historical imports at 256 KB; images at 20 MB with a 2,400-pixel OCR thumbnail; extracted OCR text at 64 KB. Files and Photos transfers use a chunked reader that limits actual bytes, even if file-size metadata changes. Motion files are limited to 2 MB and 4,500 validated samples.
- WatchConnectivity communicates with the paired companion app. Incoming messages have a strict sub-60 KB limit and semantic validation before state mutation. Receipts have bounded, unique IDs. Invalid records do not receive successful acknowledgments. Identical completed-workout replays are harmless; the same ID with different contents is rejected and the original remains untouched.
- All four App Intents explicitly require authentication. Preparing a review can expose personal history, and importing/saving/cancelling changes local state. iOS controls the actual authentication experience. Locked, unattended review is therefore not promised.

## Local storage and recovery

Workout JSON is in each app’s sandbox and atomically replaced with `completeFileProtectionUntilFirstUserAuthentication`. It is inaccessible before the first unlock after reboot, then remains accessible while locked so background delivery can persist safely. This is Apple’s Data Protection, not an app-specific password or end-to-end encrypted export. The device passcode, OS integrity, developer access and backup settings remain part of the security boundary.

The phone saves a received workout before acknowledging it. The Watch retains its durable outbox until that receipt arrives. Unreadable storage blocks ordinary writes and outgoing plan snapshots instead of silently resetting history or clearing the Watch plan. Explicit, reviewed backup recovery first preserves the unreadable original bytes to a unique protected checkpoint. A readable future storage-version header blocks recovery even when the remaining payload cannot decode. Updating the app in place preserves its container. Do not uninstall to refresh signing.

Portable workout backups use a versioned, semantically validated JSON envelope capped at 20 MB by actual bytes. Restore previews merge missing records, preserve local conflicts, reject a stale preview after concurrent changes, and require explicit confirmation. A checkpoint precedes every restore. Sharing permissions, motion opt-in, OS permissions, signing and pairing are not restored; raw experimental motion recordings are excluded. The export itself is **not encrypted by the app** and may contain training profiles and saved coach text. The user chooses its destination through native Files.

Strength-record corrections are bounded, append-only sidecar events tied to original session/set IDs and previous values. Delivery/deduplication continue using the untouched original Watch record. Reports use validated projections and disclose corrections; they do not invent timestamps. Evidence changes flag saved coach responses as outdated and revoke active attempts, so a delayed response cannot silently apply an older proposal. This audit trail is not a cryptographic authenticity proof against someone with file access.

Unused Finder/iTunes Documents file sharing is disabled. Explicit Files imports and report sharing remain available.

Workout history may be included in the user’s normal device backups. Experimental motion files are excluded from backup. Explicit report sharing and clipboard copies are readable by their recipients; avoid including private health information in a public issue or repository.

## Repository safeguards

Private signing settings, profiles, keys, device refresh scripts, real workout files, backups, screenshots from personal sessions, build output and diagnostic logs are excluded. `scripts/check_repository.py` scans the Git index (or tracked files in CI) for forbidden paths and high-confidence credential patterns; it prints file names, not secret values. This reduces accidental exposure but does not replace reviewing the staged diff. Documentation screenshots contain generic fixtures only.

## Verification and limits

Build 10 adds regression cases for oversize inputs, malformed receipts, altered duplicate records, invalid set ordering/dates, invalid motion confirmation and failed-write preservation. Exact existing data round trips, actual simulator delivery and device installation status are recorded in [verification](docs/verification.md).

Physical haptics, hardware double tap, long wrist-down motion capture, battery life, live ChatGPT and locked notification delivery are separate hardware/platform checks. Compromised or unlocked devices, malicious OS components and flaws in Apple frameworks are outside what this app can guarantee. No custom cryptography or hidden security service is introduced.

If you find a vulnerability, share a minimal generic reproduction privately with the repository owner; do not post personal records, credentials or device identifiers. No security-reporting inbox or bug bounty is currently configured.

## Platform references

- [Apple: App Intent authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy) — the default is always allowed; Little Lift opts into authentication.
- [Apple: Data Protection classes](https://support.apple.com/guide/security/secb010e978a/web) — explains protection after the first unlock.
- [Apple: Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity) — paired-app transport and system-managed delivery.
