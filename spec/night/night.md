# The Friday window and the last third of the night

Both apps show the «الصلاة على النبي ﷺ» page from the salawat pack (`content/salawat.v1.json`). From Thursday's
Maghrib to Friday's they name the time: «ليلة الجمعة» or «يوم الجمعة». Both also show when the last third of the
night begins. The PWA functions are `fridayPhase` and `tonightLastThird` in `index.html`, and
`fixtures/night.json` records them. The fixtures pass each case its Maghrib and Fajr, so a port tests these rules on
the same times, whatever its own calculation gives.

## Times

Each local date has a Maghrib and a Fajr. Either may be missing: the place has no location yet, or the sun does not
reach the angle that day. The PWA takes Maghrib from `solarDay`'s sunset and Fajr from `prayerTimesForDate`, with
its clamp (`nightTimesForDate`). The iOS app takes both from that date's `PrayerSchedule`.

## Friday window

The weekday is the weekday of `now`'s local date.

- **Thursday**: «ليلة الجمعة» (`night`) from Thursday's Maghrib on. Before it, or without a Maghrib, nothing.
- **Friday**:
  - From Friday's Maghrib on: nothing, since Saturday's night has begun.
  - Before Friday's Fajr: `night`.
  - Otherwise: «يوم الجمعة» (`day`).
  - Without a Fajr, all of Friday before Maghrib is `day`. Without a Maghrib, `day` lasts until midnight.
- **Any other day**: nothing.

Friday's night never starts without Thursday's Maghrib, so a place without a location only ever shows `day`, from
Friday's midnight to the next.

## Last third of the night

A night runs from one day's Maghrib to the next day's Fajr. It has no last third when either time is missing, or
when Fajr is not after Maghrib. Otherwise the last third starts at
`Maghrib + round((Fajr − Maghrib) × 2 / 3)` in whole milliseconds, rounding half up, and ends at Fajr.

The night shown at `now` is the one `now` is in, or the next one:

- before today's Fajr, the night from yesterday's Maghrib to today's Fajr;
- otherwise, including when today has no Fajr, the night from today's Maghrib to tomorrow's Fajr.

Today, yesterday and tomorrow are calendar days of `now`'s local date, not 24-hour steps, so a DST change names
the right days.

The iOS prayer-times screen shows the night that follows the shown day's Maghrib. Today shows the night above,
marked «الآن» while `now` is inside its last third.
