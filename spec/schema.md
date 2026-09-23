# Local schema

The native apps' SQLite database (NATIVE_APP_PLAN.md §6). iOS implements it with GRDB migrations in
`ios/AthkarCore/Sources/AthkarCore/Storage/AppDatabase.swift`. Android will implement the final schema here
when it starts (§9.2). A test (`StorageSchemaTests`) checks that every table, column, type, nullability and
primary key below matches what migration `v1` creates. Update this file in the same commit as any migration.

## Conventions

- **Types** are SQLite declared types, written exactly as in the `CREATE TABLE` statements.
- **Local dates** are `TEXT` in the form `YYYY-MM-DD`: the PWAs' `localDateKey`, a civil date in the device's
  zone at the time of the event. A `CHECK (… GLOB …)` enforces the shape. Writers only store real calendar
  days.
- **Instants** are `TEXT` in the form `YYYY-MM-DDTHH:MM:SS.sssZ`: UTC with exactly three fraction digits, as JS
  `Date.prototype.toISOString()` writes them. Sub-millisecond precision is truncated, not rounded, as in JS. The
  backup envelope uses the same form. A `CHECK (… GLOB …)` enforces the shape. Text order is time order.
- **Booleans** are `INTEGER` 0 or 1.
- **Enumerations** are `TEXT`. The allowed values are listed in the notes and enforced by `CHECK`.
- **JSON** values are `TEXT` holding one JSON value (object, array, string, number or boolean).
- **Foreign keys** are enforced (`PRAGMA foreign_keys = ON`).
- **WAL** journal mode on disk.
- The schema uses no SQLite features newer than 3.8 (no `STRICT`, no JSON1), so any Android API level can
  implement it.

## Migrations

- Migrations are numbered `v1`, `v2`, … and applied in order. On iOS the number is the GRDB `DatabaseMigrator`
  identifier. On Android it is the Room/SQLDelight schema version.
- They are forward-only. There are no down-migrations, and a migration never changes once it has shipped in a
  build that reached any user. A change is always a new migration.
- Each migration ships with a test that opens a database seeded at the previous version and checks the data
  survives (MOBILE_APP_PLAN.md §17).
- A new migration updates this file: the table sections, the migration list below, and the backup mapping if
  it is affected.

| Migration | Contents |
| --- | --- |
| `v1` | All tables below. |

## Tables (migration v1)

### `settings`

Key/value settings. Holds appearance and deck preferences (mirrored in the backup envelope), the calculation
profile, and later the Hijri offset.

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `key` | TEXT | no | PK | See keys below. |
| `value_json` | TEXT | no | | JSON value. |
| `origin` | TEXT | no | | `native`, `athkar-pwa`, `ruqyah-pwa`: who wrote the row. Used only for import precedence. |
| `updated_at` | TEXT | no | | Instant. |

| Key | JSON value | Default when absent | PWA source |
| --- | --- | --- | --- |
| `theme` | `"system"` \| `"light"` \| `"dark"` | `"system"` | `athkar-theme` / `ruqyah-theme` |
| `text_size` | `"small"` \| `"medium"` \| `"large"` | `"medium"` | `athkar-reading-text-size` / `ruqyah-text-size` |
| `line_spacing` | `"compact"` \| `"comfortable"` \| `"wide"` | `"comfortable"` | `athkar-line-spacing` / `ruqyah-line-spacing` |
| `haptics` | boolean | `true` | `athkar-haptics` / `ruqyah-haptics` ≠ `"off"` |
| `long_order` | `"last"` \| `"original"` | `"original"` | `athkar-long-order-v1` |
| `long_order_prompt_answered` | boolean | `false` | `athkar-long-order-prompt-v1` |
| `calculation_method` | `"mwl"` \| `"umm-al-qura"` \| `"egyptian"` \| `"karachi"` \| `"north-america"` | `"mwl"` | `athkar-reminders-v2.calculationMethod` |
| `asr_school` | `"standard"` \| `"hanafi"` | `"standard"` | `athkar-reminders-v2.asrSchool` |

Defaults are applied on read and never written. A row exists only once the user (or an import) sets a
value, so an import at onboarding is not shadowed by rows the app invented.

### `content_installs`

The installed version of each bundled content pack (§5.4).

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `pack_id` | TEXT | no | PK | Pack key in `content/manifest.json` (`adhkar`, `ruqyah`). |
| `version` | TEXT | no | | Semantic version from the manifest. |
| `checksum` | TEXT | no | | Lowercase hex SHA-256 of the pack file (manifest `sha256`). |
| `installed_at` | TEXT | no | | Instant. |

### `adhkar_days`

One row per (date, period) whose adhkar session is complete. Replaces the PWA's 7-entry `history`.

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `local_date` | TEXT | no | PK 1 | Local date. |
| `period` | TEXT | no | PK 2 | `morning`, `evening`. |
| `completed_at` | TEXT | yes | | Instant. Null when unknown: a PWA history entry or manual completion without a time. |
| `completion_origin` | TEXT | no | | `counters` (every counted item reached its target), `manual` (the PWA's `manualCompletion`), `import` (from a backup file, which does not say how). |

### `adhkar_item_progress`

Tap counts and chosen targets per item, per (date, period). Today's rows are the live counters. Past days keep
their rows, and are not collapsed to booleans as the PWA's `rollStateToDate` does.

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `local_date` | TEXT | no | PK 1 | Local date. |
| `period` | TEXT | no | PK 2 | `morning`, `evening`. |
| `item_id` | TEXT | no | PK 3 | Content ID (`morning-NN`, `evening-NN`), immutable once shipped. |
| `count` | INTEGER | yes | | Raw tap count, ≥ 0. Not clamped: it may exceed the target. Null means no count recorded (the item has a chosen target but no `progress` entry) and reads as 0. |
| `target` | INTEGER | yes | | Chosen target, ≥ 0. Null means the item's default. A value that is not one of the item's `targetOptions` also means the default, as in `targetForState`. |
| `updated_at` | TEXT | no | | Instant. |

`CHECK (count IS NOT NULL OR target IS NOT NULL)`: a row with neither is deleted instead.

The rows for one (date, period) are exactly the union of the PWA's `progress[period]` and `targets[period]`
maps. `target` is stored per day, so changing a target tomorrow does not rewrite yesterday.

### `ruqyah_days`

One row per local date on which every ruqyah segment was completed (`ruqyah-daily-v1.history`).

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `local_date` | TEXT | no | PK | Local date. |
| `completed_at` | TEXT | no | | Instant. |
| `completion_origin` | TEXT | no | | `counters`, `import`. Ruqyah has no manual completion. |

### `ruqyah_segment_progress`

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `local_date` | TEXT | no | PK 1 | Local date. |
| `segment_id` | TEXT | no | PK 2 | Segment ID from the ruqyah pack (`qaf-1-8` … `nas-1-6`). |
| `count` | INTEGER | no | | Repetitions read, 0 … the segment's `repeat`. |
| `updated_at` | TEXT | no | | Instant. |

### `reminder_rules`

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `id` | TEXT | no | PK | Stable. The two adhkar rules use their kind as ID. Other rules use a generated ID. |
| `kind` | TEXT | no | | `adhkar_morning`, `adhkar_evening`, `prayer`, `personal`. |
| `prayer_key` | TEXT | yes | | `fajr`, `dhuhr`, `asr`, `maghrib`, `isha`. Set for prayer-relative rules. |
| `offset_minutes` | INTEGER | yes | | Minutes after (negative: before) the prayer. Set if and only if `prayer_key` is set. |
| `local_time` | TEXT | yes | | `HH:MM`, 00:00 … 23:59, for fixed-time rules. Set if and only if `prayer_key` is null. |
| `weekday_mask` | INTEGER | no | | 0 … 127. Bit *n* is weekday *n* + 1 in `Calendar` numbering (bit 0 Sunday … bit 6 Saturday). 127 means every day. |
| `enabled` | INTEGER | no | | Boolean. |
| `updated_at` | TEXT | no | | Instant. |

Checks:

- `kind NOT IN ('adhkar_morning', 'adhkar_evening') OR id = kind`, so there is at most one rule per adhkar
  period.
- `(prayer_key IS NULL) = (offset_minutes IS NULL)`.
- `(prayer_key IS NULL) <> (local_time IS NULL)`.
- `local_time GLOB '[01][0-9]:[0-5][0-9]' OR local_time GLOB '2[0-3]:[0-5][0-9]'`.

The adhkar rules default to `fajr` + 60 and `asr` + 60, which reproduces the PWA's fixed offsets.

### `reminder_state`

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `rule_id` | TEXT | no | PK | `REFERENCES reminder_rules(id) ON DELETE CASCADE`. |
| `last_shown_local_date` | TEXT | no | | Local date. The last day the rule's notification was shown (`athkar-reminders-v2.lastShown`), needed for the 15-minute catch-up. No row means never shown. |

### `location_profiles`

1.0 has at most one profile.

| Column | Type | Null | Key | Notes |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no | PK | `CHECK (id = 1)`: at most one row. |
| `label` | TEXT | yes | | User-facing name, if any. |
| `latitude` | REAL | no | | −90 … 90, rounded to 2 decimals before storage (§7.4). |
| `longitude` | REAL | no | | −180 … 180, rounded to 2 decimals before storage (§7.4). |
| `zone_id` | TEXT | yes | | IANA zone. Null means the device's current zone, the only 1.0 behaviour. |
| `source` | TEXT | no | | `device` (one-shot location), `manual`, `import`. |
| `updated_at` | TEXT | yes | | Instant the coordinates were obtained. Null if unknown (a PWA location without `updatedAt`). |

Rounding is JavaScript/Kotlin `Math.round(x × 100) / 100`, computed as `floor(x × 100 + 0.5) / 100` in IEEE
doubles: exact halves go toward +∞, so `-33.865` → `-33.86` and `33.865` → `33.87`.

## Future tables (not in v1)

- 1.0, added by later slices' migrations: `prayer_records` (unique on `(calculation_date, prayer_key)`, per
  MOBILE_APP_PLAN.md §11 `prayer_logs`) and `notification_audit` (redacted).
- 1.1: `not_applicable_ranges`, `favorites`, `optional_practices`.

## Invariants

- An adhkar period is complete for a date if and only if an `adhkar_days` row exists. Writers keep the row in
  step with the counters and with manual completion.
- Readers clamp counters to the effective target, exactly as `countForState` does: floor, then
  `min(count, target)`. Storage keeps raw counts.
- A `review`-kind item never takes part in completion (`periodCountersComplete`).
- Rollover is a pure function of `local_date`. Nothing is deleted at midnight.
- A ruqyah date is complete if and only if a `ruqyah_days` row exists.

## Backup import (envelope v1)

Import validates the whole file first. It rejects everything `spec/backup/envelope-v1.schema.json` and
`tools/backup-validate.mjs` reject: unknown keys at any depth, sections not allowed for `meta.app` (athkar-pwa:
`adhkar`, `reminders`, `preferences` required, no `ruqyah`; ruqyah-pwa: `ruqyah`, `preferences` required, no
`adhkar` or `reminders`), `longOrder`/`longOrderPromptAnswered` present in a ruqyah file or missing from an
athkar file, dates that are not calendar days, instants that are not real UTC times, adhkar history that is not
strictly newest-first or has an entry on or after `adhkar.today.date`, ruqyah history after `ruqyah.today.date`,
and counts or targets that are negative, non-finite, or above 2^53 − 1 (`Number.MAX_SAFE_INTEGER`). It then
merges the file in one transaction, so a file that fails validation changes nothing. Imported rows get
`updated_at = meta.exportedAt`, which makes import deterministic.

### Mapping

| Envelope | Rows |
| --- | --- |
| `adhkar.today.progress[p]`, `targets[p]` | `adhkar_item_progress` (`today.date`, p, item). One row per key in either map. `count` is the progress value floored (null if the item only has a target). `target` is the target value; a non-integer target is dropped, since it can never match an option and so already means the default. |
| `adhkar.today.manualCompletion[p]` = true | `adhkar_days` (`today.date`, p), `completion_origin = manual`, `completed_at = completedAt[p]` (may be null). |
| `adhkar.today.completedAt[p]` set, not manual | `adhkar_days` (`today.date`, p), `completion_origin = import`. Trusted-exporter behaviour: the PWA sets `completedAt` only while the period is complete, so the importer does not re-check the counters (it has no content pack). A hand-edited file can therefore mark a day complete. |
| `adhkar.history[]`, `morning`/`evening` = true | `adhkar_days` (`date`, p), `completion_origin = import`, `completed_at = morningAt`/`eveningAt`. |
| `ruqyah.today.counts` | `ruqyah_segment_progress` (`today.date`, segment), zeros included. |
| `ruqyah.history` | `ruqyah_days`, `completion_origin = import`. |
| `reminders.morning`/`evening.enabled` | `reminder_rules` `adhkar_morning` (`fajr` + 60) / `adhkar_evening` (`asr` + 60). |
| `reminders.lastShown` | `reminder_state` for those rules (non-null values only). |
| `reminders.calculationMethod`, `asrSchool` | `settings` `calculation_method`, `asr_school`. |
| `reminders.location` | `location_profiles`, rounded to 2 decimals, `source = import`, `zone_id` null. |
| `preferences.*` | `settings` `theme`, `text_size`, `line_spacing`, `haptics`, `long_order`, `long_order_prompt_answered`. |

### Merge rules

- Each file merges into its own tables. The two files may be imported alone or both, in either order, and the
  result is the same.
- Merge units, each decided as a whole:
  - adhkar `(local_date, period)`: the `adhkar_days` row and all `adhkar_item_progress` rows for that pair;
  - ruqyah `(local_date)`: `ruqyah_days`;
  - ruqyah `(local_date, segment_id)`: `ruqyah_segment_progress`.
- An existing unit wins unless it is **empty**. Then the imported unit replaces it.
  - An adhkar unit is empty when it has no `adhkar_days` row and no positive `count`. Chosen targets alone do
    not count as progress.
  - A segment row is empty when its `count` is 0.
  - A `ruqyah_days` row is never empty.
  - An imported adhkar unit with no rows and no completion contributes nothing.
- Keyed singletons (the two adhkar `reminder_rules`, their `reminder_state`, the `location_profiles` row):
  an existing row wins.
- `settings` rows go by origin precedence: `native` > `athkar-pwa` > `ruqyah-pwa`. An imported value is written
  only if there is no row, or if the existing row's origin ranks lower. On a tie the existing row stays. So
  preferences from the athkar file win over the ruqyah file in either order, and values the user set in the
  app are never overwritten.
- Together these make re-import a no-op.

## Backup export and round trip

`BackupExporter` writes what the named PWA would export from the database. For the athkar PWA that is `adhkar`,
`reminders` and `preferences` (with `longOrder` keys). For the ruqyah PWA it is `ruqyah` and `preferences`. The
caller passes `today` (the local date), the zone, the export instant, and the per-export location opt-in.

- `adhkar.history` lists the dates before `today` that have any adhkar row, newest first, capped at 7. A period
  is `true` if and only if its `adhkar_days` row exists.
- `ruqyah.history` lists the `ruqyah_days` rows up to `today`, newest 365.
- `ruqyah.today.counts` are the stored counts as they are. The exporter has no content pack, so it does not
  clamp to `repeat`; readers clamp (spec/backup/envelope-v1.md).
- A setting with no row exports its default.

Import followed by export with the file's own `meta` reproduces the file in every section it contained, with
these exceptions:

1. **Location precision.** Coordinates come back rounded to 2 decimals. §7.4 exists so that ≈11 m coordinates
   are never persisted. Keeping the original next to the rounded value would defeat it, so round-trip equality
   compares `reminders.location.latitude`/`longitude` after rounding the original to 2 decimals.
2. **History days with nothing complete.** The PWA writes a history entry for every day it rolled over, even
   with `morning` and `evening` both false. Such an entry carries no worship data, and the native model
   records completion, not app opens. It is not stored and does not come back. The same applies to a
   `morningAt`/`eveningAt` on a period that is not complete (a stale instant).
3. **Shapes the PWAs never write.** A fractional count comes back floored. A fractional target is dropped. An
   instant written with other than three fraction digits comes back with three (truncated to milliseconds).

The example files in `spec/backup/examples/` contain none of 2 and 3, and round-trip exactly apart from 1.
