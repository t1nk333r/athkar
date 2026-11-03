# Prayer tracker (1.0)

The tracker records, per day, which of the five obligatory prayers the user says they prayed
(MOBILE_APP_PLAN.md §6, NATIVE_APP_PLAN.md §3.3 1.0 column). The PWAs have no tracker, so these rules and their
fixtures are written by hand, not generated. The native implementations (Swift first, Kotlin later) must pass
the fixtures in `fixtures/`. Storage is the `prayer_records` table ([`../schema.md`](../schema.md), migration v5).

1.1 adds travel, combining and shortening, make-up links, not-applicable date ranges, optional prayers, notes and
congregation. None of them is part of this file.

## Occurrence

An occurrence is one prayer on one day: `(date, prayer)`.

- `date` is the calculation date, a `YYYY-MM-DD` civil date. It is the day the user is looking at when they
  record: today on the Today screen, or the day open in the calendar. A command for a string that is not a real
  calendar day is refused (`invalid-date`).
- `prayer` is `fajr`, `dhuhr`, `asr`, `maghrib` or `isha`. Sunrise is not a prayer.

An occurrence has at most one record. The record holds the entry the user chose and the metadata captured when
the record was first created.

## Entry

| Field | Values | Rule |
| --- | --- | --- |
| `state` | `unrecorded`, `prayed`, `not_applicable` | `unrecorded` is the default. It is neutral. No missed, failed or late value exists anywhere in the model, and nothing turns `unrecorded` into anything else by itself. |
| `timing` | `null`, `on_time`, `late`, `made_up` | Only on `prayed`. The user chooses it; the app never derives it from the clock. |
| `noon` | `null`, `dhuhr`, `jumuah` | Only on a `prayed` Dhuhr on a Friday. It records which noon prayer the user performed, in the single Dhuhr slot. `null` means the user did not say. The app does not infer eligibility. |
| `loggedAt` | instant or `null` | When the current state was set. It is `null` exactly when the state is `unrecorded`. Changing `timing` or `noon` keeps it. |

Friday is the weekday of `date` in the proleptic Gregorian calendar; it does not depend on a zone.

## Metadata

When a command creates a record, the record captures three values from the command's context:

- `zone`: the IANA zone the device used.
- `scheduledAt`: the occurrence's calculated time as a UTC instant, or `null` when it could not be computed (no
  location, or a polar day or night).
- `profileVersion`: the calculation profile the time came from, as text in the form
  `<method>/<asr school>/<high-latitude rule>/<fajr>,<sunrise>,<dhuhr>,<asr>,<maghrib>,<isha>`. It uses the setting
  values of spec/schema.md and the adjustments in whole minutes, for example
  `umm-al-qura/standard/twilight-angle/0,0,0,0,0,0`. The Hijri offset is not part of it.

These values are never rewritten. A later command on the same occurrence keeps them, whatever its context. A
zone change on the same date, a changed method, or a record made from another zone after the date line all reuse
the existing record. Changing the method later never moves, duplicates or recalculates a record.

A command that leaves nothing to store (it is `unchanged` and there is no record) creates no record. Commands
never delete records. `unrecord`, an undo and `clearDay` set the entry back to `unrecorded` and keep the metadata.
Only a history removal (a future delete-all) deletes records.

## Today and the future

`today` is the civil date of the command's `now` in its zone. A command whose `date` is after `today` is refused
(`future-date`), and so is `clearDay` for such a date. A record made after midnight stays on the occurrence it
names: yesterday's Isha recorded at 00:30 is yesterday's record. A prayer later today may be recorded; the app
makes no claim about any prayer's window.

## Commands

Each command returns `changed` (the stored record is new or different), `unchanged` (nothing is written, so
`updatedAt` keeps its value) or `refused` with a reason (nothing is written). A change sets `updatedAt` to `now`.
The checks run in this order: `invalid-date`, `future-date`, then the command's own.

| Command | From `unrecorded` (or no record) | From `prayed` | From `not_applicable` |
| --- | --- | --- | --- |
| `record` (`noon` optional) | `prayed`, `loggedAt` = now, `noon` if given | unchanged; a `noon` different from the stored one replaces it | `prayed`, `loggedAt` = now, `noon` if given |
| `unrecord` | unchanged | `unrecorded`: `timing`, `noon` and `loggedAt` become `null` | the same |
| `setTiming` (`timing` or `null`) | refused `not-prayed` | sets it; unchanged when equal | refused `not-prayed` |
| `markNotApplicable` | `not_applicable`, `loggedAt` = now | `not_applicable`: `timing` and `noon` become `null`, `loggedAt` = now | unchanged |
| `unmarkNotApplicable` | unchanged | unchanged | `unrecorded` |
| `restore` (an entry) | the entry; unchanged when equal | the same | the same |

- `record` with a `noon` on anything but a Friday Dhuhr is refused (`not-friday-dhuhr`), from every state.
- `restore` is the undo. The app keeps the entry an occurrence had before a command and restores it. An entry that
  breaks the rules above (a `timing` without `prayed`, a `noon` without a Friday `prayed` Dhuhr, a `loggedAt` that
  is missing for `prayed` or `not_applicable` or present for `unrecorded`) is refused (`invalid-entry`).
- `clearDay(date)` applies `unrecord` to every record of `date` in one transaction. It is `changed` when any record
  changed. The app asks for confirmation before it runs.

The same command applied twice in a row returns `unchanged` the second time. This makes `record` idempotent. A
"record as prayed" sent twice, from the app or later from a notification action, stores one record.

## Calendar month

The calendar shows one month (`month`: `YYYY-MM`) as one summary per day:

| Field | Meaning |
| --- | --- |
| `date` | The day. |
| `weekday` | 1 Sunday … 7 Saturday. The grid starts each week on Saturday. |
| `future` | `date` is after `today`. The app shows it read-only. |
| `prayed` | Records with `prayed`. |
| `notApplicable` | Records with `not_applicable`. |
| `unrecorded` | 5 − `prayed` − `notApplicable`: records with `unrecorded` and occurrences with no record alike. |
| `applicable` | 5 − `notApplicable`: the denominator. `not_applicable` is never counted against the day. |
| `morning`, `evening` | An `adhkar_days` row exists for that period on `date`. |
| `ruqyah` | A `ruqyah_days` row exists for `date`. |

`totals` counts the month: `prayed` (all records with `prayed`), and `morning`, `evening` and `ruqyah` (the days
with each). These are plain counts. The summary has no score, percentage, streak or missed count, and the
calendar never styles `unrecorded` as a failure. A record or completion outside the month is ignored.

## Next prayer across a DST change

Today's next prayer is the first of the five prayers, in order, whose time is strictly after `now`. The prayers are
taken from the schedule of `today` (the civil date of `now` in the zone) and then from the schedule of the next
civil date (`today` plus one calendar day, not plus 24 hours). Sunrise is skipped, and so is a clamped Asr
(`NextPrayer.after`). On a 23-hour or 25-hour day this is still the right prayer, because the day is chosen by
civil date, and both readings of a repeated wall-clock hour belong to the same date.

`fixtures/next-prayer.json` checks this against `../prayer-times/vectors.json` on DST transition days in New York,
London and Sydney, with method `mwl`, Asr `standard`, the default high-latitude rule and the vectors' tolerance. Each
expected time is the vector's `fajr` or `asr`, or its `sunset` for Maghrib (`mwl` has no Maghrib offset).

## Fixtures

| File | Rule | Case input | Expected |
| --- | --- | --- | --- |
| `fixtures/transitions.json` | Commands | `records` before, then `steps`: each a `command`, `date`, `prayer` and the context (`now`, `timeZone`, `profileVersion`, `scheduledAt`) | `results`, one per step, and `records` after |
| `fixtures/calendar.json` | Calendar month | `today`, `month`, `records` (`date`, `prayer`, `state`), `adhkarDays` (`date`, `period`), `ruqyahDays` | `days` and `totals` |
| `fixtures/next-prayer.json` | Next prayer | the location, `timeZone`, method, Asr school and `now` | `today`, and the next `prayer` with its calculation `date` and `at` |

The fixtures use the common shape of [`../README.md`](../README.md). The effective input is
`{ ...defaultInput, ...case.input }`, and a step's context fields default to the case's. Instants are
`toISOString()` text.

- A command is `{"kind": "record"}`, `{"kind": "record", "noon": "jumuah"}`, `{"kind": "unrecord"}`,
  `{"kind": "setTiming", "timing": "late"}` (or `null`), `{"kind": "markNotApplicable"}`,
  `{"kind": "unmarkNotApplicable"}`, `{"kind": "restore", "entry": {state, timing, noon, loggedAt}}`,
  `{"kind": "clearDay"}` (no `prayer`), or `{"kind": "undo"}`. `undo` is the app's undo, not a domain command. It
  is `restore` of the entry the occurrence had before the previous step.
- A result is `"changed"`, `"unchanged"` or `{"refused": "<reason>"}`.
- A record is `{date, prayer, zone, scheduledAt, profileVersion, state, timing, noon, loggedAt, updatedAt}`.
  `records` lists every stored record, by `date` and then in prayer order.
