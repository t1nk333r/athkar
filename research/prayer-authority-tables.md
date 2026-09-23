# Prayer-time authority tables for candidate launch regions

Research note for `t1nk333r/athkar#9` (`wayfinder:research`). Findings only: no launch region is chosen and no default calculation method is recommended here — that is the dependent decision tracked as item 6 of `NATIVE_APP_PLAN.md` §11.

Everything below was read on **2026-09-23**. HTTP outcomes are recorded, so a later reader can distinguish "authority does not publish this" from "the fetch was blocked". Claims that are inference rather than something I read are marked `[INFERENCE]`.

---

## 1. What these tables are for

`NATIVE_APP_PLAN.md` §7.2 defines the correctness gate this research feeds:

| Check | Reference | Tolerance | Fails the gate if |
| --- | --- | --- | --- |
| **P2 Authority tables** | Published tables for representative launch regions (decision 11.6) for **all six times** | 2 minutes, 3 for Fajr/Isha | Any systematic offset. |

Adjacent constraints that shape what a fixture can be:

- P1 compares the native engine against the PWA oracle for **Fajr/sunrise/Asr/sunset only** — `prayerTimesForDate` (`index.html:3409`) and `solarDay` compute exactly four values; there is no Dhuhr, Maghrib or Isha in the PWA. So **P2 must be evaluated against the native Adhan port, not against the PWA**.
- §10 already lists "Adhan preset mismatch with PWA angles" as a risk, mitigated by "P1 parity gate with written exceptions".
- §1.1 carries an `[INFERENCE]` that the Swift and Kotlin editions expose the same presets as Adhan JS, to be verified on the pinned versions during Slice 0. Section 3 below resolves that for every preset that matters to the candidate regions.

## 2. The PWA baseline (what the app ships today)

`index.html:2243-2250`:

```js
const prayerCalculationMethods = Object.freeze({
  "mwl": { fajrAngle: 18 },
  "umm-al-qura": { fajrAngle: 18.5 },
  "egyptian": { fajrAngle: 19.5 },
  "karachi": { fajrAngle: 18 },
  "north-america": { fajrAngle: 15 }
});
const asrShadowFactors = Object.freeze({ standard: 1, hanafi: 2 });
```

Notable facts for the fixture work:

- The PWA stores only a **Fajr angle** per method. Isha is never computed; the `umm-al-qura` entry therefore silently lacks the 90-minute Isha interval that the authority uses.
- The `north-america` entry is the only non-`mwl` option that is a distinct angle family (15°); `mwl`, `karachi` and `umm-al-qura` are all 18–18.5° Fajr, so the PWA's five methods are really three distinct Fajr angles plus two Asr schools (1 / 2).
- The default for a fresh install is `mwl` (`index.html:3296-3300`, `fallback.calculationMethod`), which `NATIVE_APP_PLAN.md` §11 item 6 flags for review.
- The PWA's only high-latitude logic is `safeFajr` inside `prayerTimesForDate` (`index.html:3421-3429`), a `nightDuration × fajrAngle / 60` clamp. Adhan's high-latitude rules are a different (and larger) family; P1 allows a written exception for exactly this case.

## 3. The Adhan preset baseline, read from source

Read from the tagged/default branches on 2026-09-23: `adhan-js` **v4.4.6** (`develop` source), `adhan-swift` **1.5.0** (`main` source), `adhan-kotlin` **v1.2.1** (`main` source, package `com.batoulapps.adhan2`).

| Preset | Fajr angle | Isha | Other parameters in the preset |
| --- | --- | --- | --- |
| `MuslimWorldLeague` | 18° | 17° | `dhuhr +1` |
| `Egyptian` (Egyptian General Authority of Survey) | 19.5° | 17.5° | `dhuhr +1` |
| `Karachi` (Univ. of Islamic Sciences) | 18° | 18° | `dhuhr +1` |
| `UmmAlQura` | 18.5° | interval **90 min after Maghrib** | none |
| `Dubai` | 18.2° | 18.2° | `sunrise −3`, `dhuhr +3`, `asr +3`, `maghrib +3` |
| `MoonsightingCommittee` | 18° | 18° **plus seasonal functions** | `dhuhr +5`, `maghrib +3`, 1/7 rule at ≥55° lat, `shafaq` option |
| `NorthAmerica` (ISNA) | 15° | 15° | `dhuhr +1` |
| `Kuwait` | 18° | 17.5° | none |
| `Qatar` | 18° | interval **90 min after Maghrib** | none |
| `Turkey` (Diyanet) | 18° | 17° | `sunrise −7`, `dhuhr +5`, `asr +4`, `maghrib +7` |
| `Singapore` | 20° | 18° | `dhuhr +1`, `rounding = Up` |
| `Tehran` | 17.7° | 14° (Maghrib at 4.5°) | **adhan-swift/adhan-js only — absent from adhan-kotlin** |
| `Other` | 0° | 0° | — |

Findings that matter to the plan's pinned-version check (§1.1):

1. For every preset that touches the candidate regions (MWL, Egyptian, Karachi, UmmAlQura, Dubai, MoonsightingCommittee, NorthAmerica, Kuwait, Qatar, Turkey) the **three editions agree exactly**, including the method adjustment minutes. The `[INFERENCE]` in §1.1 can be closed for those presets.
2. The editions do **not** have identical method lists: `adhan-kotlin` implements 12 methods and has **no Tehran** method; `adhan-js`/`adhan-swift` implement 13.
3. The family has drifted on the preset that matters most for a Gulf launch before: **`adhan-kotlin` PR #44, "Fix typo in Fajr angle for Umm al-Qura"** (opened and merged 2022-09-28) changed the Kotlin Umm al-Qura Fajr angle from 18° to 18.5°, matching the Java/JS sources. Any golden vectors must name the exact edition/tag they were generated from.
4. **Licence: MIT** for all three editions (`adhan-js` LICENSE = MIT, Batoul Apps 2016; `adhan-swift` LICENSE is byte-identical to `adhan-kotlin` LICENSE — same blob hash `c80a859f7e70e35a17d5ec0bef409dda09c06962`). Values computed *by the library* are therefore redistributable with attribution; values copied *from an authority's published table* are a separate question (section 6).

## 4. Region → authority → parameters → machine-readability → reuse constraint

| Region | Publishing authority (where) | Parameters the authority itself states | Machine-readable? | Reuse constraint found |
| --- | --- | --- | --- | --- |
| **Saudi Arabia** | Umm al-Qura (تقويم أم القرى الرسمي), `https://www.ummulqura.org.sa/` — described on the site as a government site registered with the Saudi Digital Government Authority; prayer times at `/ar/prayer-times` and `/en/prayer-times` | Not published in any page reachable without JavaScript. The site is an Angular SPA (`<app-root>`, no server-rendered values). The 18.5° Fajr / 90-minute Isha pairing is stated by the Adhan libraries and by Moonsighting Committee Worldwide, not by the site itself | **No.** SPA only; no documented API, CSV or static JSON found. Legacy `index.aspx` did not resolve (TLS error). `api.data.gov.sa` (SDAIA national API marketplace) exists but no prayer-times API was located there | None found. No terms-of-use page located on the site |
| **Egypt** | Egyptian General Authority of Survey — `https://www.esa.gov.eg/praytimes.aspx`. The page states: "وتتحمل الإدارة العامة للجيودسيا والحساب بالهيئة المصرية العامة مسئولية حساب مواقيت الصلاة الخمس يومياً بالإضافة إلى صلاة العيدين وصلاة الضحى" (the General Directorate of Geodesy and Computation computes the five daily times, plus Eid and Duha) | Not published. The 19.5° Fajr / 17.5° Isha pairing exists only in the Adhan libraries and third-party compilations | **No.** ASP.NET WebForms: a city dropdown + `__VIEWSTATE` postback, plus a separate `monthlymwaket.aspx` monthly grid. Values are in the HTML, not an API/CSV/PDF | None found |
| **UAE — federal** | General Authority of Islamic Affairs & Endowments (Awqaf), `https://www.awqaf.gov.ae/prayer-times` (per-emirate, per-city/area) | Not published on the pages reachable | **No.** Page renders values client-side; the beta service host (`betaservices.awqaf.gov.ae/prayer-times`) answered "Request Rejected" to automated access | None found |
| **UAE — Dubai** | Islamic Affairs & Charitable Activities Department (IACAD), `https://www.iacad.gov.ae/en/prayer-times` and `https://eservices.iacad.gov.ae/prayer-time` | Not published | **No.** Both returned HTTP 403 to automated fetch on 2026-09-23 | None found |
| **Qatar** | Ministry of Awqaf and Islamic Affairs, `https://www.islam.gov.qa/` (header states "مواقيت الصلاة بدعم من دار التقويم القطري" — supported by the Qatar Calendar House, `https://www.qatarch.com/cal`). Separately, Ministry of Interior REST service `https://portal.moi.gov.qa/MoiPortalRestServices/rest/prayertimings/today/{ar\|en}` | Not published. Behaviourally, Isha is **90 minutes after Maghrib** in both official channels (2026-09-23 Doha: Maghrib 17:30 → Isha 19:00 on the MOI service; 17:32 → 19:02 on islam.gov.qa). The Qatar preset's 18° Fajr is library-side only | **Partly — the only official machine-readable endpoint found in this whole survey.** The MOI URL returns a small structured block (country, city, lat/long, qibla, and the six times) as HTML, not JSON; no documented contract, versioning or licence | None found |
| **Kuwait** | Ministry of Awqaf and Islamic Affairs, `https://www.awqaf.gov.kw/` — the attributed authority on third-party sites ("المواقيت المعتمدة من وزارة الأوقاف والشؤون الإسلامية") | Not published | **No.** No prayer-times page found on the ministry site (Arabic homepage read 2026-09-23: news/services only) | None found |
| **Bahrain** | Parallel institutions: Supreme Council for Islamic Affairs `https://www.almajles.gov.bh/` (site shows Manama times; HTTP **403** to automated fetch on 2026-09-23); Sunni Endowments `https://www.sunniwaqf.com/`; Jaffari Endowments `https://jwd.bh/` | Not published | **No.** HTML only | None found |
| **Oman** | Ministry of Awqaf and Religious Affairs, `https://www.mara.gov.om/` — daily times for Muscat on the landing page, regional tables at `/arabic/calendar_page4.asp`, GIS service `https://gis.mara.gov.om/` | Not published | **No.** HTML tables; all fetch attempts from this environment failed on TLS (`unable to verify the first certificate` / socket closed) | None found |
| **Turkey** | Diyanet İşleri Başkanlığı, `https://namazvakitleri.diyanet.gov.tr/` (per-city daily/weekly/monthly/yearly tables); calculation site `https://vakithesaplama.diyanet.gov.tr/` | Partially, and indirectly: the daily page prints **temkin-adjusted** values next to the astronomical ones. Ankara 2026-09-23: `Güneş 06:30` vs `Astronomik Güneş Doğuş 06:37` (−7 min) and `Akşam 18:53` vs `Astronomik Güneş Batış 18:46` (+7 min). The equivalent temkin for İmsak/Yatsı is not exposed | **No official API found.** `vakithesaplama.diyanet.gov.tr` returned HTTP 403 to automated fetch. An unofficial JSON mirror exists (`https://ezanvakti.emushaf.net/vakitler/{id}`, verified 2026-09-23 — it even carries `GunesDogus`/`GunesBatis` beside `Gunes`/`Aksam`). Using it in a fixture means redistributing Diyanet's values obtained through an unaffiliated third party | None found; Diyanet pages carry no reuse grant |
| **North America — ISNA** | Islamic Society of North America, `https://isna.net/prayer-times/` | 15°/15° is attributed to ISNA by third parties; ISNA's own page is a JavaScript shell with no times, angles or method text retrievable. Moonsighting Committee Worldwide states "Since 2018 onwards, ISNA recommends using 15° for ease of calculations"; the Fiqh Council of North America article (below) tabulates ISNA as 15°/15° | **No.** No ISNA-published table was found at all — ISNA supplies a *method*, not tables | None found |
| **North America — Moonsighting Committee Worldwide (MCW)** | Khalid Shaukat / Moonsighting Committee Worldwide, `https://www.moonsighting.com/` — per-city schedules plus a full method statement at `how-we.html` ("Updated March 1, 2024") | Yes, in prose and formulae: Fajr = Subh Sadiq; Zuhr = astronomical noon **+5 min**; Maghrib = theoretical sunset **+3 min** for Sunnis (+17 for Shi'a); Asr factors 1 (Shafi'i/Maliki/Hanbali/Ja'fari variants) and 2 (Hanafi); Fajr/Isha computed from **latitude-and-season functions, not a fixed degree**, compared against 18° (Fajr: the later of the two; Isha: the earlier); **1/7 rule applied between 55° and 60°**; above 60° the computation "slides down to 60°" (Aqrabul-Bilad) | **HTML tables per city**; no API or CSV found. MCW states its method is used by `PrayerTimeResearch/PrayerTimeAPI` and `islamic-network/prayer-times-moonsighting` | None found on the pages read; the schedules are presented as MCW's own published data |
| **North America — Fiqh Council of North America (FCNA)** | `https://fiqhcouncil.org/fifteen-or-eighteen-degrees-calculating-prayer-fasting-times-in-islam` (published 2024-09-18, modified 2026-08-13, author Shaykh Mustafa Umar) | Recommends **15° for Fajr and Isha** as the practical approximation, tabulates ISNA 15°/15°, Egyptian 19.5°/17.5°, MWL 18°/17°, Karachi 18°/18°, UOIF 12°/12°, Singapore 20°/18°, and reproduces MCW's observation range (Fajr 14.8–17.5°, Isha 11.2–17.6°) | FCNA publishes an article/position, not tables | Article is FCNA's own content; no reuse licence stated |

### 4.1 Published values captured while reading (usable as spot checks)

| Source | City | Date | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Qatar MOI REST | Doha (25:15, 51:36) | 2026-09-23 | 4:07 | 5:23 | 11:26 | 2:53 | 5:30 | 7:00 |
| Ministry of Awqaf (Qatar) site header | default Qatar city | 2026-09-23 | 04:05 | 05:23 | 11:26 | 02:52 | 05:32 | 07:02 |
| Egypt ESA page markup | القاهرة | 2026-09-23 | 5:17 ص | 6:44 ص | 12:47 م | 4:14 م | 6:51 م | 8:08 م |
| Diyanet | Ankara | 2026-09-23 | İmsak 05:06 | Güneş 06:30 (astron. 06:37) | Öğle 12:46 | İkindi 16:11 | Akşam 18:53 (astron. 18:46) | Yatsı 20:11 |

**Two Qatari government sources disagree on the same city and day** (Fajr 4:07 vs 4:05; Asr 2:53 vs 2:52; Maghrib 5:30 vs 5:32; Isha 7:00 vs 7:02). `[INFERENCE]` both rows are Doha — the MOI service says so explicitly ("City: Doha", lat 25:15 / lon 51:36) and the ministry header shows a single default location. With a P2 tolerance of 2 minutes (3 for Fajr/Isha), an authority-to-authority spread of up to 2 minutes leaves no headroom if the ported engine is compared against one of them and the other is treated as ground truth.

## 5. Documented systematic differences: authority practice vs the Adhan preset

### 5.1 Umm al-Qura (Saudi Arabia)

- The library documents a **Ramadan adjustment the preset does not perform**: "Umm al-Qura University, Makkah. Uses a fixed interval of 90 minutes from maghrib to calculate Isha. And a slightly earlier Fajr time with an angle of 18.5°. *Note: you should add a +30 minute custom adjustment for Isha during Ramadan.*" — identical wording in `adhan-js/METHODS.md` (develop), `adhan-swift/METHODS.md` (main) and the `UMM_AL_QURA` KDoc in `adhan-kotlin`'s `CalculationMethod.kt`. No edition implements a Hijri-aware switch; the caller must detect Ramadan and add 30 minutes.
- Moonsighting Committee Worldwide tabulates the Haramain rule set as: Fajr 18.5°, Shurooq **1 minute before** sunrise, Zuhr = zawaal, Asr Hanbali/Shafi'i, Maghrib **1 minute after** sunset, Isha 90 minutes after Maghrib. The Adhan `UmmAlQura` preset carries **no** sunrise/maghrib minute adjustments, so a fixture taken from a Haramain-issued timetable can be expected to differ by about 1 minute even before rounding. `[INFERENCE]` this one-minute offset is the most likely first finding of the P2 run for a Saudi fixture; it has not been measured here.
- No Adhan issue titled around Umm al-Qura was found open in the JS repo; the only Umm-al-Qura defect in the family's history that I could verify is the Kotlin angle typo fixed by PR #44 (section 3).

### 5.2 Turkey (Diyanet)

- The preset is **self-described as an approximation**: "An approximation of the Diyanet method used in Turkey. This approximation is less accurate outside the region of Turkey." (all three editions; Kotlin's KDoc is terser: "Diyanet İşleri Başkanlığı, Turkey. Uses a Fajr angle of 18 and an Isha angle of 17").
- The preset's `sunrise −7` and `maghrib +7` match, minute for minute, the temkin offsets visible on Diyanet's own page (section 4.1). The `dhuhr +5` / `asr +4` offsets are library-side; Diyanet's page does not print an astronomical transit or ikindi for comparison.
- Diyanet's İmsak and Yatsı are printed as adjusted times, but the astronomical reference for them is not shown, so whether the preset's 0-minute offsets for Fajr/Isha reproduce Diyanet is **not verifiable from the site** — it is a measurement the parity run has to make.
- A frequently-copied third-party offset table for Diyanet (seen in `pebble-qibla-www/praytimes.py`, `cpfair`) gives Fajr −2, Sunrise −6, Dhuhr +7, Asr +4, Maghrib +7, Isha +1 — i.e. **it disagrees with the Adhan preset on Fajr, Sunrise and Dhuhr**. `[INFERENCE]` at least one of the two is stale; the values should not be treated as interchangeable.

### 5.3 North America

- **MCW**: the library implements the same *family* of rules — for `moonsightingCommittee`, Fajr = later of (18° angle, seasonal function), Isha = earlier of (18° angle, seasonal function), `dhuhr +5`, `maghrib +3`, and a night/7 substitution at latitude ≥ 55° (verified in `adhan-swift/Sources/PrayerTimes.swift` and the equivalent JS). MCW's own text adds rules the library does **not** have: at latitudes above 60° MCW "slides down to 60 degrees" (Aqrabul-Bilad) and uses the 1/7 rule in summer; Adhan applies nightly/7 at ≥55° without the 60° clamp. `[INFERENCE]` divergence therefore starts somewhere above 55°N and grows with latitude; it is not measurable from the sources alone.
- **ISNA**: the `northAmerica` preset (15°/15°, `dhuhr +1`) matches the 15° that ISNA is reported to recommend, so no *angle* discrepancy is expected. The gap is different in kind: ISNA publishes no tables, so a North-American P2 check can only reference a *method statement* (ISNA's recommendation as reported by MCW/FCNA, or FCNA's own article), never "the authority's published table" as the gate's wording assumes.

### 5.4 Egypt, Kuwait, Qatar, Bahrain, Oman, UAE

- For all of these, the presets exist in the library (`egyptian`, `kuwait`, `qatar`, `dubai`) but **no authority-side parameter statement was found to compare against**. Only Qatar's Isha interval could be corroborated behaviourally (90 minutes, from two official Qatari channels). Bahrain and Oman have **no Adhan preset at all**; an Oman fixture would need a custom `CalculationParameters` or manual adjustments, and the library has an open example of exactly that class of request stalling (adhan-js #176, "Add Jordan calculation method with adjustments", opened 2025-09-16, closed unmerged 2026-02-08).

### 5.5 Library-side defects documented in the family's issues (affect the gate's P3/P4 rows as well)

| Issue | State (read 2026-09-23) | What it documents |
| --- | --- | --- |
| `batoulapps/adhan-js#221` — "stricter validation of afternoon solar times inside the polar circle" | **Open** PR, created 2026-09-11 | `PrayerTimes` can return times violating `fajr < sunrise < dhuhr < asr < maghrib < isha` near the polar circle; ports two guards from the Kotlin port (adhan-kotlin PR #94) and states that adhan-js deliberately keeps partial/NaN results while Kotlin throws — an explicit, deliberate **cross-edition semantic difference** |
| `batoulapps/adhan-kotlin#44` — "Fix typo in Fajr angle for Umm al-Qura" | Merged 2022-09-28 | Kotlin had Umm al-Qura Fajr at 18° instead of 18.5° |
| `batoulapps/adhan-js#176` — "Add Jordan calculation method with adjustments" | Closed unmerged 2026-02-08 | Requests to add national presets are not reliably accepted (link given: `awqaf.gov.jo` prayer times) |
| `batoulapps/adhan-js#12` — "Calculation Method for Morocco" | Closed 2020-05-13 | Users could not reproduce `habous.gov.ma` official times with the presets as they stood |
| `batoulapps/adhan-js#45` — "prayer times are not accurate" | Closed | Generic report after a 5-minute-scale mismatch |
| `batoulapps/adhan-js#146` — elevation | **Open**, 22 comments, created 2023-02-23 | Elevation above sea level is not modelled; the reporter measured sunrise 4–5 minutes earlier than the library at 450 m |

## 6. Licensing / reuse constraints on reproducing table values in a fixture

What I could establish, and what I could not:

- **No authority reviewed here publishes a licence permitting redistribution of its table values.** No terms-of-use, copyright or open-data licence page was located on `ummulqura.org.sa`, `esa.gov.eg`, `awqaf.gov.ae`, `iacad.gov.ae`, `islam.gov.qa`, `awqaf.gov.kw`, `almajles.gov.bh`, `mara.gov.om`, `namazvakitleri.diyanet.gov.tr` or `isna.net` on 2026-09-23. Absence of a stated licence is not a grant.
- **Saudi Arabia** has a national open-data portal (`open.data.gov.sa`) and an SDAIA-run API marketplace (`api.data.gov.sa`, "+420 واجهة برمجية"), but no prayer-times dataset or API was found there in the searches run for this ticket. If Saudi is a launch region, whether a licence exists for its table is a question for the human, not something derivable from the pages read.
- **Turkey**: the JSON that exists (`ezanvakti.emushaf.net`) is an **unaffiliated mirror** of Diyanet data; it carries no licence and no attribution requirement, and its terms are not Diyanet's. Building a fixture from it would embed the values of a government agency obtained from a third party.
- **Qatar**: the MOI REST endpoint is a government endpoint but publish-or-not is undocumented; treating it as a stable fixture source is `[INFERENCE]`-risky (per-day URLs, no versioning).
- **United States**: Moonsighting.com's schedules and its `how-we.html` statement are MCW's own published material; FCNA's article is FCNA's. Neither page stated reuse terms in what was read.
- **Library-derived values are clean**: all three Adhan editions are MIT, so vectors *computed* by a pinned edition can be committed with the usual notice. The MIT grant covers the code, not a publisher's table.

`[INFERENCE]` Practical consequence for the fixture (stated as a constraint, not a recommendation): a fixture built **from authority-stated parameters** carries no redistribution question, while a fixture built **from an authority's published rows** reproduces third-party data whose licence is unstated — which is why the per-region 'reuse constraint' column above is the binding one for decision 11.6.

## 7. Open questions / retrievals that failed

| Item | Status on 2026-09-23 |
| --- | --- |
| Umm al-Qura site parameter page | Not reachable without JavaScript (Angular SPA). Legacy `https://www.ummulqura.org.sa/index.aspx` failed with a certificate verification error |
| Saudi `api.data.gov.sa` listing | Not enumerated (JavaScript store front); no prayer-times API located via search |
| Bahrain Supreme Council (`almajles.gov.bh`) | HTTP 403 |
| Oman (`mara.gov.om`, `/arabic/calendar_page4.asp`) | TLS: "unable to verify the first certificate" / socket closed on every attempt |
| Diyanet `vakithesaplama.diyanet.gov.tr` | HTTP 403 (the per-city pages on `namazvakitleri.diyanet.gov.tr` are reachable and were read) |
| IACAD (`iacad.gov.ae`) | HTTP 403 |
| ISNA method page | JavaScript shell; no method text or times retrievable |
| Egypt ESA parameter statement | Not published anywhere reachable — the 19.5°/17.5° pairing is library/third-party only |
| Kuwait official prayer-times page | Not found on `awqaf.gov.kw` |

## 8. Sources (all read 2026-09-23)

Primary / authority

- Umm al-Qura (تقويم أم القرى الرسمي) — https://www.ummulqura.org.sa/ar/prayer-times and https://www.ummulqura.org.sa/en/prayer-times (SPA shell; `:raw` HTML read)
- Egyptian General Authority of Survey — https://www.esa.gov.eg/praytimes.aspx
- Qatar Ministry of Interior REST — https://portal.moi.gov.qa/MoiPortalRestServices/rest/prayertimings/today/en
- Qatar Ministry of Awqaf and Islamic Affairs — https://www.islam.gov.qa/ ; Qatar Calendar House — https://www.qatarch.com/cal
- Kuwait Ministry of Awqaf and Islamic Affairs — https://www.awqaf.gov.kw/ar
- UAE Awqaf — https://www.awqaf.gov.ae/prayer-times ; IACAD — https://www.iacad.gov.ae/en/prayer-times
- Bahrain: https://www.almajles.gov.bh/ (403), https://www.sunniwaqf.com/, https://jwd.bh/
- Oman Ministry of Awqaf and Religious Affairs — https://www.mara.gov.om/
- Diyanet İşleri Başkanlığı — https://namazvakitleri.diyanet.gov.tr/tr-TR (city pages, e.g. …/9541/istanbul-namaz-vakitleri, …/9206/ankara-namaz-vakitleri)
- Fiqh Council of North America — https://fiqhcouncil.org/fifteen-or-eighteen-degrees-calculating-prayer-fasting-times-in-islam/
- Moonsighting Committee Worldwide — https://www.moonsighting.com/how-we.html and https://www.moonsighting.com/faq_pt.html
- ISNA — https://isna.net/prayer-times/ (shell only)
- Unofficial Diyanet JSON mirror — https://ezanvakti.emushaf.net/vakitler/9541

Library (batoulapps)

- https://raw.githubusercontent.com/batoulapps/adhan-js/develop/src/CalculationMethod.ts
- https://raw.githubusercontent.com/batoulapps/adhan-js/develop/METHODS.md
- https://raw.githubusercontent.com/batoulapps/adhan-js/develop/LICENSE
- https://raw.githubusercontent.com/batoulapps/adhan-swift/main/Sources/Models/CalculationMethod.swift
- https://raw.githubusercontent.com/batoulapps/adhan-swift/main/Sources/PrayerTimes.swift
- https://raw.githubusercontent.com/batoulapps/adhan-swift/main/Sources/Astronomy/Astronomical.swift
- https://raw.githubusercontent.com/batoulapps/adhan-swift/main/METHODS.md
- https://raw.githubusercontent.com/batoulapps/adhan-kotlin/main/adhan/src/commonMain/kotlin/com/batoulapps/adhan2/CalculationMethod.kt
- Tags read: `adhan-js` v4.4.6, `adhan-swift` 1.5.0, `adhan-kotlin` v1.2.1 (GitHub tags API)
- Issues/PRs: adhan-js #221, #176, #146, #45, #12; adhan-kotlin #44

Repository (read-only, for the baseline)

- `index.html`: `prayerCalculationMethods`, `asrShadowFactors` (2243-2250), settings select (1821-1826), `prayerTimesForDate` (3409-3440 incl. `safeFajr`)
- `NATIVE_APP_PLAN.md`: §1.1, §4.3, §7.2, §10, §11 item 6
