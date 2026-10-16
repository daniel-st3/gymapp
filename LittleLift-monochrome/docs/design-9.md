# Build 9: a coherent native interface

This redesign uses three deliberate type roles: New York serif for phone page/workout titles and the idle Watch workout title; San Francisco for controls and explanatory text; rounded tabular figures for workout values. It uses the OS fonts through SwiftUI, with Dynamic Type support. No font files, generated artwork or icon packages are downloaded. Icons are Apple's SF Symbols, and the existing monochrome app icon is unchanged.

## What changed

- Today has a clear workout heading, three compact prescription facts, direct Change/Edit actions, numbered exercise rows, links to matching prior sets, and a grouped time/coach area. Send to Watch and Import stay pinned.
- History uses dated workout cards and clearly separates imported records. Workout records distinguish targets from logged sets and keep sharing together.
- Routines has a schedule entry, readable workout cards, a Today selection indicator and a pinned Add action. Routine details reuse the same exercise rows and retain explicit selection.
- Settings groups training/coach, Watch and secondary tools. Shared icon columns scale with text; secondary explanations align with their titles.
- Import separates text entry, screenshot/file input and manual creation. Its editable preview retains validation, native reordering, the visible Save action, and explicit acceptance. Native Forms/Lists use the same quieter surfaces and spacing throughout editing, review, planning and motion screens.
- Watch Today gains the serif title treatment. Logging has distinct load and repetition panels, a small within-exercise progress indicator, compact values and full-size adjustment targets. Start, Log, rest controls and Done remain fixed outside the scrolling content. Options retain their existing native navigation.
- Short incoming fades, press feedback, numerical transitions and disclosure reveals are shared across the interface. Reduce Motion disables the custom movement. No workout state waits for an animation.

## Decisions and boundaries

Black remains the canvas; white marks primary actions, and neutral gray separates secondary content. Large titles are restricted to the phone's page hierarchy and Watch's idle workout name. Live logging uses compact type. Native platform navigation chrome remains native; the app adds no glass materials, gradients or web views.

The workout engine, storage format, transport, Personal Team configuration and original records were not changed. The redesign does not establish physical haptic quality, motion-capture reliability or live ChatGPT/Shortcut execution.

Primary design sources checked for this pass: [Apple fonts](https://developer.apple.com/fonts/), [SF Symbols](https://developer.apple.com/sf-symbols/) and the vendored [SwiftUI skill](../.agents/skills/swiftui-expert-skill/SKILL.md). The observed evidence and device status are in [verification](verification.md); the delivery tasks are in [the checklist](design-9-checklist.md).
