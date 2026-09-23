# Backup envelope, format 1

The file both PWAs export so the native app can import a user's history (NATIVE_APP_PLAN.md §6.4).
Machine-checkable schema: [`envelope-v1.schema.json`](envelope-v1.schema.json). Validate a file with
`node tools/backup-validate.mjs <file>`. [`examples/`](examples/) holds real exports from each PWA.

- One UTF-8 JSON document, file extension `.athkarbackup`, MIME `application/json`.
- Each PWA exports only its own sections. The athkar PWA writes `meta`, `adhkar`, `reminders`,
  `preferences`; the ruqyah PWA writes `meta`, `ruqyah`, `preferences`. An importer must accept either file,
  alone or both, in either order.
- The export is taken after the PWA's own loader has normalised legacy keys (`athkar-progress-v1`,
  `athkar-reminders-v1`, `athkar-text-size`, `ruqyah-progress-v1`) and rolled the day, so it never contains
  legacy shapes and `today.date` is the device's local date at export time.
- Plaintext. Nothing leaves the device unless the user shares the file.

## Sections

| Field | Type | Source |
| --- | --- | --- |
| `meta.format` | `1` | constant |
| `meta.app` | `"athkar-pwa"` \| `"ruqyah-pwa"` | constant per PWA |
| `meta.exportedAt` | UTC instant | `new Date().toISOString()` |
| `meta.timeZone` | IANA zone | `Intl.DateTimeFormat().resolvedOptions().timeZone`; the zone every `date` field is local to |
| `adhkar.today` | object | `athkar-progress-v2`: `date`, `progress`, `targets`, `completedAt`, `manualCompletion` |
| `adhkar.today.progress.{morning,evening}` | `{itemId: count}` | raw tap counts; non-numeric or negative values dropped. Counts may exceed the target; clamp on read as `countForState` does |
| `adhkar.today.targets.{morning,evening}` | `{itemId: target}` | chosen target for items with `targetOptions`; values outside the options mean "use `defaultTarget`" |
| `adhkar.history` | array, newest first, ≤7 | `date`, `morning`, `evening` (booleans: complete by counters or manually), `morningAt`, `eveningAt` (UTC instant or null) |
| `ruqyah.today` | object | `ruqyah-daily-v1`: `date`, `counts` (`{segmentId: count}`, already clamped to `repeat`) |
| `ruqyah.history` | `{date: {completedAt}}`, ≤365 | days on which every segment was completed |
| `reminders` | object | `athkar-reminders-v2`: `morning.enabled`, `evening.enabled`, `calculationMethod`, `asrSchool`, `lastShown.{morning,evening}` (local date or null) |
| `reminders.location` | object, optional | `latitude`, `longitude` (4 decimals as stored by the PWA), `updatedAt`. Present **only** if the user ticked "include location" at export; the native importer rounds to 2 decimals (§7.4) |
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
