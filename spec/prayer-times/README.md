# Prayer times

The native apps compute prayer times with Batoul Apps' Adhan library behind one port (NATIVE_APP_PLAN.md §7.1).
This file records how the iOS adapter is configured, what the parity gate (§7.2) found, and why each difference
outside tolerance is acceptable. `vectors.json` is the PWA oracle (see [`../README.md`](../README.md)).

## Library

| | |
| --- | --- |
| Package | `https://github.com/batoulapps/adhan-swift.git`, MIT |
| Pin | `exact: "1.5.0"` in `ios/AthkarCore/Package.swift` |
| Resolved revision | `a6fa2deee80c5abb0b9ad04466f8ab12b53144e7` (`ios/AthkarCore/Package.resolved`; the 1.5.0 tag is lightweight and points at this commit) |

Only `ios/AthkarCore/Sources/AthkarCore/PrayerTimes/AdhanPrayerTimes.swift` imports Adhan. Everything else uses
`PrayerTimesPort`:

```swift
func schedule(on localDate: String, at coordinates: GeoCoordinates, in zone: TimeZone,
              settings: CalculationSettings) throws(PrayerTimesError) -> PrayerSchedule
```

`PrayerSchedule` holds `localDate`, `zone` and six optional UTC instants: `fajr`, `sunrise`, `dhuhr`, `asr`,
`maghrib`, `isha`. `CalculationSettings` is `method`, `asrSchool`, `highLatitudeRule`, `adjustments` (whole
minutes per time) and `hijriOffset` (days, display only). Each field is its own `settings` key; see
[`../schema.md`](../schema.md).

## Adapter configuration

| Setting | Choice | Why |
| --- | --- | --- |
| Method | The setting's preset (table below) | The PWA's five Fajr angles equal Adhan's presets: 18, 18.5, 19.5, 18, 15. |
| Asr | `standard` → `.shafi` (shadow factor 1), `hanafi` → `.hanafi` (2) | Same factors as the PWA's `asrShadowFactors`. |
| High-latitude rule | Always passed explicitly. Default `.twilightAngle` | See the next section. Adhan's own default (`recommended(for:)`) is never used. |
| Rounding | `.none`: the instant, truncated to the whole second | Adhan's default `.nearest` is a library default, not part of any method, and adds up to 30 s. The PWA did not round. Display rounding is the view's decision (Slice 5). A preset that asks for `.up` keeps it (Singapore). |
| Adjustments | User minutes go to Adhan's `adjustments`. The presets' own `methodAdjustments` stay | See the table below. |
| Date | The UTC date whose solar transit falls on `localDate` in `zone` | Adhan computes the solar day around the transit of a UTC date. Where a zone's offset is about a day from its longitude, that transit is on the next civil day. That happens in zones east of 180° that use UTC+12 or more: Kiritimati (UTC+14 at 157° W), Apia (UTC+13 at 172° W), and likewise Tonga, Tokelau, Kanton and Chatham. Those zones need the previous UTC date. P3 covers Kiritimati and Apia, and Pago Pago (UTC−11) as the case that needs no shift. |
| No result | All six times `nil` | Adhan returns everything or nothing. It returns nothing when the Sun does not rise or set that day. |

For the PWA's five methods, Maghrib is sunset. None of them has a Maghrib angle or a Maghrib offset, so P1
compares `maghrib` with the PWA's `sunset` directly.

### Parameters per method

The PWA never computed Isha. These values come from Adhan 1.5.0 `CalculationMethod.params`. Offsets are minutes
Adhan adds on top of the computed time.

| Setting value | Adhan preset | Fajr | Isha | Maghrib | Preset offsets | Rounding |
| --- | --- | --- | --- | --- | --- | --- |
| `mwl` | `muslimWorldLeague` | 18° | 17° | sunset | Dhuhr +1 | none |
| `umm-al-qura` | `ummAlQura` | 18.5° | Maghrib + 90 min (Adhan does not add Ramadan's +30; use the Isha adjustment) | sunset | none | none |
| `egyptian` | `egyptian` | 19.5° | 17.5° | sunset | Dhuhr +1 | none |
| `karachi` | `karachi` | 18° | 18° | sunset | Dhuhr +1 | none |
| `north-america` | `northAmerica` | 15° | 15° | sunset | Dhuhr +1 | none |
| `dubai` | `dubai` | 18.2° | 18.2° | sunset + 3 | sunrise −3, Dhuhr +3, Asr +3, Maghrib +3 | none |
| `moonsighting-committee` | `moonsightingCommittee` | 18°, seasonal | 18°, seasonal (`shafaq` general) | sunset + 3 | Dhuhr +5, Maghrib +3 | none |
| `kuwait` | `kuwait` | 18° | 17.5° | sunset | none | none |
| `qatar` | `qatar` | 18° | Maghrib + 90 min | sunset | none | none |
| `singapore` | `singapore` | 20° | 18° | sunset | Dhuhr +1 | up |
| `tehran` | `tehran` | 17.7° | 14° | 4.5° below the horizon | none | none |
| `turkey` | `turkey` | 18° | 17° | sunset + 7 | sunrise −7, Dhuhr +5, Asr +4, Maghrib +7 | none |

The high-latitude rule bounds Isha too: it is never later than sunset + portion × night. Interval methods
(`umm-al-qura`, `qatar`) are not bounded. `moonsighting-committee` ignores the rule and uses its own seasonal
twilight, and above 55° it uses 1/7 of the night.

## Default high-latitude rule: twilight angle

The PWA has one fixed rule: Fajr = max(angle Fajr, sunrise − night × fajrAngle/60). It applies at every latitude.
Adhan's `.twilightAngle` uses the same portion. The difference is the night: the PWA measures it from the previous
day's sunset to today's sunrise, and Adhan from today's sunset to tomorrow's sunrise.

Measured over all 3600 vectors. Only Fajr depends on the rule. "Recommended" is Adhan's own default: `.seventhOfTheNight`
above 48°, `.middleOfTheNight` otherwise.

| Rule | Fajr outside 120 s (of 3580) | Night-fraction vectors outside (of 172) | Max \|Δ\| on those | Angle vectors outside (of 3408) | Max \|Δ\| on those |
| --- | --- | --- | --- | --- | --- |
| `.twilightAngle` | **134** | **102** | **318 s** | **32** | **161 s** |
| `.middleOfTheNight` | 204 | 170 | 8180 s | 34 | 3332 s |
| `.seventhOfTheNight` | 984 | 172 | 7859 s | 812 | 7860 s |
| recommended | 752 | 172 | 7859 s | 580 | 7860 s |

`.twilightAngle` is the default:

- It is the PWA's rule, so existing reminder users see no rule change. Its differences are bounded by minutes;
  every other rule's are bounded by hours.
- The seventh and recommended rules also move Fajr on "angle" days. Sunrise − night/7 is later than the angle
  Fajr on many ordinary summer days (the seventh rule does this below 48° too), so those rules move Fajr later by up
  to 2 h 11 min.
- Adhan's `recommended(for:)` compares the signed latitude with 48. It never chooses a high-latitude rule in the
  southern hemisphere. The port always passes the rule, so 53° S gets the same treatment as 53° N (P3).

Users can choose `.middleOfTheNight` or `.seventhOfTheNight` in settings (§7.3).

## P1: legacy parity

`ios/AthkarCore/Tests/AthkarCoreTests/PrayerTimes/PrayerTimesParityTests.swift` runs every vector through
`AdhanPrayerTimes` with the vector's method and Asr school and the default settings. The tolerance is 120 s,
taken from the file. A time outside tolerance passes only if a named class explains it and the difference is
within that class's bound. Otherwise the failure names the vector, the field, both instants and the difference.

The test can fail. With MWL's Fajr angle temporarily changed to 18.5°, 558 MWL Fajr vectors failed, for example
`mecca 2026-01-15 mwl standard fajr: Adhan 2026-01-15T02:40:35.000Z, PWA 2026-01-15T02:42:51.007Z, Δ -136 s:
outside tolerance and no explanation class applies`. Some high-latitude ones were caught by a class bound instead:
`… Δ -227 s: beyond the high-latitude-solar-position bound of 180 s` (Stockholm 2026-01-15). Without the dateline
date shift, P3 failed for Kiritimati and Apia.

### Results

3600 vectors. For 20 of them (Tromsø at both solstices) neither side computes times: the PWA returned `null`, and
the test asserts that Adhan returns six `nil`s. That leaves 3580 vectors × 4 times.

| Time | Within 120 s | Max \|Δ\| within | Max \|Δ\| below 59° |
| --- | --- | --- | --- |
| Fajr | 3446 | 118 s | 102 s (Berlin 2026-08-15, Egyptian) |
| Sunrise | 3570 | 114 s | 39 s |
| Asr | 3395 | 118 s | 78 s (Toronto 2026-10-04) |
| Sunset (Maghrib) | 3560 | 76 s | 39 s |

Every vector below 59° is within tolerance. All 349 times outside tolerance are at Stockholm (59.33°), Oslo,
Anchorage, Reykjavík or Tromsø.

| Class | Times | Count | Max \|Δ\| | Bound | Where |
| --- | --- | --- | --- | --- | --- |
| `clamp-night-span` | Fajr | 102 | 318 s | 6 min | Night-fraction days at Anchorage, Oslo, Reykjavík, Stockholm, Tromsø (worst: Tromsø 2026-08-15, Egyptian) |
| `high-latitude-solar-position` | Fajr (angle), sunset | 42 (32 Fajr, 10 sunset) | 161 s | 3 min | Fajr near the equinoxes at Anchorage, Oslo, Reykjavík, Stockholm, Tromsø; Tromsø sunset 2026-08-15 (−124 s) |
| `high-latitude-asr` | Asr | 175 | 375 s | 7 min | Anchorage 60, Tromsø 60, Reykjavík 45, Oslo 10 (worst: Tromsø 2026-11-01, standard) |
| `grazing-sun` | sunrise, sunset, Asr | 30 (10 each) | 1855 s | 32 min | Tromsø 2026-01-15 only: sunrise −410 s, sunset +486 s, Asr +1855 s (standard) / +1339 s (hanafi) |

### Classes

Each class is a condition in the test, not a list of vectors. The mechanisms were confirmed offline: the PWA's
`solarTerms`/`solarDay` were re-run in Node with the model changes listed below and compared with this adapter's
output. That script is not kept.

- **`clamp-night-span`**, Fajr. The PWA's clamp measures the night from the previous day's sunset.
  `.twilightAngle` measures it from today's sunset to tomorrow's sunrise. At 59–70° in spring and August the
  night length changes by minutes a day (about a quarter of an hour at Tromsø), and the clamp moves by
  fajrAngle/60 of that. *Test condition:* the PWA's rule applied to Adhan's own astronomy lands within tolerance.
  That rule is max(angle Fajr, sunrise − (sunrise − previous day's sunset) × fajrAngle/60). The angle Fajr is
  read with `.middleOfTheNight`, whose clamp is always earlier than the PWA's. The same reconstruction brings all
  3580 vectors within tolerance except the 32 in the next class.
- **`high-latitude-solar-position`**, Fajr, sunrise, sunset at \|latitude\| ≥ 59°. The PWA evaluates every event
  with the Sun's declination and equation of time at local solar noon, in one pass. Adhan (Meeus) interpolates
  the Sun's position to the event itself. Near the equinoxes that is a 0.1–0.2° difference in declination, and
  where the Sun crosses the event altitude at a shallow angle it moves the event by minutes. *Offline check:* the
  PWA formulas with the Sun's position taken at the event time agree with Adhan's angle Fajr to ≤ 8 s and with
  sunrise and sunset to ≤ 4 s, at every latitude except on the grazing-sun day.
- **`high-latitude-asr`**, Asr at \|latitude\| ≥ 59°. Same as above, plus Adhan takes the Asr shadow angle from
  the declination at 0h UTC of the date, while the PWA takes it at local solar noon. Asr therefore comes later
  while the declination rises (January to June) and earlier while it falls. The data shows this sign pattern.
  *Offline check:* with both changes, Asr agrees to ≤ 18 s below 59° and ≤ 29 s above, except on the grazing-sun
  day.
- **`grazing-sun`**, sunrise, sunset and Asr when the PWA's day is shorter than 2 h. On Tromsø 2026-01-15 the
  noon Sun is about 0.8° below the geometric horizon, just above the −0.833° sunrise altitude. The PWA's day is
  49 min and Adhan's is 64 min. The Asr shadow altitude is itself below the horizon there. These times are
  ill-conditioned: even the event-time model leaves 431 s, 464 s and 877 s, because Adhan applies a single Meeus
  correction step. See P3 for the ordering consequence.

## P2: authority tables (pending)

Blocked on open decision §11.6 (launch regions and their published tables). No reference tables have been chosen
or invented. When §11.6 is decided, add each region's table here with its source and edition, compare all six
times (2 min; 3 min for Fajr and Isha), and look for systematic offsets. Published tables are usually rounded to
the minute, and the port returns seconds, so compare after the table's own rounding.

## P3: edge cases

`PrayerTimesEdgeCaseTests.swift`. The gate fails on a nil result, a negative night, or Fajr after sunrise. All
cases pass. Documented behaviour is marked.

| Case | Place, dates | Asserted |
| --- | --- | --- |
| Equator | Pontianak (0.03° S), 2026-03-20, 06-21, 12-21 | Six times, strictly ordered, all on the local date; daylight 12 h 00–15 min (observed 12 h 6–7 min) |
| Equator, equinox | Pontianak 2026-03-20 | Asr is 3 h ± 5 min after Dhuhr (Sun overhead, so Asr is at 45° altitude; observed 2 h 59 min 21 s including MWL's Dhuhr +1) |
| ≥ 60° N, June solstice | Helsinki 60.17°, Reykjavík 64.15°, Fairbanks 64.84°, Luleå 65.58°; 06-20..06-22; all three rules | Six ordered times; Fajr through Asr on the local date; Isha before the next day's Fajr. *Documented:* Maghrib and Isha can fall after local midnight (Reykjavík sunset 00:04, Isha 00:52; Luleå sunset 00:06). *Documented:* with `.middleOfTheNight`, Isha and the next Fajr both sit at the middle of the night, each measured from its own night, so Isha can be up to 14 s after the next Fajr (asserted ≤ 60 s). Twilight-angle and seventh keep a real gap. |
| Polar day and night | Tromsø (69.65° N) 2026-06-21, 12-21 | *Documented:* all six `nil`, as the PWA's `computed: false` |
| Polar-night edge | Tromsø 2026-01-15 | *Documented:* Asr (12:31:44 local) is after Maghrib (12:26:13). The Asr shadow altitude is below the horizon on the first day the Sun rises (see `grazing-sun`). Fajr < sunrise < Dhuhr < Maghrib < Isha still holds. Slices 5 and 6 must not assume Asr < Maghrib. Adhan has no times for 2026-01-14 there: polar night by its model. |
| Southern hemisphere | Sydney (33.87° S), Johannesburg (26.2° S); 06-21, 12-21 | Six ordered times on the local date |
| Southern high latitude | Punta Arenas (53.16° S) 2026-12-21 | Ordered; Fajr = sunrise − 18/60 × (next sunrise − sunset) ± 2 s: the default rule applies south of −48°, which Adhan's own default would not do; Isha (00:10) is before the next Fajr |
| DST, both directions | New York 03-08 (forward) and 11-01 (back); Sydney 04-05 (back) and 10-04 (forward); London 03-29, 10-25 | On the transition day and each neighbour: six ordered times, all on their local date; each time 24 h ± 5 min after the previous day's (UTC continuous); Dhuhr's wall clock moves by exactly the offset change ± 5 min |
| Dateline | Kiritimati (UTC+14, 157° W), Apia (UTC+13, 172° W), Pago Pago (UTC−11, 171° W); 2026-01-01, 06-21 | Six ordered times on the requested local date; Dhuhr between 11:30 and 13:30 local; the next day's Dhuhr 24 h ± 1 min later |
| Input | — | Non-calendar dates throw `invalidLocalDate`. Latitude outside ±90, longitude outside ±180, or NaN throws `invalidCoordinates` |

## P4: cross-platform (Android, later)

Android wraps `adhan-kotlin` behind the same port signature and runs this same `vectors.json` with the same four
classes, conditions and bounds. To make the platforms comparable, the Kotlin adapter must copy this configuration:

- the explicit rule with `twilightAngle` as the default;
- no rounding, except where a preset rounds up;
- the preset `methodAdjustments`;
- the UTC-date selection for zones about a day from their longitude;
- `maghrib` as sunset for the PWA's five methods;
- all-or-nothing `null`s.

The gate allows 0 s difference between platforms for the same Adhan algorithm version and 1 min across versions. A
change of the Swift pin re-runs P1 here first. If class counts or maxima move, this file is updated in the same
change.
