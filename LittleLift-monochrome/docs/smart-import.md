# Import examples and decisions

Paste ordinary text, a labelled table, a screenshot, or existing Little Lift JSON.
Every route leads to an editable preview. Saving a proposal is always explicit.
For example:

```text
Entrenamiento: Fuerza sencilla
Ejercicio | Series | Reps | Peso (kg) | Descanso (s)
Remo | 3 | 10 | 20 | 60
Press | 2 | 8 | 15 | 90
```

Tab and semicolon tables also work. English headings include Exercise, Sets, Reps,
Weight (kg/lb), Rest (s/min), Unit, Convention and Variation ID. A weight column
with no explicit unit does not imply kg. Conflicting units remain unresolved.
Unlabelled rest values do not imply seconds. Spanish decimal commas are retained.

```text
Entrenamiento: Revisar antes de guardar
Remo 3 series de 8 a 20 kg
Descanso: 90 segundos
Press 3 - 4 x 8–12 a 20–25 kg
```

The first exercise has a confirmed target in the source. The second requires
single set, repetition and load targets chosen in the editor. The app does not
select a convenient end of a range. Original text and import notes stay visible.
Choose the correct load convention and exact variation ID only when known;
unknown identity does not qualify a machine for matched historical comparisons.

Vision OCR runs locally. Explicit table headers and cell positions preserve
column meaning. If OCR misses a digit, its cell stays blank rather than shifting
the next number into it. Poor images, merged cells and unsupported layouts can
still require manual entry. The editor names the fields needing attention.

Optional Foundation Models extraction identifies exercise lines from quoted
source text. A deterministic parser owns the numeric quantities; unsupported
model numbers are not silently accepted. Unsupported source quotes fall back to
ordinary extraction. Availability depends on Apple Intelligence; manual editing
and ordinary extraction remain usable without it. No external inference fallback.

Imported data never executes instructions. Receipt-bearing coach/test replies
must return through Save Workout Review; they cannot bypass correlation by
being pasted as a fresh workout. Duplicate JSON field names (including escaped
aliases), deep nesting and oversize payloads are rejected before typed decoding.

Generic connection test: Settings → Coach connection → Set up review Shortcut.
Add the prepared test Shortcut once, allow Apple's actions, then run it. A
successful return displays **Response received · history unchanged**. This is
separate from the production review Shortcut and sends no saved personal data.
It does not inherit an existing conversation, prove coaching quality, or prove
unattended execution. Keep using explicit report sharing for an existing gym chat.
