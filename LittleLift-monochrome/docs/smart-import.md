# Import examples and decisions

## The shorter gym flow (Build 16)

Today → **Change workout** → **Use a screenshot** or **Paste** → **Check your workout**.
Image reading and Paste now open review directly. Review shows names, sets,
repetitions and rest together; details and the original message remain available.
Use the explicit bottom action to save and send. Until then, Today is unchanged.
An older saved plan is retained in routines; completed records are never rewritten.

A generic chat-format fixture, not a training recommendation:

```text
## Pierna
1. Prensa de piernas
3 series de 10–12 repeticiones
Descanso: 90 segundos
2. Curl femoral sentado
2 x 12
```

Here, choose a repetition target from the range, choose kg/lb, and choose the
missing rest for the second exercise. The first exercise retains its prescribed
90 seconds. The preview explicitly offers **Choose the actual load on Watch**;
the first zero-load Log requires confirmation. Positive load uses ordinary input
and Log. No extra mandatory logging action is added when a load is already chosen.

The saved plan uses `schemaVersion: 3` and optional `loadIsUnspecified: true` for
an absent strength-load target. Its internal numeric sentinel is zero; reports
say the load was not prescribed and never calculate a delta against zero.
Schema 3 also permits a known load convention without an invented variation ID;
historical matching still requires exact variation ID, units and convention.
Legacy plans/sessions keep their original meaning. Older apps reject schema 3
rather than silently interpreting the unknown load as a prescription: update both.

Screenshot quality and message structure can still prevent full extraction.
Unknown values/ranges remain visible; edit the same preview or use manual text.
The app cannot infer a workout from just “legs” or read an existing ChatGPT thread.

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
