# Backup envelope, format 1

The file both PWAs export so the native app can import a user's history (NATIVE_APP_PLAN.md §6.4).
Machine-checkable schema: [`envelope-v1.schema.json`](envelope-v1.schema.json). Validate a file with
`node tools/backup-validate.mjs <file>`. [`examples/`](examples/) holds real exports from each PWA.

- One UTF-8 JSON document, file extension `.athkarbackup`, MIME `application/json`. The file name carries the
  device's local date. Importers strip a leading BOM (files passed through Mail or Notes can gain one).
- Each PWA exports only its own sections. The athkar PWA writes `meta`, `adhkar`, `reminders`,
  `preferences`; the ruqyah PWA writes `meta`, `ruqyah`, `preferences`. An importer must accept either file,
  alone or both, in either order.
- The export is taken after the PWA's own loader has normalised legacy keys (`athkar-progress-v1`,
  `athkar-reminders-v1`, `athkar-text-size`, `ruqyah-progress-v1`) and rolled the day, so it never contains
  legacy shapes and `today.date` is the device's local date at export time.
- The PWAs' loaders tolerate malformed stored values; the exporter does not pass them on. Dates that are not
  real calendar days and instants that are not ISO-8601 UTC become `null` (or the whole history entry is
  dropped when its own `date` is invalid); adhkar history is de-duplicated by date (first stored entry wins),
  sorted newest first, limited to days before `today.date` and capped at 7; ruqyah history keeps days up to
  `today.date` (today appears once it is completed), capped to the 365 newest. Instants must round-trip
  through `Date` (so `2026-02-30T…` or `T24:00` are rejected rather than rolled over). So every field below
  always satisfies the schema.
- Plaintext. Nothing leaves the device unless the user shares the file.

## Sections

| Field | Type | Source |
| --- | --- | --- |
| `meta.format` | `1` | constant |
| `meta.app` | `"athkar-pwa"` \| `"ruqyah-pwa"` | constant per PWA |
| `meta.exportedAt` | UTC instant | `new Date().toISOString()` |
| `meta.timeZone` | IANA zone | `Intl.DateTimeFormat().resolvedOptions().timeZone`; the zone every `date` field is local to |
| `adhkar.today` | object | `athkar-progress-v2`: `date`, `progress`, `targets`, `completedAt`, `manualCompletion` |
| `adhkar.today.progress.{morning,evening}` | `{itemId: count}` | tap counts converted with `Number()`, as `countForState` reads them; entries that come out non-finite or negative are dropped. Not floored and may exceed the target: floor and clamp on read as `countForState` does |
| `adhkar.today.targets.{morning,evening}` | `{itemId: target}` | chosen target for items with `targetOptions`; values outside the options mean "use `defaultTarget`" |
| `adhkar.history` | array, newest first, ≤7 | `date`, `morning`, `evening` (booleans: complete by counters or manually), `morningAt`, `eveningAt` (UTC instant or null) |
| `ruqyah.today` | object | `ruqyah-daily-v1`: `date`, `counts` (`{segmentId: integer count}`). The ruqyah PWA's export is already clamped to `repeat` by `normalizeCounts`; the schema sets no upper bound. The native importer clamps each count to its segment's `repeat` in the installed pack and drops unknown segment IDs, as `normalizeCounts` does |
| `ruqyah.history` | `{date: {completedAt}}`, ≤365 | days on which every segment was completed |
| `reminders` | object | `athkar-reminders-v2`: `morning.enabled`, `evening.enabled`, `calculationMethod`, `asrSchool`, `lastShown.{morning,evening}` (local date or null) |
| `reminders.location` | object, optional | `latitude`, `longitude` (rounded to 4 decimals, as the PWA stores them), `updatedAt` (UTC instant or null). Present **only** if the user switched on "include location" for this export; the switch resets to off every time settings open. The native importer rounds to 2 decimals with `Math.round(x × 100) / 100` semantics (§7.4, spec/schema.md) |
| `preferences.theme` | `system` \| `light` \| `dark` | `athkar-theme` / `ruqyah-theme`, effective value |
| `preferences.textSize` | `small` \| `medium` \| `large` | `athkar-reading-text-size` / `ruqyah-text-size`, effective value |
| `preferences.lineSpacing` | `compact` \| `comfortable` \| `wide` | `athkar-line-spacing` / `ruqyah-line-spacing`, effective value |
| `preferences.haptics` | boolean | `athkar-haptics` / `ruqyah-haptics` ≠ `"off"` |
| `preferences.longOrder` | `last` \| `original` | athkar only: `athkar-long-order-v1` (absent key = `original`) |
| `preferences.longOrderPromptAnswered` | boolean | athkar only: `athkar-long-order-prompt-v1 === "answered"` |

Not exported: `athkar-install-onboarding-v1`.

## Import rules (native side)

Restated from §6.4: each file merges into its own tables; preferences from the athkar file win over the ruqyah
file; merge keys are `(local_date, period)`, `(local_date)`, `(local_date, segment_id)`; an existing non-empty
native row wins, so re-import is idempotent; a native re-export of an imported file must equal it in every
section it contained.

The native importer rejects the whole file on exactly what `tools/backup-validate.mjs` rejects, including a count
or target above 2^53 − 1 (`Number.MAX_SAFE_INTEGER`), which cannot be stored as an exact integer
(spec/schema.md "Backup import").

It then checks `today` against the installed content packs: an adhkar period is recorded complete only if
`manualCompletion` is true or the counters complete it by the PWA's `periodCountersComplete` rule (a
`completedAt` alone is not enough), and ruqyah counts are clamped to `repeat` with unknown segments dropped.
History entries are trusted as written.
