# Backup envelope, format 2

The native app's own backup (NATIVE_APP_PLAN.md §6.4, §11 item 12). «تصدير نسخة احتياطية» in الإعدادات writes it as a
`.athkarbackup` file and hands it to the share sheet; the same app on another device, or on this one after
«حذف كل البيانات», restores it from «استيراد ملف» or by opening the file. Machine-checkable schema:
[`envelope-v2.schema.json`](envelope-v2.schema.json). Validate a file with `node tools/backup-validate.mjs <file>`,
which reads either format. [`examples/native.athkarbackup`](examples/native.athkarbackup) is a format 2 file.

Format 1 ([`envelope-v1.md`](envelope-v1.md)) stays the PWAs' format, and the app keeps importing it. A PWA cannot
read format 2: it carries tables the PWAs never had.

## The file

- One UTF-8 JSON document, extension `.athkarbackup`, MIME type `application/json`, named
  `athkar-backup-YYYY-MM-DD.athkarbackup` after the device's local date. Read as format 1 is: one leading BOM is
  stripped, bytes that are not UTF-8 reject the file, and the text follows `JSON.parse` (a duplicated key keeps its
  last value). `meta.format` is read first, so a later format is reported as such (`unsupportedFormat`), not as a
  damaged file.
- **Plaintext.** The file holds the user's worship history in the clear. Nothing leaves the device unless the user
  shares it, and the export screen says so. Passphrase protection is out of scope for 1.x.
- **Location excluded by default.** `reminders.location` is written only when the user switches on «تضمين الموقع» for
  that export; the switch starts off every time the screen opens. The coordinates are the stored ones, rounded to 2
  decimals (§7.4).
- Every section is required; a section's array may be empty. A preference or prayer setting appears only when the
  user set it (its `settings` row exists); an absent one reads as its default on import, and stays absent.
- Rows are the tables' rows (spec/schema.md), sorted by their keys as text (adhkar days by date then period, so
  `evening` before `morning`), «مسبحة» counts by date then first use, prayer records by date then Fajr … Isha. The
  whole history is exported: the native tables keep no window, and nothing is trimmed.
- `updated_at` is not exported. Each imported row is stamped with `meta.exportedAt`, as format 1's are. A
  location's `source` is not exported either; an imported location is `import`.
- Keys whose value may be `null` (`completedAt` of an adhkar day, `count`/`target` of an item, a prayer record's
  `scheduledAt`, `timing`, `noonPrayer`, `loggedAt`, a rule's `prayer`, `offsetMinutes`, `localTime`, a location's
  `label`, `zoneId`, `updatedAt`) are always written, as `null` when empty. No other key may be `null`, and no key
  outside the schema is allowed at any depth.

## Sections

| Field | Type | Source |
| --- | --- | --- |
| `meta.format` | `2` | constant |
| `meta.app` | `"athkar-native"` | constant: the iOS app now, the Android app later |
| `meta.exportedAt` | UTC instant | the export's time, `toISOString()` form |
| `meta.timeZone` | IANA zone | the device's zone at export; every `date` is the local date its row was written on |
| `preferences` | object | `settings` rows `theme`, `text_size` → `textSize`, `line_spacing` → `lineSpacing`, `haptics`, `long_order` → `longOrder`, `long_order_prompt_answered` → `longOrderPromptAnswered`, `home_prayer_row` → `homePrayerRow`; the values of spec/schema.md |
| `prayerSettings` | object | the calculation profile (§6.4 `prayerSettings`): `calculation_method` → `calculationMethod` (all 12 methods, native presets included), `asr_school` → `asrSchool`, `high_latitude_rule` → `highLatitudeRule`, `prayer_adjustments` → `adjustments` (`fajr` … `isha`, whole minutes −30 … 30), `hijri_offset` → `hijriOffset` (−2 … 2) |
| `adhkar.days[]` | `{date, period, completedAt, origin}` | `adhkar_days`; `origin` is `completion_origin` (`counters`, `manual`, `import`) |
| `adhkar.items[]` | `{date, period, itemId, count, target}` | `adhkar_item_progress`; `count` and `target` are integers 0 … 2^53 − 1, not both `null` |
| `ruqyah.days[]` | `{date, completedAt, origin}` | `ruqyah_days`; `origin` is `counters` or `import` |
| `ruqyah.segments[]` | `{date, segmentId, count}` | `ruqyah_segment_progress` |
| `ruqyah.suras[]` | `{date, suraId, completedAt}` | `ruqyah_sura_days` (the ruqyah per-sura completions) |
| `suwar.selected` | string, optional | `suwar_selected_sura` |
| `suwar.pages[]` | `{date, suraId, pageId, readAt}` | `suwar_page_reads` |
| `suwar.suras[]` | `{date, suraId, completedAt}` | `suwar_sura_days` |
| `tasbih.selected`, `.target`, `.phrases` | optional | `tasbih_selected`, `tasbih_target` (0 … 9999), `tasbih_custom_phrases` (≤ 8, each 1 … 60 UTF-16 code units) |
| `tasbih.counts[]` | `{date, phrase, count, firstUse}` | `tasbih_counts`: `phrase` is `phrase_key` (a preset ID or `c:` and a saved phrase, 1 … 62 code points), `count` 1 … 99999, `firstUse` ≥ 1 and unique within a date |
| `prayers.records[]` | `{date, prayer, zone, scheduledAt, profile, state, timing, noonPrayer, loggedAt}` | `prayer_records` with its metadata (spec/tracker/tracker.md): `date` is `calculation_date`, `zone` `zone_id`, `profile` `profile_version` |
| `reminders.rules[]` | `{id, kind, prayer, offsetMinutes, localTime, weekdays, enabled}` | `reminder_rules`; `prayer` is `prayer_key`, `weekdays` `weekday_mask` (0 … 127) |
| `reminders.lastShown` | `{ruleId: date}` | `reminder_state`; every key is the `id` of a rule in `rules` |
| `reminders.location` | object, optional | `location_profiles`: `latitude`, `longitude`, `label`, `zoneId`, `updatedAt`. Only with «تضمين الموقع» |

What format 2 carries that format 1 does not: the whole adhkar and ruqyah history (format 1 keeps 7 and 365 days
and only completion for past days), the ruqyah per-sura completions, «سور», «مسبحة», the prayer tracker's records,
every reminder rule with its weekdays, the full calculation profile and Hijri offset, `home_prayer_row`, and the
location's label and zone.

Not exported: `content_installs` (the installed pack versions are the app's, not the user's), diagnostics times, and
the app's `UserDefaults` flags.

## Validity

The importer rejects the whole file, writing nothing, under exactly the conditions `tools/backup-validate.mjs`
checks:

- the schema, and the calendar checks of format 1: every date a real proleptic-Gregorian day, every instant a real
  time, applied to the schema's date and instant fields only;
- each table's key unique: adhkar days `(date, period)`, items `(date, period, itemId)`, ruqyah days `(date)`,
  segments `(date, segmentId)`, suras `(date, suraId)`, «سور» pages `(date, pageId)`, «مسبحة» counts
  `(date, phrase)` and `(date, firstUse)`, prayer records `(date, prayer)`, rules `(id)`. Keys compare as code
  points, as SQLite compares text;
- no ID contains U+0000 (SQLite would store it truncated);
- the tables' checks: an item has a `count` or a `target`; only a `prayed` record has a `timing`; only a prayed Dhuhr
  on a Friday has a `noonPrayer`; `loggedAt` is set exactly when the state is not `unrecorded`; an adhkar rule's
  `id` is its `kind`; a rule has `prayer` and `offsetMinutes` together or `localTime` alone; a `lastShown` key
  names a rule in the file.

## Import rules (native side)

The file merges into the tables in one transaction. The device wins wherever it already has something: a unit is
imported only when the device has nothing for it. So a file restores everything on a fresh install, adds what is
missing on a device in use, and importing it again writes nothing.

| Unit | Imported when |
| --- | --- |
| adhkar `(date, period)`: its completion and item rows together | the device's session is empty (format 1's rule) |
| ruqyah completion `(date)` | the device has no row |
| ruqyah count `(date, segment)` | the device's count is absent or 0; clamped to the segment's `repeat` in the installed pack, unknown segments dropped (format 1's rule) |
| ruqyah sura `(date, sura)` | the device has no row |
| «سور» `(date, sura)`: its pages and completion together | the device has no page and no completion of that sura on that date |
| «مسبحة» `(date)`: the day's counts together, so the first-use order stays whole | the device has no count on that date |
| prayer record `(date, prayer)`, metadata as written | the device has no record, or its record is still `unrecorded` and the file's is not |
| reminder rule `(id)`; its last shown date | the device has no rule with that `id`; no last shown date for it |
| location | the device has none (source `import`) |
| each setting | as format 1's settings, with origin `native`: it replaces a row a PWA import wrote, never one the user set in the app |

A dry run of the same merge, rolled back, gives the review screen its list (what each section would add); the
confirmation then runs it for real.

## Round trip

Exporting a fresh install that imported a format 2 file reproduces that file exactly: the same rows, settings and
`lastShown`, given the same `meta`. The location round-trips only when the file had one and the export includes it.
`AthkarCoreTests` checks this with the example file.
