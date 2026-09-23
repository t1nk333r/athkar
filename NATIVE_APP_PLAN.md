# Athkar Native App Plan: Swift/SwiftUI First, Kotlin/Compose Later

## Status

This document is the stack and sequencing decision for consolidating three things into one native app:

1. The Athkar PWA (`index.html`, `sw.js`, GitHub Pages at https://t1nk333r.github.io/athkar/).
2. The رقية القرين PWA (`~/Projects/ruqyah-al-qareen/index.html` + `content.js`, https://t1nk333r.github.io/ruqyah-al-qareen/).
3. A new first-class prayer-times feature with per-prayer reminders and the tracker already designed in `MOBILE_APP_PLAN.md`.

It replaces the **stack decision only** of `MOBILE_APP_PLAN.md` (React Native + Expo, Flutter fallback). Section 2 maps every section of that document into *authoritative*, *superseded*, or *needs rewrite* so the two documents cannot contradict each other. Where this plan and `MOBILE_APP_PLAN.md` disagree, this plan wins.

It is a plan, not a status report. No native code exists. No Apple Developer account or organization identity exists yet. Work is not starting immediately.

Conventions: claims about current behaviour cite the file and symbol they were read from. Claims that could not be verified from the repositories are marked `[INFERENCE]`. Effort is expressed in relative bands (S/M/L/XL, defined in section 10), never in calendar dates.

---

## 1. Decision record: Swift-first native replaces React Native/Expo

### 1.1 The decision

| Item | Decision |
| --- | --- |
| Primary platform | iOS, Swift + SwiftUI, one Xcode project in the `athkar` repository under `ios/`. |
| Second platform | Android, Kotlin + Jetpack Compose, started only after the "iOS is stable" criteria in 1.4 are all met. |
| Shared UI layer | None. Two native UIs. |
| Shared non-UI layer | Data and specifications, not code: content packs, calculation golden vectors, notification-planner fixtures, SQL schema, backup envelope. See section 4. |
| Prayer-time engine | Batoul Apps Adhan library, native edition per platform (`adhan-swift` on iOS, `adhan-kotlin` on Android) behind a project-owned port, validated against golden vectors generated from the PWA's `solarDay`/`prayerTimesForDate` and against authority tables. `[INFERENCE]` that the Swift and Kotlin editions expose the same method presets as Adhan JS; this must be verified on the pinned versions during Slice 0. |
| PWAs | Kept live in maintenance mode through the native build; see section 10.4. |

### 1.2 Why React Native/Expo no longer fits

`MOBILE_APP_PLAN.md` §10 justified React Native with four arguments. Each has weakened:

| RN/Expo argument in `MOBILE_APP_PLAN.md` §10 | Current assessment |
| --- | --- |
| "Existing JavaScript domain rules and content can be migrated to typed shared packages." | The domain code that matters is small. `normalizeState`, `rollStateToDate`, `periodIsComplete`, `buildDeck`, `nextReminderTime`, `solarDay`, `prayerTimesForDate` in `index.html` total a few hundred lines. The rules are cheap to re-express in Swift and to pin with fixtures; the *content* is what must be shared, and content is data, not code. |
| "The PWA and native app can share content, backup schemas, search normalization, and pure scheduling rules." | Content, backup schema and fixtures are still shared (section 4), as JSON and test vectors. Sharing them does not require a JavaScript runtime in the app. |
| "Expo provides maintained iOS/Android notification and SQLite APIs while prebuild permits native widgets." | On iOS, `UNUserNotificationCenter`, `CoreLocation`, `BGTaskScheduler`, WidgetKit and SQLite are first-party and directly reachable from Swift. Expo adds an abstraction layer over exactly the APIs whose edge behaviour (pending-request budget, terminated-state delivery, time-zone change) this app depends on. |
| "It avoids maintaining two complete native UIs for a small team." | True and still a real cost (1.3). But the team is one person, Android is explicitly deferred, and the UI surface is small: card decks, a prayer-times list, a tracker, settings. The React Native tax (Metro, Hermes, native-module version churn, Expo SDK upgrades, Arabic text-shaping falsifier in `MOBILE_APP_PLAN.md` §10) is paid every day; the two-UI tax is paid only once Android starts. |

Additional reasons specific to this product:

- **Arabic typography is the product.** The card is a page of Quran or dhikr set in KFGQPC Uthman Taha Naskh (`fonts/kfgqpc-uthman-taha-naskh.ttf` in both repos) with auto-fit sizing so no card scrolls (`fitCardContent` in athkar, `fitCardText` in ruqyah). `MOBILE_APP_PLAN.md` §10 already listed RN text-shaping defects as an architecture falsifier. SwiftUI `Text` with Core Text shaping and Dynamic Type removes that risk on iOS entirely.
- **Notification correctness is the second product.** The PWA's own status copy admits the limitation: "يعمل المؤقت أثناء فتح التطبيق، ويعتمد العمل بعد إغلاقه على دعم النظام" (`updateReminderControls`). The whole reason to go native is scheduling that survives termination. That code should be written directly against `UNUserNotificationCenter` with no intermediary.
- **Solo maintainer paying per token.** Fewer moving parts per platform means fewer upgrade-driven regressions to diagnose with paid assistance. A SwiftUI project has one toolchain (Xcode) and one package manager (SwiftPM).

### 1.3 Costs accepted

| Cost | Consequence | Mitigation |
| --- | --- | --- |
| Two UI codebases eventually | Every screen is built twice. Any UI bug fixed on iOS must be independently checked on Android. | Android is deferred until iOS is stable; the design system, copy, and flows are frozen by then and become the spec Android implements. |
| No shared business-logic code | Domain rules (rollover, completion, deck ordering, planner) exist twice. | Rules are pinned by platform-neutral fixtures (section 4.3). Divergence is caught by tests, not by code sharing. |
| Domain expertise split | Swift and Kotlin both must be learned/maintained. | Sequential, not parallel. Android starts only when iOS demands little attention. |
| Android users wait longer | Android users stay on the PWAs for the whole iOS phase. | PWAs remain live and get bug/content fixes (section 10.4). |
| A Mac and Xcode are required | The current workstation is Linux (`uname` shows Arch Linux). iOS development cannot proceed without macOS hardware or a hosted Mac. | Hard prerequisite alongside the Apple Developer account; listed in section 11. |

### 1.4 "iOS is stable": criteria that unblock Android

Android work may begin only when **all** of the following hold. Each is observable without a calendar.

| # | Criterion | How it is observed |
| --- | --- | --- |
| S1 | Two consecutive public App Store releases have shipped with no P1 (data loss, duplicate/missed reminders, wrong Quran text, wrong prayer time beyond tolerance) reported or found. | Release notes and the private issue tracker. |
| S2 | Content pack `adhkar` and `ruqyah` (section 5) have been at the same major version across those two releases, i.e. no item ID, order, or text change was required. | `content/manifest.json` history. |
| S3 | The physical-device notification matrix (foreground, background, terminated, reboot, time-zone change, clock change, permission revoked) passes on the current release with zero duplicates. | Test log kept with the release. |
| S4 | At least one real PWA export from each PWA (athkar and ruqyah) has been imported on a real device by someone other than the maintainer with no semantic difference in a re-export. | Round-trip fixture plus a tester confirmation. |
| S5 | Crash-free sessions at or above 99.5% among users who share analytics with Apple, over the two releases in S1. | App Store Connect metrics. |
| S6 | The maintainer has closed the iOS backlog to "bug fixes and content only" for one full release cycle without a feature slice in flight. | Repository history. |
| S7 | The platform-neutral artefacts in section 4 (content packs, golden vectors, planner fixtures, schema doc, backup envelope) are complete and are what the iOS build actually consumes, not a parallel copy. | Build reads them from `content/` and `spec/`; CI validates them. |

If any criterion regresses after Android starts, Android work pauses until it is restored.

---

## 2. Mapping of `MOBILE_APP_PLAN.md`

Every section of the existing plan is classified. "Authoritative" means it stands as written and this document does not restate it. "Superseded" means this document replaces it. "Needs rewrite" means the content is still wanted but is written in Expo/RN terms and must be re-expressed; the rewrite target is named.

| `MOBILE_APP_PLAN.md` section | Status | Notes |
| --- | --- | --- |
| Status | Superseded | This document is the status. |
| 1. Product outcome | Needs rewrite | Definition of a complete release stands. Replace "on both platforms" with "on iOS; Android inherits when started". Add the ruqyah pillar (section 3 here). |
| 2. Product principles | Authoritative, one edit | Principle 9 ("shared … pure TypeScript rules") is superseded by section 4 here: shared *data and fixtures*, not TypeScript. |
| 3. Current PWA baseline | Needs rewrite | Item counts are stale: the repo now has 26 morning (`morning-01`…`morning-26`) and 24 evening (`evening-01`…`evening-24`) cards, including `comprehensiveDua` (البقرة ٢٠١) inserted before `salatUponProphet`. The long-order feature (`buildDeck`, `athkar-long-order-v1`), the scoped reset picker (`resetWeek`, `resetEverything`, `dayCountLabel`), and the ruqyah tab did not exist when §3 was written. Section 3 here is the replacement baseline. |
| 4. Scope and release boundaries | Superseded | Section 3.3 here redefines 1.0/1.1 for a solo iOS-first build. |
| 5. Information architecture | Needs rewrite | Add a رقية pillar; otherwise the Today / Prayer times / Tracker / Athkar / Calendar / Settings structure stands. Section 3.2 here. |
| 6. Prayer tracker domain (6.1–6.9) | **Authoritative** | Occurrence identity, recording states, Friday, travel, not-applicable, make-up, optional prayers, midnight rules. Not restated here. Only the *release* of travel/make-up/optional prayers moves (section 3.3). |
| 7. The eight README features | Needs rewrite | Contracts stand; release assignment changes (section 3.3). |
| 8. Prayer calculations, location, Hijri | Authoritative in intent, superseded in library | "Adhan JS" becomes the native Adhan editions; the correctness gate (30 locations × 12 dates, authority tables, edge cases) stands and is expanded in section 7. Location policy stands with one tightening (rounding, section 7.4). |
| 9. Native reminders | Needs rewrite | Planner requirements and replan triggers are authoritative. "via Expo Notifications" is removed. Android subsection is deferred but retained as the Android spec. Section 7.5 here. |
| 10. Recommended architecture | **Superseded** | Entire section (stack, falsifiers, repo shape, module seams) replaced by sections 1, 4, 8 here. |
| 11. Persistence and data model | Authoritative, extended | Table set stands; section 6 here adds ruqyah tables, long-order setting, and iOS storage engine choice. |
| 12. Content-pack system and governance | Authoritative, extended | Section 5 here adds the ruqyah pack, the two-source Quran check, and native shipping. |
| 13. Backup, migration, sync | Authoritative, extended | Section 6.4 here adds the ruqyah keys and removes "Web Crypto and React Native" from the encryption requirement. |
| 14. Widgets, quick actions, deep links | Authoritative | Widgets stay 1.1; "Expo configuration" references removed by implication. |
| 15. Privacy and security | **Authoritative** | Unchanged. |
| 16. Accessibility and localization | Authoritative | Unchanged; the Android-specific device tests apply when Android starts. |
| 17. Quality strategy | Authoritative | Fixture-first approach is the backbone of section 4.3. |
| 18. Nonfunctional targets | Authoritative | Android baseline-device targets apply when Android starts. |
| 19. Delivery phases and gates | **Superseded** | Section 8 here is the iOS slice plan; section 9 the Android plan. |
| 20. CI/CD and release operations | Split | The **iOS publisher-identity procedure (individual→organization migration, developer name, app transfer, Keychain/Team-ID cautions, identity gate)** is **authoritative and restated as a gate in section 8.1**. "Expo/EAS" references in the build-cutover subsection are superseded by Xcode Cloud or local `xcodebuild` (section 8.6). |
| 21. Major risks | Authoritative, extended | Section 10 here adds Swift-first and PWA-lifecycle risks. |
| 22. Decisions required | Superseded | Section 11 here. |
| 23. Final launch checklist | Authoritative, one edit | "on iOS and Android" becomes "on iOS" for the first launch; Android reruns the checklist. |
| 24. References | Needs rewrite | Drop Expo links; add Adhan Swift/Kotlin, GRDB, BGTaskScheduler, UNUserNotificationCenter limits. |

Rule going forward: `MOBILE_APP_PLAN.md` is edited only to add a banner at its top pointing to this document and to strike §10 and §19. Domain sections (6, 8, 11, 12, 13, 15, 16, 17, 20-identity) are maintained in place.

---

## 3. Unified product scope

### 3.1 Three pillars in one app

| Pillar | Source today | In the native app |
| --- | --- | --- |
| أذكار الصباح والمساء | `index.html` `morningAthkar` (26) and `eveningAthkar` (24) | Same two decks, same IDs, same targets, same completion semantics. |
| رقية القرين | `ruqyah-al-qareen/content.js` `RUQYAH_SEGMENTS` (15 segments, 33 readings) | A third deck type: scroll-free Quran pages with per-segment `repeat` counters, daily completion, own history. Currently reachable from athkar only through the launcher tab (`#ruqyah-tab` → external link to the other PWA, `index.html` line 1701). |
| مواقيت الصلاة والتتبع | Internal only: `prayerTimesForDate` computes Fajr/Sunrise/Asr/Sunset and derives `morning = fajr+60min`, `evening = asr+60min` for reminders | Full six-time display, next-prayer countdown, per-prayer notification offsets, five-prayer tracker per `MOBILE_APP_PLAN.md` §6. |

Shared across pillars: theme, text size, line spacing, haptics (45 ms in both PWAs: `hapticDurationMs = 45`), reduced motion, the scoped-reset picker (day / last 7 calendar days / everything; both PWAs implement `resetDayProgress`, `resetWeek`, `resetEverything` with the same Arabic wording), swipe navigation with axis lock, auto-advance, and completion dialogs.

### 3.2 Information architecture (iOS)

Tab bar, RTL order, four tabs:

1. **اليوم** (Today): Gregorian + Hijri date, next prayer with countdown, five prayer rows with quick log, morning/evening/ruqyah status chips, non-blocking notices (no location, notifications denied, stale schedule).
2. **الأذكار**: segmented control الصباح / المساء / الرقية over one card-deck view. The deck view is a single SwiftUI component parameterised by a deck definition (section 6.1), so ruqyah is not a fork of the adhkar deck.
3. **المواقيت**: six times for the selected day, previous/next day, method/school/location summary, per-prayer reminder toggles and offsets.
4. **الإعدادات**: reading and appearance; reminders (adhkar + prayers + personal); location and calculation; long-order toggle (ترتيب الأذكار الطويلة); history (calendar); backup/import including "استيراد من تطبيق الويب"; privacy, delete-all, about/content version, sources.

The PWA's tab hash routes (`#morning`, `#evening`, `#ruqyah` in `tabOrder`) become the app's deep-link routes plus `#prayers`.

### 3.3 Release boundaries for a solo iOS-first build

`MOBILE_APP_PLAN.md` §4 put nearly everything into 1.0. That was sized for a small team on one shared codebase. This plan trims iOS 1.0 to what a solo maintainer can ship with confidence, and defers the rest without dropping it.

| Feature | iOS 1.0 | iOS 1.1 | Later |
| --- | --- | --- | --- |
| Adhkar decks, counters, targets (1/10/100), manual completion, long-order, scoped resets, completion dialog | Yes | | |
| Ruqyah deck with auto-fit pages, per-segment counters, daily completion | Yes | | |
| Unbounded completion history + monthly calendar (adhkar, ruqyah, prayers) | Yes (calendar is the natural history UI once history is unbounded) | | |
| Prayer times screen (6 times, countdown, day navigation), method, Asr school, high-latitude rule, per-prayer minute adjustments | Yes | | |
| Location: current (one-shot) and manual coordinates; device time zone | Yes | Offline city list, manual zone | |
| Prayer tracker: `unrecorded` / `prayed` / `not_applicable`, optional timing, Friday choice, undo, past-day edit | Yes | Travel/combining/shortening, single-occurrence make-up link, not-applicable ranges | Optional prayers, bulk make-up ledger |
| Notifications: morning/evening adhkar (Fajr+60, Asr+60 as today), per-prayer offsets, 15-minute catch-up, completion suppression | Yes | Personal fixed-time reminders, weekday masks | |
| Backup export/import (envelope v1), PWA import | Yes | Passphrase-encrypted backups | |
| Home-screen quick actions (morning, evening, ruqyah, log prayer) | Yes (cheap on iOS) | | |
| Quick card index | Yes | | |
| Search, favorites | | Yes | |
| Widgets (WidgetKit), Qibla | | Yes | |
| Audio, Ramadan mode, English UI, biometric lock, sync | | | Per `MOBILE_APP_PLAN.md` §4 |

This trim is a scope change to the reviewed plan and is listed as a decision the user must confirm (section 11, item 4).

### 3.4 What happens to رقية القرين as a separate app

Position: **the ruqyah PWA stops being a product and becomes a distribution channel for non-iOS users.**

1. Content moves: `content.js` `RUQYAH_SEGMENTS` becomes `content/ruqyah.v1.json` in the athkar repo (section 5). The ruqyah repo's `content.js` is regenerated from that file, not edited by hand, so there is one source of truth from the day the pack exists.
2. The ruqyah PWA gains the same export button as athkar (section 6.4), because a native app cannot read its `ruqyah-daily-v1` localStorage.
3. The athkar PWA's ruqyah tab remains a launcher for the PWA generation. It is not turned into an embedded deck in the PWA; that effort belongs to the native app.
4. When the iOS app is public, both PWAs show an install banner on iOS Safari only (user-agent gated, as the existing `isIosDevice` check already does for the install dialog) pointing to the App Store listing. On Android and desktop the PWAs remain the primary experience until Android ships.
5. The ruqyah PWA is never taken down while Android is unshipped. Its published URL stays valid indefinitely; after Android ships, it may become a redirect page to the unified app plus a one-line export instruction for stragglers (decision 11.9).
6. Users' local progress: `ruqyah-daily-v1` holds `{date, counts, history: {date: {completedAt}}}` with history trimmed to 365 entries (`trimHistory`) and 30 displayed (`historyLimit`). All 365 days are importable. Legacy `ruqyah-progress-v1` is already migrated and removed on load (`loadState`), so the export only needs the daily key.

---

## 4. Shared-core decision

### 4.1 Decision

**Share specifications, data, and fixtures. Do not share executable code across platforms.**

What crosses the platform boundary, all as files under version control in the athkar repo:

| Artefact | Location | Format | iOS consumer | Android consumer (later) |
| --- | --- | --- | --- | --- |
| Adhkar content pack | `content/adhkar.v1.json` + `content/manifest.json` | JSON, schema in `content/schema/` | Bundled resource, decoded with `Codable` | Bundled asset, decoded with kotlinx.serialization |
| Ruqyah content pack | `content/ruqyah.v1.json` | JSON | same | same |
| Quran reference snapshots | `content/reference/` | Frozen copies of the two upstream editions for the verses used | CI check only | CI check only |
| Prayer-time golden vectors | `spec/prayer-times/vectors.json` | Inputs (lat, lon, zone, date, method, school, rule) → expected instants with tolerance | XCTest parity suite | JVM parity suite |
| Notification-planner fixtures | `spec/reminders/fixtures/*.json` | Given state → expected notification ID set and instants | XCTest | JVM test |
| Session-rule fixtures | `spec/sessions/fixtures/*.json` | Rollover, completion, long-order deck ordering, scoped reset outcomes | XCTest | JVM test |
| Local schema | `spec/schema.md` | Table/column definitions, migration numbering rules, invariants | GRDB migrations written to match | Room/SQLDelight migrations written to match |
| Backup envelope | `spec/backup/envelope-v1.md` + `spec/backup/examples/` | JSON with format version | Import/export | Import/export |
| Deep-link routes | `spec/routes.md` | Route table | `URL` handling | Intent filters |
| Domain wording | `content/ui-copy.json` | Arabic strings for domain states (unrecorded, prayed, not applicable, Friday choice, timing labels, reset confirmations) | String catalog seeded from it | `strings.xml` seeded from it |

Everything else (views, view models, repositories, scheduler adapters, location adapter) is written per platform.

### 4.2 Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| **Pure duplication** (no shared artefacts, Android re-derives everything from the iOS app) | The one thing that must never diverge is Quran text. Two hand-maintained copies of `content.js` is how a text error ships on one platform only. Fixtures are also what make a later Android port checkable rather than "looks the same". |
| **Kotlin Multiplatform core** (domain + calculation + planner in Kotlin, consumed on iOS as an XCFramework) | Genuine shared logic, but: it adds a Gradle toolchain to every iOS build on a solo project whose second platform is deferred indefinitely; Swift-side debugging through KMP interop is materially worse than native Swift; the domain code in question is a few hundred lines; and for prayer times a maintained native library already exists on each platform. KMP would be the right answer for a team building both platforms concurrently. Revisit only if Android starts and the Swift domain layer has grown beyond what fixtures can pin (section 9.3 states the trigger). |
| **Spec + golden vectors for calculation, hand-ported from the PWA's `solarDay`** | The PWA engine computes only Fajr, sunrise, Asr, sunset (`solarDay` returns exactly those four) and one high-latitude clamp (`safeFajr` in `prayerTimesForDate`, a night-fraction rule). It has no Dhuhr, Maghrib, Isha, Isha-interval methods (Umm al-Qura), or configurable high-latitude rules. Porting it means extending it; Adhan already contains audited versions of all of those. The PWA engine stays as a **parity oracle** for the four values it does compute. |
| **WebView reuse** (ship `index.html` inside a native shell) | Keeps every limitation the native app exists to remove: notifications still need a native scheduler and a native data store the web code cannot see; auto-fit and RTL layout inside a WKWebView are no better than Safari; App Store review treats thin wrappers unfavourably; and it makes the iOS app a third front-end to maintain rather than a replacement. |
| **Sharing TypeScript via a JS engine (JavaScriptCore)** | Same objections as KMP with worse tooling; the rules are too small to justify a runtime. |

### 4.3 How fixtures replace code sharing

Before any native code, the PWA's current behaviour is captured as fixtures. This is the same "golden fixtures before extraction" principle as `MOBILE_APP_PLAN.md` §17, made concrete:

- **Sessions**: for a set of stored `athkar-progress-v2` states and a "now", the expected outcome of `rollStateToDate`, `periodIsComplete` (counters vs `manualCompletion`), `firstIncompleteIndex`, and `buildDeck` under `longAdhkarLast = true` (long items — target ≥ `longDhikrThreshold` 10, excluding `review` items — moved to just before the last item). Generated by a small Node script that loads the PWA's functions; the script is throwaway tooling in `tools/` and its outputs are the committed fixtures.
- **Prayer times**: the PWA's `prayerTimesForDate` output for the 30-location × 12-date grid from `MOBILE_APP_PLAN.md` §8, for each of the five `prayerCalculationMethods` (`mwl` 18°, `umm-al-qura` 18.5°, `egyptian` 19.5°, `karachi` 18°, `north-america` 15°) and both `asrShadowFactors` (standard 1, hanafi 2). Stored as vectors with a stated tolerance (section 7.2).
- **Reminders**: `nextReminderTime` semantics: fire at `morning`/`evening` if in the future and not `lastShown` today; if within 15 minutes past, fire "now"; otherwise tomorrow's; and never while `periodIsComplete`.

The Swift implementation must pass these fixtures; the Kotlin implementation must pass the same files. That is the entire parity mechanism.

---

## 5. Content pipeline

### 5.1 Current state

- Adhkar text lives inline in `index.html` as JavaScript object literals (`ayatAlKursi`, `alIkhlas`, …, `comprehensiveDua`) composed into `morningAthkar`/`eveningAthkar` with IDs `morning-NN`/`evening-NN`. Item fields observed: `id`, `text`, `prefix`, `details[]`, `count`, `countLabel`, `targetOptions`, `defaultTarget`, `quran`, `noteIndex`, and the `review`/`reviewTitle`/`reviewCopy` mechanism (`cardMarkup`). `[INFERENCE]` No item currently sets `review: true`; the mechanism exists in code (`periodCountersComplete` excludes `review` items; `updateSessionProgress` changes the suffix to "ذكرًا متاحًا" when one exists) but is unused in the current content.
- Ruqyah text lives in `content.js` as `RUQYAH_SEGMENTS` with `id`, `surah`, `range`, `repeat`, `basmala`, `ayahs[{number, text}]`. Text is AlQuran Cloud `quran-uthmani`, cross-checked against Quran.com v4 uthmani per the assignment; the repositories contain no tooling for that check, so `[INFERENCE]` it was performed manually.
- The two corpora use different orthography: ruqyah is full Uthmani (`ٱلْقُرْءَانِ`, `مُّنذِرٌۭ`), while the adhkar Quran items use a simplified rasm with `﴿١﴾` ayah markers (`قُلْ هُوَ اللَّهُ أَحَدٌ ﴿١﴾`). Both are shipped and reviewed; this plan does not change either text (non-goal), but the pack schema must record which edition each Quran item follows so verification compares like with like.

### 5.2 Target layout

```
content/
  manifest.json          # pack ids, semantic versions, sha256 per pack, review record ids
  adhkar.v1.json         # morning + evening items, stable ids morning-NN / evening-NN
  ruqyah.v1.json         # segments, stable ids qaf-1-8 ... nas-full
  ui-copy.json           # domain wording (section 4.1)
  schema/adhkar.schema.json
  schema/ruqyah.schema.json
  reference/             # frozen upstream snapshots for every ayah used
    alquran-cloud.quran-uthmani.json
    quran-com.v4.uthmani.json
  REVIEW.md              # named review log: pack version, reviewer, date-free sequence id, scope, outcome
tools/
  content-validate.mjs   # schema, id uniqueness, order, checksum, two-source Quran comparison
  content-export-pwa.mjs # regenerates ruqyah/content.js and (optionally) the athkar inline arrays from the packs
```

Pack schema additions over today's fields: `kind` (`quran` | `dhikr` | `review`), `edition` for Quran items (`alquran-cloud:quran-uthmani` or `simplified-rasm`, per 5.1), `surah`/`ayahFrom`/`ayahTo` for Quran items so verification can address the reference, `sources` structured per `MOBILE_APP_PLAN.md` §12, and `reviewState`.

### 5.3 Verification rules (unchanged in principle, made tooling)

1. Schema validation and ID uniqueness; IDs are immutable once shipped because `athkar-progress-v2` `progress`/`targets` and `ruqyah-daily-v1` `counts` are keyed by them.
2. For every `kind: quran` item: character-for-character comparison, after a documented normalisation (strip ayah markers `﴿…﴾`, collapse whitespace), against **both** reference snapshots for the addressed ayah range. Any mismatch fails CI. The snapshots are refreshed only by a deliberate commit that records the upstream version.
3. Named human review recorded in `REVIEW.md` for every text or order change. CI checks that the pack's `reviewRecord` in `manifest.json` points at an entry whose `scope` covers the changed item IDs. The reviewer's name is a required field; a pack with no named reviewer cannot bump version.
4. Version bump plus changelog entry for any change.
5. Migration test: stored progress referencing every ID in the previous pack version still resolves.

### 5.4 Shipping natively

- Packs are **bundled resources** in the iOS app. No remote content in 1.0 (same as `MOBILE_APP_PLAN.md` §12).
- On launch the app compares `manifest.json` pack versions against `content_installs` (section 6.2) and records the installed version. The About screen shows it.
- **A content fix reaches users only through an app update.** This is slower than the PWA (where `sw.js` `athkar-static-v21` bumps propagate on next load via the update banner) and is accepted deliberately: a remote content channel needs signing, rollback, and a privacy re-declaration, and the risk it mitigates (a wrong Quran letter) is exactly the risk the two-source CI check exists to prevent before release. If a text error nonetheless ships, the procedure is: fix the pack, bump version, expedited App Store review request, release note naming the item ID. Remote packs are reconsidered only after the pipeline is proven (`MOBILE_APP_PLAN.md` §4 "2.0").

---

## 6. Data model and persistence

### 6.1 Storage engine on iOS

**SQLite via GRDB.swift**, WAL mode, forward-only numbered migrations, schema documented in `spec/schema.md`.

Rejected: SwiftData/Core Data. Reasons: schema is opaque to a non-Apple port, migration behaviour is harder to test against seeded previous-version databases (`MOBILE_APP_PLAN.md` §17 requires that), and SwiftData raises the minimum OS. A plain SQL schema is itself the shared artefact Android will implement with Room or SQLDelight.

Settings that are not worship data (theme, text size, line spacing, haptics, long-order, reduced motion) live in `UserDefaults`, mirrored into the backup envelope. Worship data and reminder rules live only in SQLite.

### 6.2 Tables

Extends `MOBILE_APP_PLAN.md` §11 (authoritative) with the ruqyah pillar and the settings observed in the PWAs.

| Table | Purpose | Notes |
| --- | --- | --- |
| `settings` | key/value JSON | Includes `long_order` (`last`/`original`, from `athkar-long-order-v1`), `long_order_prompt_answered` (from `athkar-long-order-prompt-v1`), calculation profile, Hijri offset. |
| `content_installs` | pack id, version, checksum, installed_at | |
| `adhkar_days` | `local_date, period, completed_at, completion_origin` | `completion_origin` ∈ `counters`, `manual` (from `manualCompletion`), `import`. One row per (date, period) whenever the period was complete. Replaces the 7-entry `history` array. |
| `adhkar_item_progress` | `local_date, period, item_id, count, target, updated_at` | Today's rows are live counters (`state.progress`, `state.targets`); past days retain their rows instead of being collapsed to booleans as `rollStateToDate` does now. `target` is stored per day so a target change tomorrow does not rewrite yesterday. |
| `ruqyah_days` | `local_date, completed_at` | From `ruqyah-daily-v1.history`. |
| `ruqyah_segment_progress` | `local_date, segment_id, count, updated_at` | Bounded by `repeat` from the pack. |
| `prayer_records` | per `MOBILE_APP_PLAN.md` §11 `prayer_logs` | Unique on `(calculation_date, prayer_key)`. |
| `not_applicable_ranges` | per §11 | 1.1 (section 3.3). |
| `location_profiles` | per §11 | 1.0 has at most one profile. |
| `reminder_rules` | `id, kind, prayer_key, offset_minutes, local_time, weekday_mask, enabled` | `kind` ∈ `adhkar_morning`, `adhkar_evening`, `prayer`, `personal`. Adhkar rules carry `prayer_key = fajr`/`asr`, `offset_minutes = 60` by default, reproducing today's fixed `+60` in `prayerTimesForDate`. |
| `reminder_state` | `rule_id, last_shown_local_date` | From `athkar-reminders-v2.lastShown`; needed for the 15-minute catch-up rule. |
| `notification_audit` | per §11 | Redacted. |

Invariants (in `spec/schema.md`): a day is "complete" for a period iff an `adhkar_days` row exists; counters are clamped to target on read exactly as `countForState` does; a `review`-kind item never participates in completion (`periodCountersComplete`).

### 6.3 Day rollover

Both PWAs roll at local civil midnight (`scheduleDayRollover` sets 00:00:01; `ensureCurrentDay` on visibility change). The native app does the same, driven by `NSCalendarDayChanged` plus a foreground check, and additionally handles the case the PWAs cannot: the app not being open at midnight. Rollover is a pure function of `local_date`; nothing is deleted, so a missed rollover only means today's counters start on first open.

### 6.4 Migration from both PWAs

A native app cannot read Safari's localStorage. Therefore (as `MOBILE_APP_PLAN.md` §13 already concluded) both PWAs must ship an **export** before the iOS app ships an **import**.

Envelope `athkar-backup` format 1, one JSON document:

| Section | Populated by athkar PWA from | Populated by ruqyah PWA from |
| --- | --- | --- |
| `meta` | `{format: 1, app: "athkar-pwa", exportedAt}` | `{format: 1, app: "ruqyah-pwa", exportedAt}` |
| `adhkar.today` | `athkar-progress-v2` → `date`, `progress`, `targets`, `completedAt`, `manualCompletion` | absent |
| `adhkar.history` | `history[]` (≤7 entries: `date`, `morning`, `evening`, `morningAt`, `eveningAt`) | absent |
| `ruqyah.today` | absent | `ruqyah-daily-v1` → `date`, `counts` |
| `ruqyah.history` | absent | `history` object (≤365 entries) |
| `reminders` | `athkar-reminders-v2` → `morning.enabled`, `evening.enabled`, `calculationMethod`, `asrSchool`, `lastShown`; `location` only if the user ticks the inclusion checkbox | absent |
| `preferences` | `athkar-theme`, `athkar-reading-text-size`, `athkar-line-spacing`, `athkar-haptics`, `athkar-long-order-v1`, `athkar-long-order-prompt-v1` | `ruqyah-theme`, `ruqyah-text-size`, `ruqyah-line-spacing`, `ruqyah-haptics` |

Not exported: `athkar-install-onboarding-v1` (install prompt state is meaningless natively).

Import rules:

- Two files may be imported independently and in either order; each merges into its own tables. Preferences: the athkar file wins over the ruqyah file when both are present, because athkar has the superset (long-order).
- Merge is by `(local_date, period)` / `(local_date)` / `(local_date, segment_id)`; an existing native row wins over an imported one except when the native row is empty. This makes re-import idempotent.
- Legacy PWA keys (`athkar-progress-v1`, `athkar-reminders-v1`, `athkar-text-size`, `ruqyah-progress-v1`) are already normalised by the PWAs' own loaders (`loadState`, `loadReminderPreferences`, the inline text-size shim) so the export never needs to understand them.
- Transport: Web Share API with a file when available, otherwise a download; on iOS the app declares a UTType for `.athkarbackup` so opening the file from Files/Mail/AirDrop launches import. A URL-encoded payload is not used: the location field and history should not transit through browser history.
- Round-trip fixture: native re-export of an imported PWA file must equal the original in every section it contained (`MOBILE_APP_PLAN.md` §13 step 5).

---

## 7. Prayer times as a feature

### 7.1 Source of truth

On iOS: `adhan-swift` (Batoul Apps, MIT) pinned by SwiftPM version and checksum, wrapped by `PrayerTimesPort` (protocol) with one production adapter. The port returns UTC instants plus the IANA zone for Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha (and, unused in 1.0, middle-of-night, last-third, Qibla). No view or planner touches the library directly.

On Android later: `adhan-kotlin` behind the identical port signature, validated against the same `spec/prayer-times/vectors.json`.

The PWA's `solarDay`/`prayerTimesForDate` are **not** ported. They remain the parity oracle for Fajr, sunrise, Asr, and sunset only.

### 7.2 Parity and correctness gate

| Check | Reference | Tolerance | Fails the gate if |
| --- | --- | --- | --- |
| P1 Legacy parity | PWA `prayerTimesForDate` for Fajr/sunrise/Asr/sunset over 30 locations × 12 dates × 5 methods × 2 schools | 2 minutes | Any vector outside tolerance without a written explanation (e.g. the PWA `safeFajr` night-fraction clamp vs Adhan's chosen high-latitude rule). |
| P2 Authority tables | Published tables for representative launch regions (decision 11.6) for all six times | 2 minutes, 3 for Fajr/Isha | Any systematic offset. |
| P3 Edge cases | Equator, 60°N+ in June, southern hemisphere, DST transitions in both directions, dateline | Documented per case | Nil result, negative night, or Fajr after sunrise. |
| P4 Cross-platform | Android later runs the identical vector file | 0 seconds difference between platforms for the same Adhan version; 1 minute across Adhan versions | Any difference not explained by a library version bump. |

Findings from P1 must be written into `spec/prayer-times/README.md`: which method parameters Adhan uses for Isha (the PWA never computed Isha) and which high-latitude rule was chosen as the default (the PWA's clamp is closest to Adhan's angle-based rule `[INFERENCE]`; confirm during Slice 3).

### 7.3 Feature surface (1.0)

- Six times for today; previous/next day; countdown to the next prayer; today's schedule visible on the Today tab.
- Configuration: calculation method (the five the PWA offers plus whatever Adhan adds; the PWA's five are the defaults surfaced first, with the same Arabic labels the settings dialog uses today), Asr school, high-latitude rule, per-prayer minute adjustments, Hijri offset.
- The schedule screen shows which location and zone produced it and when the location was last updated (the PWA already stores `location.updatedAt`).

### 7.4 Location and privacy

- One-shot `CLLocationManager` request with `.reducedAccuracy`-tolerant handling, when-in-use only, requested only when the user taps تحديد الموقع (the PWA button) or enables a reminder without a location (`setReminderEnabled` behaviour today).
- Stored coordinates are rounded to **two decimals** (≈1 km) before persistence. The PWA rounds to four (`toFixed(4)`, ≈11 m). Two decimals changes prayer times by seconds at most and is materially less identifying; the parity vectors use the rounded value so the gate reflects what ships.
- Manual coordinates are accepted for users who deny location. The zone is the device's current zone in 1.0.
- Never background, never stored off-device, excluded from backup unless the user opts in per export.

### 7.5 One notification planner for prayers and adhkar

`ReminderPlanner` is a pure Swift function: `(now, zone, schedule for horizon, rules, completion/log state, last-shown state) → [PlannedNotification{id, fireAt, category, payload}]`.

- Stable IDs: `adhkar.morning.<local_date>`, `adhkar.evening.<local_date>`, `prayer.<key>.<local_date>`, `personal.<rule_id>.<local_date>`.
- Adhkar rules are prayer-relative rules with the same offsets as today (`fajr + 60`, `asr + 60`), so there is no special case; the copy reproduces the current body ("مرّت ساعة على صلاة الفجر. حان وقت أذكار الصباح.").
- Suppression: an adhkar notification is not planned for a period that is complete (`periodIsComplete` logic); a prayer notification is not planned for an occurrence already `prayed` or `not_applicable`.
- Catch-up: if a rule's instant is up to 15 minutes in the past and not yet shown today, plan it for "now" (from `nextReminderTime`).
- Horizon and budget: iOS caps pending local notifications at 64. Seven rules per day (five prayers, two adhkar) over a **7-day horizon** is 49 requests, leaving headroom for personal rules. The planner is given the budget and truncates furthest-first; the diagnostics screen shows planned vs pending counts.
- Replan triggers: foreground, `significantTimeChangeNotification`, `NSSystemTimeZoneDidChange`, any settings/rule/location change, any completion or log write, import, day change, and an opportunistic `BGAppRefreshTask`. Replan = compute desired set, diff against `UNUserNotificationCenter.pendingNotificationRequests`, add/remove by ID. Idempotent by construction.
- Actions: prayer notifications carry a "سجّل الصلاة" action that writes the same idempotent command as the tracker screen; adhkar notifications open the deck (deep link `#morning`/`#evening`).
- Disclosure: settings copy states that reminders beyond the horizon require the app to have been opened, replacing the PWA's current disclosure.

All of the above is captured as fixtures in `spec/reminders/fixtures/` before implementation (section 4.3).

---

## 8. iOS delivery plan

### 8.1 Hard prerequisite gate: organization publisher identity

Restated from `MOBILE_APP_PLAN.md` §20 (authoritative, not summarised here): **no App Store Connect app record, no TestFlight upload, no bundle ID reservation for the product** until:

- An Apple Developer Program **organization** membership exists (or an individual membership has been converted), with the legal entity, D-U-N-S, domain, and domain email in place.
- The public developer name has been chosen deliberately at first-app creation.
- The final Team ID is known and recorded privately, so no Keychain-scoped secret is created under a throwaway team.

Additional prerequisites specific to this plan: macOS hardware or a hosted Mac with current Xcode; a physical iPhone for notification testing (simulators do not exercise terminated-state delivery faithfully).

Slices 0–4 below do **not** require the account: they run on simulator and local device builds signed with a free personal team. The gate blocks Slice 5 onward.

### 8.2 Repository layout

```
athkar/
  index.html, sw.js, …        # PWA stays at root; GitHub Pages unchanged
  content/                    # section 5
  spec/                       # section 4
  tools/                      # Node scripts: content validation, fixture generation, PWA content export
  ios/
    Athkar.xcodeproj
    Athkar/                   # app target (SwiftUI)
    AthkarCore/               # Swift package: domain, planner, PrayerTimesPort, repositories; no UIKit/SwiftUI imports
    AthkarCoreTests/          # fixture-driven tests
    AthkarUITests/
  android/                    # created only when section 9 triggers
  NATIVE_APP_PLAN.md
  MOBILE_APP_PLAN.md
```

`AthkarCore` is a local SwiftPM package so the domain can be unit-tested without booting the app and so its boundary (no platform UI) is enforced by the compiler.

### 8.3 Slices in build order

Each slice ends on an observable exit criterion. Effort bands per section 10.1.

| # | Slice | Content | Exit criterion | Band |
| --- | --- | --- | --- | --- |
| 0 | Fixtures and packs | `content/` packs extracted from `index.html` and `content.js`; `tools/content-validate.mjs` with two-source Quran check; `content-export-pwa.mjs` regenerates `ruqyah/content.js` byte-identically; session/reminder/prayer-time fixtures generated from the PWA. Pin `adhan-swift` and confirm method presets. | CI passes on the packs; regenerated `content.js` diff is empty; fixture files exist for every rule in 4.3. No native code yet. | M |
| 1 | PWA export | Export button in both PWAs producing envelope v1 (section 6.4); ruqyah PWA reads regenerated `content.js`. Ship both PWAs. | A real export from each live PWA validates against the envelope schema; this is the last PWA feature before maintenance mode. | S |
| 2 | Core package and storage | `AthkarCore`: models, GRDB schema + migration 1, repositories, session rules passing session fixtures, import of envelope v1 with round-trip test. | All session fixtures pass; import→export round-trip equals input for both PWA files. | M |
| 3 | Prayer-time port | `PrayerTimesPort` + Adhan adapter; parity suite P1–P3; location adapter; calculation settings model. | P1–P3 pass with documented exceptions; `spec/prayer-times/README.md` written. | M |
| 4 | Deck UI | One `DeckView` driven by a deck definition; adhkar morning/evening with counters, targets, manual completion, long-order (with the one-time prompt), scoped reset picker, completion dialog, swipe with axis lock, auto-advance, haptics, Uthman Taha font, auto-fit; ruqyah deck with `repeat` counters and daily completion. Settings for theme/text/spacing/haptics. | Every workflow in section 3.1 works on a device in airplane mode; VoiceOver script for tap-count, target change, manual completion, reset; screenshots at three text sizes in light/dark RTL. | L |
| **Gate** | **Identity** | Section 8.1 complete. | Organization provider visible in App Store Connect; Team ID recorded. | – |
| 5 | Prayer times and tracker UI | المواقيت tab, Today tab, tracker with `unrecorded`/`prayed`/`not_applicable`, timing, Friday choice, undo, past-day edit, monthly calendar showing prayers + adhkar + ruqyah. | Tracker transition fixtures pass; calendar never renders a "missed" state; Today shows correct next prayer across a DST boundary in a simulated zone. | L |
| 6 | Notifications | `ReminderPlanner` passing fixtures; `UNUserNotificationCenter` adapter; permission flow (requested only when a reminder is enabled, as `setReminderEnabled` does today); per-prayer offsets; adhkar rules; catch-up; actions; `BGAppRefreshTask`; diagnostics screen. | Physical-device matrix (S3 in 1.4) passes with zero duplicates; completion cancels the pending request within one replan. | L |
| 7 | Migration and privacy UI | "استيراد من تطبيق الويب" onboarding + settings; backup export; delete-all; privacy screen; About with content version and sources; quick actions; deep links. | Import of both real PWA exports on a fresh install; re-export round-trip; delete-all leaves no rows and no pending notifications. | M |
| 8 | TestFlight | Internal TestFlight (maintainer's own devices), then external group. Store metadata, Arabic RTL screenshots, privacy labels ("no data collected"), age rating, licenses. | An external tester completes S4 (section 1.4); all `MOBILE_APP_PLAN.md` §23 checklist items applicable to iOS ticked. | M |
| 9 | App Store 1.0 | Submission (8.5); PWA install banners live (section 3.4 item 4); PWAs enter maintenance mode formally. | App live; first release note published; PWAs show the banner on iOS Safari only. | S |

Slices 2–4 may proceed while the identity gate is pending; nothing in them depends on a paid account.

### 8.4 TestFlight strategy for a solo maintainer

- Internal testing is the maintainer's own iPhone(s) plus, if available, one older device. Automatic distribution on every archive.
- External testing: a small named group recruited from existing PWA users, which is also where S4 comes from. Beta review by Apple is required once per build train; submit the external build early so review latency does not sit on the critical path.
- Every TestFlight build carries the diagnostics screen, so testers can report planned/pending notification counts and content version without screenshots of worship data.
- No crash SDK. Rely on Xcode Organizer crash logs from opted-in users and TestFlight feedback (`MOBILE_APP_PLAN.md` §15 posture).

### 8.5 Contents of the first App Store submission

- iOS 1.0 scope exactly as the 1.0 column of section 3.3, nothing from 1.1.
- Packs `adhkar.v1`, `ruqyah.v1` with a completed `REVIEW.md` entry each.
- Privacy nutrition label: no data collected. Location permission string in Arabic explaining one-shot use for prayer times only. Notification permission requested contextually.
- App Store copy in Arabic (primary) with English metadata secondary if the user chooses (decision 11.7).
- Support URL and privacy-policy URL on the organization domain (identity gate).
- Screenshots: RTL, light and dark, deck, prayer times, Today, calendar.
- Release notes state the PWA import path in one sentence.

### 8.6 Build and release operations

- Local `xcodebuild` archives from tagged commits are sufficient for a solo maintainer; Xcode Cloud is optional and can be added later without changing anything else. No Expo/EAS.
- CI (GitHub Actions on a macOS runner, or local pre-push): `tools/content-validate.mjs`, `swift test` for `AthkarCore`, and the XCTest fixture suites. UI tests run locally before release, not on every push, to control cost.
- Signing credentials, Apple verification documents, and the Team ID live outside the repository (`MOBILE_APP_PLAN.md` §20).

---

## 9. Android plan

### 9.1 What is deferred

All Android UI, `adhan-kotlin` integration, Room/SQLDelight persistence, `AlarmManager`/exact-alarm policy work, boot/time-change receivers, Glance widgets, Play Console setup, and Data Safety form. `MOBILE_APP_PLAN.md` §9 Android subsection and §17 Android device tests are retained as the spec for that work.

### 9.2 What is designed now so Android is not a rewrite

Everything in section 4.1's table, plus:

- The iOS `AthkarCore` package is written with a strict "no UIKit/SwiftUI/CoreLocation/UserNotifications inside the package" rule, enforced by the package having no such dependencies. Its public types are the de-facto Kotlin interface list.
- `spec/schema.md` is updated with every GRDB migration; Android implements the *final* schema at its start, plus import of any envelope version iOS has ever exported.
- The deck definition format (which deck, which items, counter semantics, long-order eligibility) is described in `spec/sessions/deck-definition.md` so the Compose `DeckScreen` is built from the same description.
- Arabic UI copy lives in a String Catalog seeded from `content/ui-copy.json`; new keys are added to the JSON first. Android generates `strings.xml` from the same file.
- Route table in `spec/routes.md` is used for iOS deep links and quick actions; Android maps it to intent filters and shortcuts.

### 9.3 Triggers to start Android

Start when all of section 1.4 (S1–S7) hold **and** one of:

- T1: PWA usage from Android user agents is a meaningful share of PWA traffic `[INFERENCE: no analytics exist; this would have to be judged from support requests or a privacy-preserving self-report, decision 11.10]`.
- T2: a content or rule change is being held back on the PWA side because keeping PWA and iOS behaviourally aligned has become the dominant maintenance cost.

Revisit the KMP rejection (section 4.2) at that moment only if `AthkarCore` has exceeded roughly 3 000 lines of domain logic that fixtures alone struggle to pin; below that, a direct Kotlin port against the fixtures remains cheaper.

---

## 10. Risks and effort

### 10.1 Effort bands

Bands are for one maintainer with AI assistance, counting focused working time, not elapsed time:

| Band | Meaning |
| --- | --- |
| S | Up to about 15 hours |
| M | About 15–40 hours |
| L | About 40–100 hours |
| XL | More than 100 hours |

Summing section 8.3: two S, four M, three L. Honest total for iOS 1.0 is in the **XL range, plausibly 250–400 hours of focused work**, dominated by Slices 4–6 (deck UI fidelity, tracker, notifications) and by physical-device testing that AI assistance cannot shorten. First-time Swift/SwiftUI ramp-up adds to that if the maintainer has not shipped SwiftUI before `[INFERENCE: prior Swift experience is unknown]`. Android later is another L–XL, smaller than iOS because the spec and fixtures exist.

Token cost: the expensive AI phases are the ones with long iterative feedback loops (SwiftUI layout of auto-fit Arabic cards; notification edge cases). Fixture-first ordering (Slice 0 before any UI) is chosen partly to keep later prompts short and verifiable.

### 10.2 Risk table (additions to `MOBILE_APP_PLAN.md` §21)

| Risk | Consequence | Mitigation |
| --- | --- | --- |
| Identity gate stalls (no legal entity, D-U-N-S delays) | Slices 5–9 blocked; work continues on 2–4 but cannot ship. | Start the gate before Slice 0; it has no code dependency. |
| No Mac / Xcode access | iOS cannot start at all. | Prerequisite in section 11. |
| Dropping the PWAs too early | Android users and non-App-Store iOS users lose the only working app; ruqyah users lose their history if they never exported. | Section 10.4 policy; PWAs are never removed before Android ships; export stays available indefinitely. |
| Maintaining PWA + iOS + Android simultaneously | Three codebases for one person; every content fix triples. | PWAs in maintenance mode with regenerated content (`content-export-pwa.mjs`) so a pack fix is one commit; Android only after S6 shows the iOS load has dropped. |
| Silent divergence between PWA and native rules during the long overlap | Users see different completion or reminder behaviour on two surfaces. | PWA rule changes are frozen (10.4); any exception must update the fixtures first, which forces the native side to follow. |
| Quran text regression during extraction | Worst-case product failure. | Slice 0 regenerates `content.js` byte-identically and compares every Quran item to two references before any native code. |
| Adhan preset mismatch with PWA angles | Prayer times shift for existing reminder users. | P1 parity gate with written exceptions; release note if any material shift is accepted. |
| iOS 64-request budget exceeded by personal reminders | Later notifications silently dropped. | Planner budget truncation and diagnostics count in 1.0, before personal reminders exist. |
| SwiftUI auto-fit for scroll-free Quran pages harder than CSS | Ruqyah cards scroll or clip. | Slice 4 exit criterion includes all 15 ruqyah segments fitting at three text sizes on the smallest supported device; fallback is a per-segment minimum size stored in the pack. |
| Solo-maintainer burnout | Project stalls mid-slice. | Slices are independently shippable to TestFlight from Slice 5 on; nothing is half-built across slices. |

### 10.3 What would falsify this plan

- Slice 3 shows Adhan cannot reproduce the PWA's Fajr within tolerance for the launch regions and the difference cannot be attributed to a documented rule; then a hand-port of `solarDay` extended with Isha/Maghrib becomes the engine, and the vectors are regenerated from it.
- Slice 4 shows SwiftUI cannot fit ruqyah pages without scrolling at the smallest supported device and large text; then the pack gains per-segment layout hints, or the smallest device is dropped from support.
- The identity gate proves impossible (no qualifying entity can be formed); then iOS distribution is delayed or shipped under a personal seller name, which `MOBILE_APP_PLAN.md` §20 explicitly advises against. Android-first would then be reconsidered, since Play does not impose the same seller-name constraint `[INFERENCE]`.

### 10.4 Interim policy for the two live PWAs

Effective from the end of Slice 1:

| Allowed | Not allowed |
| --- | --- |
| Bug fixes that do not change stored-state semantics | New features, new storage keys, new tabs |
| Content fixes, applied to `content/` and regenerated into the PWA by `content-export-pwa.mjs` | Hand-editing `content.js` or the inline arrays in `index.html` |
| The export feature (Slice 1) and, at 1.0, the iOS install banner | Import into the PWA (native is the destination, not the PWA) |
| `sw.js` cache-name bumps to deliver the above | Any change to `normalizeState`, `rollStateToDate`, `buildDeck`, `prayerTimesForDate`, `nextReminderTime` unless the corresponding fixture is updated first |

The athkar PWA's ruqyah launcher tab stays as is. `MOBILE_APP_PLAN.md` and this document are linked from the athkar README; the ruqyah README gains one line pointing here.

---

## 11. Open decisions before implementation

1. **Legal entity and Apple identity.** Which entity will hold the organization membership, its public developer name, the support/privacy domain, and who is Account Holder. Nothing in Slice 5+ can ship without this (section 8.1).
2. **Mac access.** Owned Mac, hosted Mac, or other; and which physical iPhone(s) are available for the notification matrix.
3. **Minimum iOS version.** Recommendation: iOS 17, for SwiftUI maturity and `@Observable`; lower only if a known user base demands it.
4. **Scope trim approval.** Confirm the 1.0 / 1.1 split in section 3.3, in particular moving travel/make-up/not-applicable ranges, search, favorites and personal reminders to 1.1.
5. **Named reviewers.** Who signs `REVIEW.md` for the adhkar pack, the ruqyah pack, and the tracker wording in `content/ui-copy.json`. Without a name the packs cannot version-bump.
6. **Launch regions and authority tables.** Which regions' published tables are the P2 reference, and which method is the default for a fresh install (the PWA defaults to `mwl`).
7. **Product name and English metadata.** The PWA titles itself "أذكار المسلم" (document title in `selectTab`); confirm the App Store name and whether English store metadata is provided at launch.
8. **Quran edition policy for adhkar items.** Keep the simplified rasm for `ayatAlKursi`, `alIkhlas`, `alFalaq`, `anNas`, `comprehensiveDua` and verify against a matching reference, or migrate them to the same Uthmani edition as ruqyah. Recommendation: keep as shipped for 1.0, record the edition in the pack, and treat unification as a reviewed content change later.
9. **Fate of the ruqyah PWA after Android ships.** Keep live indefinitely, or convert to a redirect page with export instructions. Recommendation: keep live; the maintenance cost is near zero once content is regenerated from the pack.
10. **How Android demand will be judged.** No analytics exist and none are planned; decide whether support requests alone are sufficient to satisfy trigger T1, or whether the PWA gains a privacy-preserving "I use Android" self-report link.
11. **Location rounding.** Confirm two decimals (section 7.4) versus the PWA's four.
12. **Backup encryption.** Whether iOS 1.0 ships plaintext-only export (with the location exclusion default) and defers the passphrase envelope to 1.1, as this plan recommends.
