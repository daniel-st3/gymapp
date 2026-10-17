# Build 12 · in-app completion checklist

This increment continues F01–F27; it does not redefine a local calculation as ChatGPT.

- [x] Automatic factual review directly from durable completed sessions; exact variation/unit/load-convention/set matching; missing evidence explicit.
- [x] Native Today, History and review navigation; optional ChatGPT kept separate.
- [x] Search saved exercises and the local guide without a network request or assumed gym inventory.
- [x] Expire stalled external attempts and reject late results, while preserving the local review and current plan.
- [x] Permit optional rhythm pulses with an active HealthKit session when the wrist is down; stop on interruption, pause, completion or haptic opt-out.
- [x] 121 engine tests / 16 suites, 10 launcher tests, both simulator builds; actual phone/46 mm Watch interaction and layout checks.
- [x] Build 12 installed and launched on both real devices with free signing; fresh full backups and matching post-launch state, motion and checkpoint readbacks. No restoration required.

- [x] Native 150 ms touch-pair guard, completed-summary relaunch, identical phone delivery and duplicate replay.
- [x] Corrected review navigation so new delivery does not switch an already opened review.
- [x] Phone normal/accessibility layouts, Reduce Motion readback, saved-exercise detail and previous-workout link inspected.

Full evidence and the preserved 27-point scope are in [verification](verification.md) and [F01–F27](feedback-27.md).

Still requires evidence: physical wrist return/haptic feel, sensor accuracy and energy use. Exact existing-chat delivery, live ChatGPT, web machine search and unattended Shortcuts are not claimed completed. Apple permission/account/device gates cannot be bypassed.

The rhythm change follows [Apple’s haptic API](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)): background playback requires an active workout session. The app never starts a replacement workout automatically after another app interrupts it. [Workout session documentation](https://developer.apple.com/documentation/healthkit/running-workout-sessions).
