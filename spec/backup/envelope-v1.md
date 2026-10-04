# Backup envelope, format 1

The file both PWAs export so the native app can import a user's history (NATIVE_APP_PLAN.md §6.4).
Machine-checkable schema: [`envelope-v1.schema.json`](envelope-v1.schema.json). Validate a file with
`node tools/backup-validate.mjs <file>`. [`examples/`](examples/) holds real exports from each PWA.

- The export is one UTF-8 JSON document with extension `.athkarbackup` and MIME type `application/json`. Its file
  name carries the device's local date. Importers strip one leading BOM (files passed through Mail or Notes can
  gain one) and reject any byte sequence that is not valid UTF-8. The document follows `JSON.parse` semantics: a
  duplicated key keeps its last value, numbers that underflow read as 0, and lone surrogates in strings are kept.
- Each PWA exports only its own sections. The athkar PWA writes `meta`, `adhkar`, `reminders`,
  `preferences`; the ruqyah PWA writes `meta`, `ruqyah`, `preferences`. An importer must accept either file,
  alone or both, in either order.
- Each PWA exports after its loader normalises legacy keys (`athkar-progress-v1`, `athkar-reminders-v1`, `athkar-text-size`, `ruqyah-progress-v1`) and rolls the day. The export contains no legacy shapes, and `today.date` is the device's local date at export time.
- The PWAs' loaders tolerate malformed stored values, but the exporter does not pass them on.
  It converts dates that are not real calendar days and instants that are not ISO-8601 UTC to `null`. If a
  history entry's own `date` is invalid, the exporter drops the whole entry.
  It de-duplicates adhkar history by date, keeping the first stored entry. It sorts entries newest first, includes
  only days before `today.date`, and caps the history at 7 days.
  The exporter keeps ruqyah history through `today.date` (today appears once it is completed) and caps it at the
  365 newest days.
  Instants must round-trip through `Date`, so `2026-02-30T…` or `T24:00` are rejected rather than rolled over.
  The exporter writes instants in `toISOString()` form, with millisecond precision and extra fraction digits
  truncated, as the native app does.
  Every field below therefore satisfies the schema. The PWAs' settings history lists exactly the days the export
  would carry.
- Calendar checks apply only to the schema's date and instant fields: `meta.exportedAt`, every `date`,
  `completedAt`, `morningAt`, `eveningAt`, `lastShown`, `location.updatedAt`, and the `ruqyah.history` keys.
  A date is a real proleptic-Gregorian day for any year 0000–9999. An instant consists of such a date, a real
  time (hours 00–23, no leap second `:60`), any number of fraction digits, and an uppercase `Z`.
  Other date-shaped strings (a `timeZone`, an item id) are not calendar-checked. Item and segment IDs
  (`adhkar.today.progress`/`targets` keys, `ruqyah.today.counts` keys) must not contain U+0000.
  The file is plaintext. Nothing leaves the device unless the user shares it.

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

These rules restate §6.4. Each file merges into its own tables. Preferences from the athkar file win over
preferences from the ruqyah file. The merge keys are `(local_date, period)`, `(local_date)`,
`(local_date, segment_id)`. An existing non-empty native row wins, so re-import is idempotent. A native re-export
of an imported file must equal that file in every section it contained.

The native importer rejects the whole file under exactly the same conditions as `tools/backup-validate.mjs`,
including a count or target above 2^53 − 1 (`Number.MAX_SAFE_INTEGER`), which cannot be stored as an exact
integer (`spec/schema.md "Backup import"`).

It then checks `today` against the installed content packs. It records an adhkar period as complete only if
`manualCompletion` is true or its counters satisfy the PWA's `periodCountersComplete` rule. A `completedAt` value
alone is not enough. It clamps ruqyah counts to `repeat` and drops unknown segments. It trusts history entries
as written.
