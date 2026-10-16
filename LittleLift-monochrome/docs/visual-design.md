> The current interface is [Build 9](design-9.md). The Build 8 notes below describe the preceding pass.

# Native visual design · Build 8

## Icons and type

The interface uses Apple's **SF Symbols**, accessed with `Image(systemName:)` / `Label`. These are Apple-designed vectors supplied by the operating system; no generated icon artwork, downloaded icon dependencies or network loading were introduced. Symbols accompany visible text, and decorative copies are hidden from accessibility. All new symbols predate the minimum iOS 18 / watchOS 11 deployment versions.

- SF rounded headings and workout numbers distinguish the workout from navigation and secondary details. Regular system body text remains easy to scan; tabular digits keep timers and values stable.
- Primary actions use white with black labels. Secondary actions use quiet gray surfaces. The existing monochrome app icon is unchanged.
- Menu icons have a scaled, aligned column. Native navigation, Forms, Lists, Crown interaction and system sheets remain in use.
- Everyday preferences are grouped on iPhone. Watch options contain workout actions, sync and a separate Preferences screen. Imported history now sits in History; routine creation and scheduling sit in Routines.

Sources consulted on 15 October 2026:

- [Apple SF Symbols](https://developer.apple.com/sf-symbols/) — system integration, weights, scales and monochrome rendering.
- [SF Symbols usage guidelines](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) — interface use and trademark/app-icon restrictions. No SF Symbol was added to the app icon or used as a logo.
- [Meet the expanded San Francisco font family](https://developer.apple.com/videos/play/wwdc2022/110381/) — platform system fonts and rounded designs. Fonts are used through the OS, not redistributed as font files.
- [SwiftUI animation guidance](https://developer.apple.com/videos/play/wwdc2023/10157/) — short, event-driven effects, scoped to the changing content.

## Motion and accessibility

- Button feedback: 120 ms press response, slight scale only when Reduce Motion is off.
- Incoming workout content: 180 ms fade and four-point movement. Fixed actions do not participate in screen exit transitions.
- Phone disclosures: 180 ms expansion with a rotating chevron and clipped reveal, preventing the content from overlapping the next row during expansion.
- Watch numbers/timers: brief native numeric transitions; a single completion checkmark effect. No continuously repeating decoration.
- Reduce Motion removes custom movement/expansion animation. Dynamic Type scales all roles; Watch actions stay outside the scrolling fallback. Buttons retain at least 44-point targets (primary buttons: 46).

## Fixes accompanying this pass

Import OCR and model operations now share a generation token and cancellable timeout. Cancellation invalidates the generation before cancelling the task, so a late operation cannot overwrite a new result, clear its busy state or publish an old error. The timeout also ends when the view disappears or extraction finishes. Photo selection resets after capture so the same screenshot can be retried. The review-before-save boundary is unchanged.

Inspection caught an overlap in the first version of the disclosure transition; clipping the expanding group corrected it. Single-exercise summaries now use singular wording. Copying a workout report now shows a visible confirmation.

See [verification](verification.md) and [the delivery checklist](design-pass-checklist.md) for observed results and limits.
