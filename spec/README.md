# Golden fixtures

These files record what the PWA (`index.html`) does today. The native implementations (Swift first, Kotlin
later) must pass them (NATIVE_APP_PLAN.md §4.3).

## Regenerating

```sh
node tools/fixtures-generate.mjs
```

The script needs no npm packages. It cuts the real functions out of the application `<script>` in
`index.html` and runs them in a `node:vm` context. Only UI side effects are stubbed: rendering, dialogs, and
live-region text. `openConfirmation` is stubbed to accept the confirmation. The clock is fixed per case, and
`TZ` is set per case to that case's `timeZone`. The output is byte-identical on every run, whatever the host
time zone. Regenerate only after deliberately changing the PWA behaviour, and review the diff.

## Common shape (`spec/sessions/fixtures/*.json`, `spec/reminders/fixtures/*.json`)

```json
{
  "about": "rule under test",
  "source": "index.html functions exercised",
  "generator": "tools/fixtures-generate.mjs",
  "defaultInput": { "timeZone": "Asia/Riyadh", "collections": { "morning": [...], "evening": [...] } },
  "cases": [ { "name": "...", "input": { ... }, "expected": { ... } } ]
}
```

- **Effective input** is `{ ...defaultInput, ...case.input }`, a shallow merge where the case wins.
- **`collections`** lists the adhkar items with only the fields the rules read: `id`, `count`,
  `targetOptions`, `defaultTarget`, and `review`. The default is the shipped content. Cases that need a
  rule the shipped content does not trigger override it with synthetic items (`s-*`, `t-*`, `u-*`):
  review items, the 9/10 long-item threshold, and decks shorter than three items.
- **`timeZone`** is an IANA zone. Local dates (`YYYY-MM-DD`) and local wall-clock times are interpreted in it.
- **`now`** is an ISO-8601 UTC instant. `nowLocal` is the same instant written in `timeZone`, for readers only.
- **`state`** is an `athkar-progress-v2` object:
  `{date, progress, targets, completedAt, manualCompletion, history[]}`.
  - Each history entry is `{date, morning, evening, morningAt, eveningAt}`.
  - Timestamps (`completedAt`, `morningAt`, `eveningAt`) are ISO strings or `null`.

| File | Function(s) | Case input | Expected |
| --- | --- | --- | --- |
| `sessions/fixtures/period-is-complete.json` | `periodIsComplete`, `periodCountersComplete`, `periodIsManuallyComplete` | `state` | per period `{countersComplete, manuallyComplete, complete}` |
| `sessions/fixtures/roll-state-to-date.json` | `rollStateToDate` | `state`, `nextDate` | rolled `state` |
| `sessions/fixtures/load-state.json` | `loadState` (`normalizeState` + rollover at local midnight) | `now`, `timeZone`, `storage` (localStorage key → raw string) | resulting `state` |
| `sessions/fixtures/build-deck.json` | `buildDeck`, `isLongDhikr` | `longAdhkarLast`, `state` (targets) | per period `{deck: [ids], longItems: [ids]}` |
| `sessions/fixtures/first-incomplete-index.json` | `firstIncompleteIndex` | `longAdhkarLast`, `state` | per period `{index, itemId}` |
| `sessions/fixtures/completion-sync.json` | `syncCompletionState`, `setManualCompletion` | `now`, `state`, `operation` | `returned` (sync only, else `null`), resulting `state` |
| `sessions/fixtures/scoped-reset.json` | `resetDayProgress` / `resetWeek` / `resetEverything`, `hasResettableState` | `now`, `timeZone`, `scope` (`day`/`week`/`everything`), `state` | `hasResettableStateBefore`, `deletedHistoryDates` (week), resulting `state` |
| `reminders/fixtures/next-reminder-time.json` | `nextReminderTime`, `scheduleReminders`, `prayerTimesForDate` | `now`, `timeZone`, `preferences` (the `athkar-reminders-v2` shape), `state`, `notificationPermission` | `todaySchedule`, per period `nextReminderTime`, and per period `scheduled: {delayMs, fireAt}` or `null` |

### Reminder notes

- `nextReminderTime` ignores completion.
- `scheduled` is the result of `scheduleReminders`. A period is skipped when it is disabled, when
  permission is not `granted`, when `periodIsComplete` is true, or when no time can be computed.
- The catch-up time is `now + 300 ms`, exactly as the PWA does it.
- The native notification IDs (`adhkar.<period>.<local_date>`, §7.5) are new. The PWA has no
  equivalent at scheduling time, so the fixtures do not record them.

## `spec/prayer-times/vectors.json`

The file header contains:

- `tolerance`: 120 s, from NATIVE_APP_PLAN.md §7.2 P1.
- The method and Asr-factor tables, read from the PWA.
- `highLatitudeRule`: the PWA's fixed high-latitude rule.
- `locations`: 30 locations. Coordinates are rounded to 2 decimals, as §7.4 requires.
- `dates`: 12 dates in 2026. They are the solstices, the equinoxes, and the US, EU and AU/NZ DST
  transition days.

`vectors` has one line per location × date × method (5) × Asr school (2), 3600 in total:

```json
{"location":"mecca","latitude":21.42,"longitude":39.83,"timeZone":"Asia/Riyadh","date":"2026-01-15",
 "method":"mwl","fajrAngle":18,"asrSchool":"standard","asrShadowFactor":1,
 "expected":{"computed":true,"fajr":"…Z","sunrise":"…Z","asr":"…Z","sunset":"…Z","fajrRule":"angle"}}
```

- **`fajr`** and **`asr`** come from `prayerTimesForDate`.
- **`sunrise`** and **`sunset`** come from `solarDay` for the same date, since `prayerTimesForDate` does not
  return them.
- **`fajrRule`** is `"angle"`, or `"night-fraction"` when the PWA's clamp moved Fajr.
- **`computed: false`** means `prayerTimesForDate` returned `null`, which happens for Tromsø at both
  solstices. In that case `fajr` and `asr` are `null`.

Expected P1 divergences from `adhan-swift`, to be written up in `spec/prayer-times/README.md` during Slice 3:

- Adhan rounds to the nearest minute by default.
- Above 48° Adhan defaults to `.seventhOfTheNight`. `.twilightAngle` uses the PWA's portion, but Adhan
  measures the night from tonight's sunset to tomorrow's sunrise, not from last night's.

## Backup envelope

`backup/envelope-v1.md` specifies the `.athkarbackup` file both PWAs export (NATIVE_APP_PLAN.md §6.4); `backup/examples/` holds real exports. Validate any export with `node tools/backup-validate.mjs <file>`.
