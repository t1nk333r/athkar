# Athkar native app plan: Swift/SwiftUI first, Kotlin/Compose later

## Status

This document records the stack and sequence for combining three parts into one native app:

1. The Athkar PWA (`index.html`, `sw.js`, GitHub Pages at https://t1nk333r.github.io/athkar/).
2. The رقية القرين PWA (`~/Projects/ruqyah-al-qareen/index.html` + `content.js`, https://t1nk333r.github.io/ruqyah-al-qareen/).
3. A new first-class prayer-times feature with per-prayer reminders and the tracker already designed in `MOBILE_APP_PLAN.md`.

This document replaces only the stack decision in `MOBILE_APP_PLAN.md` (React Native + Expo, Flutter fallback). Section 2 classifies every section of that document as *authoritative*, *superseded*, or *needs rewrite*. This mapping prevents contradictions between the two documents. If the plans disagree, this one takes precedence.

It is a plan, not a status report. No native code exists. No Apple Developer account or organization identity exists yet. Work is not starting immediately.

This plan cites the file and symbol for each claim about current behaviour. Claims that the repositories could not verify are marked `[INFERENCE]`. Effort uses relative bands (S/M/L/XL, defined in section 10), not calendar dates.

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

`MOBILE_APP_PLAN.md` §10 gives four reasons for choosing React Native. Those reasons have weakened:

| RN/Expo argument in `MOBILE_APP_PLAN.md` §10 | Current assessment |
| --- | --- |
| "Existing JavaScript domain rules and content can be migrated to typed shared packages." | The relevant domain code is small. The functions `normalizeState`, `rollStateToDate`, `periodIsComplete`, `buildDeck`, `nextReminderTime`, `solarDay`, and `prayerTimesForDate` in `index.html` total a few hundred lines. Rewriting the rules in Swift and pinning them with fixtures costs little. The *content* must be shared, and it is data, not code. |
| "The PWA and native app can share content, backup schemas, search normalization, and pure scheduling rules." | Content, backup schema, and fixtures remain shared (section 4) as JSON and test vectors. Sharing them does not require a JavaScript runtime in the app. |
| "Expo provides maintained iOS/Android notification and SQLite APIs while prebuild permits native widgets." | On iOS, `UNUserNotificationCenter`, `CoreLocation`, `BGTaskScheduler`, WidgetKit, and SQLite are first-party and directly reachable from Swift. Expo adds an abstraction over the same APIs the app depends on for edge cases such as pending-request budgets, delivery after termination, and time-zone changes. |
| "It avoids maintaining two complete native UIs for a small team." | That remains a real cost (1.3). The team has one person, Android is explicitly deferred, and the app has a small UI: card decks, a prayer-times list, a tracker, and settings. React Native requires ongoing maintenance for Metro, Hermes, native-module version churn, Expo SDK upgrades, and the Arabic text-shaping defects identified as an architecture falsifier in `MOBILE_APP_PLAN.md` §10. The cost of maintaining two UIs begins only when Android work starts. |

Additional reasons specific to this product:

- **Arabic typography is central to the app.** Each card is a page of Quran or dhikr set in KFGQPC Uthman Taha Naskh (`fonts/kfgqpc-uthman-taha-naskh.ttf` in both repos), with auto-fit sizing so no card scrolls (`fitCardContent` in athkar, `fitCardText` in ruqyah). `MOBILE_APP_PLAN.md` §10 already lists RN text-shaping defects as a reason to reject the architecture. SwiftUI `Text` with Core Text shaping and Dynamic Type eliminates that risk on iOS.
- **Reliable notifications are also central to the app.** The PWA's own status copy admits the limitation: "يعمل المؤقت أثناء فتح التطبيق، ويعتمد العمل بعد إغلاقه على دعم النظام" (`updateReminderControls`). The native app exists to schedule notifications that survive termination. Use `UNUserNotificationCenter` directly, without an intermediary.
- **A solo maintainer pays per token.** Fewer components to maintain on each platform mean fewer upgrade-driven regressions to diagnose with paid assistance. A SwiftUI project uses one toolchain (Xcode) and one package manager (SwiftPM).

### 1.3 Costs accepted

| Cost | Consequence | Mitigation |
| --- | --- | --- |
| Two UI codebases eventually | Build every screen twice. After fixing a UI bug on iOS, check the corresponding Android UI independently. | Android is deferred until iOS is stable. By then, the design system, copy, and flows are frozen and become the Android implementation spec. |
| No shared business-logic code | Domain rules (rollover, completion, deck ordering, planner) exist twice. | Platform-neutral fixtures pin the rules (section 4.3). Tests catch divergence without code sharing. |
| Domain expertise split | Swift and Kotlin both require learning and maintenance. | Work sequentially, not in parallel. Start Android only when iOS demands little attention. |
| Android users wait longer | Android users stay on the PWAs for the whole iOS phase. | PWAs remain live and get bug/content fixes (section 10.4). |
| A Mac and Xcode are required | The current workstation is Linux (`uname` shows Arch Linux). iOS development cannot proceed without macOS hardware or a hosted Mac. | This is a hard prerequisite alongside the Apple Developer account (section 11). |

### 1.4 "iOS is stable": criteria that unblock Android

Android work may begin only after all of these criteria are met. Each criterion can be observed without a calendar.

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

This document classifies every section of the existing plan. "Authoritative" means the section remains as written and this document does not restate it. "Superseded" means this document replaces the section. "Needs rewrite" means the content is still relevant but uses Expo/RN terms and must be re-expressed; this document names the rewrite target.

| `MOBILE_APP_PLAN.md` section | Status | Notes |
| --- | --- | --- |
| Status | Superseded | This document is the status. |
| 1. Product outcome | Needs rewrite | Keep the definition of a complete release. Change "on both platforms" to "on iOS; Android inherits when started". Add the ruqyah pillar (section 3 here). |
| 2. Product principles | Authoritative, one edit | Principle 9 ("shared … pure TypeScript rules") is superseded by section 4 here: shared *data and fixtures*, not TypeScript. |
| 3. Current PWA baseline | Needs rewrite | Item counts are stale: the repo now has 26 morning (`morning-01`…`morning-26`) and 24 evening (`evening-01`…`evening-24`) cards, including `comprehensiveDua` (البقرة ٢٠١) inserted before `salatUponProphet`. The long-order feature (`buildDeck`, `athkar-long-order-v1`), the scoped reset picker (`resetWeek`, `resetEverything`, `dayCountLabel`), and the ruqyah tab did not exist when §3 was written. Section 3 here is the replacement baseline. |
| 4. Scope and release boundaries | Superseded | Section 3.3 here redefines 1.0/1.1 for a solo iOS-first build. |
| 5. Information architecture | Needs rewrite | Add a رقية pillar and keep the Today / Prayer times / Tracker / Athkar / Calendar / Settings structure. See section 3.2 here. |
| 6. Prayer tracker domain (6.1–6.9) | **Authoritative** | Occurrence identity, recording states, Friday, travel, not-applicable, make-up, optional prayers, midnight rules. Not restated here. Only the *release* of travel/make-up/optional prayers moves (section 3.3). |
| 7. The eight README features | Needs rewrite | Keep the contracts, but change their release assignments (section 3.3). |
| 8. Prayer calculations, location, Hijri | Authoritative in intent, superseded in library | Keep the intent but replace "Adhan JS" with the native Adhan editions. The correctness gate (30 locations × 12 dates, authority tables, edge cases) remains and section 7 expands it. Keep the location policy, with one change to rounding (section 7.4). |
| 9. Native reminders | Needs rewrite | Planner requirements and replan triggers are authoritative. "via Expo Notifications" is removed. Android subsection is deferred but retained as the Android spec. Section 7.5 here. |
| 10. Recommended architecture | **Superseded** | Entire section (stack, falsifiers, repo shape, module seams) replaced by sections 1, 4, 8 here. |
| 11. Persistence and data model | Authoritative, extended | Keep the table set. Section 6 adds ruqyah tables, the long-order setting, and the iOS storage engine choice. |
| 12. Content-pack system and governance | Authoritative, extended | Section 5 here adds the ruqyah pack, the two-source Quran check, and native shipping. |
| 13. Backup, migration, sync | Authoritative, extended | Section 6.4 here adds the ruqyah keys and removes "Web Crypto and React Native" from the encryption requirement. |
| 14. Widgets, quick actions, deep links | Authoritative | Widgets stay 1.1; "Expo configuration" references removed by implication. |
| 15. Privacy and security | **Authoritative** | Unchanged. |
| 16. Accessibility and localization | Authoritative | Unchanged; the Android-specific device tests apply when Android starts. |
| 17. Quality strategy | Authoritative | Section 4.3 builds on the fixture-first approach. |
| 18. Nonfunctional targets | Authoritative | Android baseline-device targets apply when Android starts. |
| 19. Delivery phases and gates | **Superseded** | Section 8 here is the iOS slice plan; section 9 the Android plan. |
| 20. CI/CD and release operations | Split | The **iOS publisher-identity procedure (individual→organization migration, developer name, app transfer, Keychain/Team-ID cautions, identity gate)** remains **authoritative** and is restated as a gate in section 8.1. Replace "Expo/EAS" references in the build-cutover subsection with Xcode Cloud or local `xcodebuild` (section 8.6). |
| 21. Major risks | Authoritative, extended | Section 10 here adds Swift-first and PWA-lifecycle risks. |
| 22. Decisions required | Superseded | Section 11 here. |
| 23. Final launch checklist | Authoritative, one edit | "on iOS and Android" becomes "on iOS" for the first launch; Android reruns the checklist. |
| 24. References | Needs rewrite | Drop Expo links; add Adhan Swift/Kotlin, GRDB, BGTaskScheduler, UNUserNotificationCenter limits. |

Going forward, edit `MOBILE_APP_PLAN.md` only to add a banner at the top that points to this document and to strike §10 and §19. Maintain domain sections (6, 8, 11, 12, 13, 15, 16, 17, 20-identity) in place.

---

## 3. Unified product scope

### 3.1 Three pillars in one app

| Pillar | Source today | In the native app |
| --- | --- | --- |
| أذكار الصباح والمساء | `index.html` `morningAthkar` (26) and `eveningAthkar` (24) | Same two decks, same IDs, same targets, same completion semantics. |
| رقية القرين | `ruqyah-al-qareen/content.js` `RUQYAH_SEGMENTS` (15 segments, 33 readings) | A third deck type: scroll-free Quran pages with per-segment `repeat` counters, daily completion, own history. Currently reachable from athkar only through the launcher tab (`#ruqyah-tab` → external link to the other PWA, `index.html` line 1701). |
| مواقيت الصلاة والتتبع | Internal only: `prayerTimesForDate` computes Fajr/Sunrise/Asr/Sunset and derives `morning = fajr+60min`, `evening = asr+60min` for reminders | Full six-time display, next-prayer countdown, per-prayer notification offsets, five-prayer tracker per `MOBILE_APP_PLAN.md` §6. |

All three pillars share a theme, text size, line spacing, haptics (45 ms in both PWAs: `hapticDurationMs = 45`), reduced motion, the scoped-reset picker (day / last 7 calendar days / everything; both PWAs implement `resetDayProgress`, `resetWeek`, and `resetEverything` with the same Arabic wording), swipe navigation with axis lock, auto-advance, and completion dialogs.

### 3.2 Information architecture (iOS)

Use a four-tab bar in RTL order:

1. **اليوم** (Today): Gregorian + Hijri date, next prayer with countdown, five prayer rows with quick log, morning/evening/ruqyah status chips, non-blocking notices (no location, notifications denied, stale schedule).
2. **الأذكار**: segmented control الصباح / المساء / الرقية over one card-deck view. The deck view is a single SwiftUI component parameterised by a deck definition (section 6.1), so ruqyah is not a fork of the adhkar deck.
3. **المواقيت**: six times for the selected day, previous/next day, method/school/location summary, per-prayer reminder toggles and offsets.
4. **الإعدادات**: reading and appearance; reminders (adhkar + prayers + personal); location and calculation; long-order toggle (ترتيب الأذكار الطويلة); history (calendar); backup/import including "استيراد من تطبيق الويب"; privacy, delete-all, about/content version, sources.

The PWA's tab hash routes (`#morning`, `#evening`, `#ruqyah` in `tabOrder`) become the app's deep-link routes plus `#prayers`.

### 3.3 Release boundaries for a solo iOS-first build

`MOBILE_APP_PLAN.md` §4 put nearly every feature into 1.0. That scope assumed a small team sharing one codebase. This plan narrows iOS 1.0 to features a solo maintainer can ship with confidence and defers the rest without removing them.

| Feature | iOS 1.0 | iOS 1.1 | Later |
| --- | --- | --- | --- |
| Adhkar decks, counters, targets (1/10/100), manual completion, long-order, scoped resets, completion dialog | Yes | | |
| Ruqyah deck with auto-fit pages, per-segment counters, daily completion | Yes | | |
| Unbounded completion history + monthly calendar (adhkar, ruqyah, prayers) | Yes (the calendar is a natural way to browse unbounded history) | | |
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

The ruqyah PWA stops being a product and becomes a distribution channel for non-iOS users.

1. Move `RUQYAH_SEGMENTS` from `content.js` to `content/ruqyah.v1.json` in the athkar repo (section 5). Generate the ruqyah repo's `content.js` from that file instead of editing it by hand. This gives the content pack one source of truth from the day it exists.
2. The ruqyah PWA gets the same export button as athkar (section 6.4), because a native app cannot read its `ruqyah-daily-v1` localStorage.
3. Keep the athkar PWA's ruqyah tab as a launcher for the separate PWA. Do not embed the deck in the athkar PWA; that work belongs in the native app.
4. When the iOS app is public, both PWAs show an install banner on iOS Safari only (user-agent gated, as the existing `isIosDevice` check already does for the install dialog) pointing to the App Store listing. On Android and desktop the PWAs remain the primary experience until Android ships.
5. Keep the ruqyah PWA online while Android remains unshipped. Its published URL stays valid indefinitely. After Android ships, it may become a redirect page to the unified app with a one-line export instruction for remaining users (decision 11.9).
6. Users' local progress is stored in `ruqyah-daily-v1`, which holds `{date, counts, history: {date: {completedAt}}}`. The history is trimmed to 365 entries (`trimHistory`), and the app displays 30 entries (`historyLimit`). All 365 days can be imported. On load, `loadState` already migrates and removes the legacy `ruqyah-progress-v1` key, so the export needs only the daily key.

---

## 4. Shared-core decision

### 4.1 Decision

**Share specifications, data, and fixtures. Do not share executable code across platforms.**

The shared artefacts are files under version control in the athkar repo:

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

Write everything else separately for each platform, including views, view models, repositories, scheduler adapters, and location adapters.

### 4.2 Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| **Pure duplication** (no shared artefacts, Android re-derives everything from the iOS app) | Quran text must never diverge. Two hand-maintained copies of `content.js` could let a text error ship on only one platform. Fixtures also make a later Android port testable instead of relying on whether it looks the same. |
| **Kotlin Multiplatform core** (domain + calculation + planner in Kotlin, consumed on iOS as an XCFramework) | Genuine shared logic, but: it adds a Gradle toolchain to every iOS build on a solo project whose second platform is deferred indefinitely; Swift-side debugging through KMP interop is materially worse than native Swift; the domain code in question is a few hundred lines; and for prayer times a maintained native library already exists on each platform. KMP would be the right answer for a team building both platforms concurrently. Revisit only if Android starts and the Swift domain layer has grown beyond what fixtures can pin (section 9.3 states the trigger). |
| **Spec + golden vectors for calculation, hand-ported from the PWA's `solarDay`** | The PWA engine computes only Fajr, sunrise, Asr, and sunset (`solarDay` returns exactly those four), plus one high-latitude clamp (`safeFajr` in `prayerTimesForDate`, a night-fraction rule). It has no Dhuhr, Maghrib, Isha, Isha-interval methods (Umm al-Qura), or configurable high-latitude rules. Porting it would mean adding these features. Adhan already contains audited versions of them. The PWA engine remains the comparison reference for its four computed values. |
| **WebView reuse** (ship `index.html` inside a native shell) | WebView reuse retains every limitation the native app exists to remove. Notifications still need a native scheduler and a native data store the web code cannot see. Auto-fit and RTL layout inside a WKWebView are no better than in Safari. App Store review treats thin wrappers unfavourably. WebView reuse would also make the iOS app a third front end to maintain instead of replacing the PWA. |
| **Sharing TypeScript via a JS engine (JavaScriptCore)** | Sharing TypeScript through JavaScriptCore has the same issues as KMP and worse tooling. The rules are too small to justify a runtime. |

### 4.3 How fixtures replace code sharing

Before writing native code, capture the PWA's current behaviour in fixtures. This follows the "golden fixtures before extraction" principle from `MOBILE_APP_PLAN.md` §17 and applies it concretely:

- For each stored `athkar-progress-v2` state and a `"now"` value, record the expected results of `rollStateToDate`, `periodIsComplete` (counters vs `manualCompletion`), `firstIncompleteIndex`, and `buildDeck` when `longAdhkarLast = true`. Move long items, those with target ≥ `longDhikrThreshold` 10 and not marked `review`, to just before the last item. A small Node script loads the PWA's functions and generates the fixtures. Keep the script as throwaway tooling in `tools/`; commit its outputs as fixtures.
- Generate prayer-time fixtures from the PWA's `prayerTimesForDate` output for the 30-location × 12-date grid from `MOBILE_APP_PLAN.md` §8. Cover each of the five `prayerCalculationMethods` (`mwl` 18°, `umm-al-qura` 18.5°, `egyptian` 19.5°, `karachi` 18°, `north-america` 15°) and both `asrShadowFactors` (standard 1, hanafi 2). Store the results as vectors with a stated tolerance (section 7.2).
- `nextReminderTime` fires at `morning`/`evening` if the time is in the future and `lastShown` is not today. If the time was within 15 minutes in the past, it fires "now"; otherwise, it fires tomorrow. It never fires when `periodIsComplete` is true.

The Swift implementation must pass these fixtures. The Kotlin implementation must pass the same files. This is the full parity mechanism.

---

## 5. Content pipeline

### 5.1 Current state

- `index.html` contains the adhkar text as JavaScript object literals (`ayatAlKursi`, `alIkhlas`, …, `comprehensiveDua`) composed into `morningAthkar`/`eveningAthkar` with IDs `morning-NN`/`evening-NN`. The observed item fields are `id`, `text`, `prefix`, `details[]`, `count`, `countLabel`, `targetOptions`, `defaultTarget`, `quran`, and `noteIndex`, along with the `review`/`reviewTitle`/`reviewCopy` mechanism (`cardMarkup`). `[INFERENCE]` No current item sets `review: true`. The mechanism exists in the code: `periodCountersComplete` excludes `review` items, and `updateSessionProgress` changes the suffix to "ذكرًا متاحًا" when one exists. The current content does not use it.
- Ruqyah text is in `content.js` under `RUQYAH_SEGMENTS`, with fields `id`, `surah`, `range`, `repeat`, `basmala`, and `ayahs[{number, text}]`. The text uses AlQuran Cloud `quran-uthmani` and was cross-checked against Quran.com v4 uthmani per the assignment. The repositories have no tooling for that check, so `[INFERENCE]` it was performed manually.
- The two corpora use different orthographies. Ruqyah uses full Uthmani (`ٱلْقُرْءَانِ`, `مُّنذِرٌۭ`), while the adhkar Quran items use a simplified rasm with `﴿١﴾` ayah markers (`قُلْ هُوَ اللَّهُ أَحَدٌ ﴿١﴾`). Both corpora are shipped and reviewed. This plan does not change either text (non-goal), but the pack schema must record each Quran item's edition so verification compares matching editions.

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
  REVIEW.md              # named review log: pack version, reviewed pack SHA-256, reviewer, date-free sequence id, scope, outcome
tools/
  content-validate.mjs   # schema, id uniqueness, order, checksum, two-source Quran comparison
  content-export-pwa.mjs # regenerates ruqyah/content.js and (optionally) the athkar inline arrays from the packs
```

Pack schema additions over today's fields: `kind` (`quran` | `dhikr` | `review`), `edition` for Quran items (`alquran-cloud:quran-uthmani` or `simplified-rasm`, per 5.1), `surah`/`ayahFrom`/`ayahTo` for Quran items so verification can address the reference, `sources` structured per `MOBILE_APP_PLAN.md` §12, and `reviewState`.

### 5.3 Verification rules (unchanged in principle, made tooling)

1. Validate the schema and check ID uniqueness. Once shipped, IDs cannot change because `athkar-progress-v2` `progress`/`targets` and `ruqyah-daily-v1` `counts` are keyed by them.
2. For every `kind: quran` item, compare every character, after documented normalisation (strip ayah markers `﴿…﴾`, collapse whitespace), against **both** reference snapshots for the addressed ayah range. Any mismatch fails CI. Refresh snapshots only in a deliberate commit that records the upstream version.
3. Named human review recorded in `REVIEW.md` for every text or order change. CI checks that the pack's `reviewRecord` in `manifest.json` points at an entry whose `scope` covers the changed item IDs. The reviewer's name is a required field; a pack with no named reviewer cannot bump version.
4. Version bump plus changelog entry for any change.
5. Migration test: stored progress referencing every ID in the previous pack version still resolves.

### 5.4 Shipping natively

- Packs are **bundled resources** in the iOS app. No remote content in 1.0 (same as `MOBILE_APP_PLAN.md` §12).
- On launch the app compares `manifest.json` pack versions against `content_installs` (section 6.2) and records the installed version. The About screen shows it.
- **Users receive content fixes only through an app update.** This is slower than the PWA, where `sw.js` `athkar-static-v21` bumps propagate on next load through the update banner. The delay is deliberate. A remote content channel needs signing, rollback, and a privacy re-declaration. It would mitigate the risk of a wrong Quran letter, which the two-source CI check is designed to prevent before release. If an error ships, fix the pack, bump its version, request expedited App Store review, and publish a release note naming the item ID. Reconsider remote packs only after the pipeline is proven (`MOBILE_APP_PLAN.md` §4 "2.0").

---

## 6. Data model and persistence

### 6.1 Storage engine on iOS

**SQLite via GRDB.swift**, WAL mode, forward-only numbered migrations, schema documented in `spec/schema.md`.

Reject SwiftData/Core Data because their schemas are opaque to a non-Apple port, migration behavior is harder to test against seeded previous-version databases (`MOBILE_APP_PLAN.md` §17 requires this), and SwiftData raises the minimum OS. A plain SQL schema is the shared artifact Android will implement with Room or SQLDelight.

Store settings unrelated to worship data (theme, text size, line spacing, haptics, long-order, reduced motion) in the SQLite `settings` table (`spec/schema.md`) and mirror them into the backup envelope. The app may also mirror them into `UserDefaults` for fast launch-time reads. SQLite holds the authoritative values; record import precedence between the two PWA files in `spec/schema.md`. Keep worship data and reminder rules only in SQLite.

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

The invariants in `spec/schema.md` are: a day is complete for a period if and only if an `adhkar_days` row exists; readers clamp counters to target exactly as `countForState` does; a `review`-kind item never participates in completion (`periodCountersComplete`).

### 6.3 Day rollover

Both PWAs roll at local civil midnight. `scheduleDayRollover` sets 00:00:01, and `ensureCurrentDay` runs on visibility change. The native app also rolls at local civil midnight, using `NSCalendarDayChanged` plus a foreground check. It handles a case the PWAs cannot: when the app is not open at midnight. Rollover is a pure function of `local_date`; it deletes nothing, so if rollover is missed, today's counters start on first open.

### 6.4 Migration from both PWAs

Safari's localStorage is inaccessible to a native app. As `MOBILE_APP_PLAN.md` §13 already concludes, both PWAs must ship an **export** before the iOS app ships an **import**.

The `athkar-backup` export uses format 1 and contains one JSON document:

| Section | Populated by athkar PWA from | Populated by ruqyah PWA from |
| --- | --- | --- |
| `meta` | `{format: 1, app: "athkar-pwa", exportedAt, timeZone}` | `{format: 1, app: "ruqyah-pwa", exportedAt, timeZone}` |
| `adhkar.today` | `athkar-progress-v2` → `date`, `progress`, `targets`, `completedAt`, `manualCompletion` | absent |
| `adhkar.history` | `history[]` (≤7 entries: `date`, `morning`, `evening`, `morningAt`, `eveningAt`) | absent |
| `ruqyah.today` | absent | `ruqyah-daily-v1` → `date`, `counts` |
| `ruqyah.history` | absent | `history` object (≤365 entries) |
| `reminders` | `athkar-reminders-v2` → `morning.enabled`, `evening.enabled`, `calculationMethod`, `asrSchool`, `lastShown`; `location` only if the user ticks the inclusion checkbox | absent |
| `preferences` | `athkar-theme`, `athkar-reading-text-size`, `athkar-line-spacing`, `athkar-haptics`, `athkar-long-order-v1`, `athkar-long-order-prompt-v1` | `ruqyah-theme`, `ruqyah-text-size`, `ruqyah-line-spacing`, `ruqyah-haptics` |

The export omits `athkar-install-onboarding-v1` because the install-prompt state has no meaning natively.

Import rules:

- Import either file independently and in either order. Merge each into its own tables. If both files contain preferences, use the athkar file because it has the superset, including long-order.
- Merge by `(local_date, period)` / `(local_date)` / `(local_date, segment_id)`. An existing native row wins over an imported row unless the native row is empty. This makes re-import idempotent.
- The PWA loaders (`loadState`, `loadReminderPreferences`, and the inline text-size shim) already normalise legacy keys (`athkar-progress-v1`, `athkar-reminders-v1`, `athkar-text-size`, `ruqyah-progress-v1`). The export does not need to handle them.
- Use the Web Share API with a file when available; otherwise, download the export. On iOS, declare a UTType for `.athkarbackup` so opening the file from Files/Mail/AirDrop launches import. Keep the payload out of URLs so the location field and history do not pass through browser history.
- For the round-trip fixture, re-exporting a PWA file after native import must reproduce every section in the original (`MOBILE_APP_PLAN.md` §13 step 5), except for the cases listed in `spec/schema.md` "Export". Coordinates return rounded to 2 decimals (§7.4). The app does not store adhkar history days when neither period was complete because they contain no worship data; those days are absent from re-export.
- Envelope v1 carries only data the PWAs hold. A native-to-native restore therefore loses native-only prayer settings: the Adhan-only methods (which a v1 export writes as `mwl`), the high-latitude rule, per-prayer adjustments, and Hijri offset. Before the native app ships its own export (backup UI), envelope format 2 adds a `prayerSettings` section; importers keep accepting format 1.

---

## 7. Prayer times as a feature

### 7.1 Source of truth

On iOS, pin `adhan-swift` (Batoul Apps, MIT) by SwiftPM version and checksum. Wrap it in `PrayerTimesPort` (protocol) with one production adapter. The port returns UTC instants and the IANA zone for Fajr, Sunrise, Dhuhr, Asr, Maghrib, and Isha. It also returns middle-of-night, last-third, and Qibla values, which 1.0 does not use. No view or planner may call the library directly.

On Android later, put `adhan-kotlin` behind the same port signature and validate it against `spec/prayer-times/vectors.json`.

Do not port the PWA's `solarDay` or `prayerTimesForDate`. Use them as the comparison reference for Fajr, sunrise, Asr, and sunset only.

### 7.2 Parity and correctness gate

| Check | Reference | Tolerance | Fails the gate if |
| --- | --- | --- | --- |
| P1 Legacy parity | PWA `prayerTimesForDate` for Fajr/sunrise/Asr/sunset over 30 locations × 12 dates × 5 methods × 2 schools | 2 minutes | Any vector outside tolerance without a written explanation (e.g. the PWA `safeFajr` night-fraction clamp vs Adhan's chosen high-latitude rule). |
| P2 Authority tables | Published tables for representative launch regions (decision 11.6) for all six times | 2 minutes, 3 for Fajr/Isha | Any systematic offset. |
| P3 Edge cases | Equator, 60°N+ in June, southern hemisphere, DST transitions in both directions, dateline | Documented per case | Nil result, negative night, or Fajr after sunrise. |
| P4 Cross-platform | Android later runs the identical vector file | 0 seconds difference between platforms for the same Adhan version; 1 minute across Adhan versions | Any difference not explained by a library version bump. |

Record P1 findings in `spec/prayer-times/README.md`. Include the method parameters Adhan uses for Isha, which the PWA never computed. Also record the default high-latitude rule. Slice 3 confirmed Adhan's `.twilightAngle` as the closest rule and the default; see `spec/prayer-times/README.md`.

### 7.3 Feature surface (1.0)

- Show six times for today, previous/next-day navigation, a countdown to the next prayer, and today's schedule on the Today tab.
- Let users configure the calculation method, Asr school, high-latitude rule, per-prayer minute adjustments, and Hijri offset. Include the five methods the PWA offers and any additional Adhan methods. List the five PWA methods first as defaults, using the same Arabic labels as the current settings dialog.
- Show which location and zone produced the schedule and when the location was last updated. The PWA already stores `location.updatedAt`.

### 7.4 Location and privacy

- Request one-shot location access with `CLLocationManager`. Tolerate `.reducedAccuracy`, use when-in-use access only, and request access only when the user taps تحديد الموقع (the PWA button) or enables a reminder without a location (`setReminderEnabled` behaviour today).
- Round stored coordinates to **two decimals** (≈1 km) before persistence. The PWA rounds to four (`toFixed(4)`, ≈11 m). Two-decimal rounding changes prayer times by seconds at most and identifies users less precisely. Use rounded coordinates in parity vectors so the gate reflects what ships.
- Accept manual coordinates when users deny location. Use the device's current time zone in 1.0.
- Do not access location in the background or store it off-device. Exclude it from backup unless the user opts in during export.

### 7.5 One notification planner for prayers and adhkar

`ReminderPlanner` is a pure Swift function: `(now, zone, schedule for horizon, rules, completion/log state, last-shown state) → [PlannedNotification{id, fireAt, category, payload}]`.

- Use stable IDs: `adhkar.morning.<local_date>`, `adhkar.evening.<local_date>`, `prayer.<key>.<local_date>`, and `personal.<rule_id>.<local_date>`.
- Schedule adhkar relative to prayers with the same offsets as today (`fajr + 60`, `asr + 60`), so no special case is needed. Use the current body copy: "مرّت ساعة على صلاة الفجر. حان وقت أذكار الصباح."
- Do not plan an adhkar notification for a completed period (`periodIsComplete` logic) or a prayer notification for an occurrence already marked `prayed` or `not_applicable`.
- If a rule's instant was up to 15 minutes ago and it has not been shown today, plan it for "now" (from `nextReminderTime`).
- iOS caps pending local notifications at 64. Seven rules per day (five prayers and two adhkar) over a **7-day horizon** use 49 requests, leaving headroom for personal rules. Give the planner a budget and have it truncate furthest-first. The diagnostics screen shows planned and pending counts.
- Replan on foreground, `significantTimeChangeNotification`, `NSSystemTimeZoneDidChange`, any settings/rule/location change, any completion or log write, import, day change, and an opportunistic `BGAppRefreshTask`. To replan, compute the desired set, compare it with `UNUserNotificationCenter.pendingNotificationRequests`, and add or remove requests by ID. The operation is idempotent by construction.
- Prayer notifications carry a "سجّل الصلاة" action that writes the same idempotent command as the tracker screen. Adhkar notifications open the deck (deep link `#morning`/`#evening`).
- Settings copy states that reminders beyond the horizon require the app to have been opened, replacing the PWA's current disclosure.

Capture all of these requirements in fixtures under `spec/reminders/fixtures/` before implementation (section 4.3).

---

## 8. iOS delivery plan

### 8.1 Hard prerequisite gate: organization publisher identity

Section 20 of `MOBILE_APP_PLAN.md` is authoritative and is restated here, not summarised. Until the following conditions are met, there must be **no App Store Connect app record, no TestFlight upload, and no bundle ID reservation for the product**:

- An Apple Developer Program **organization** membership exists (or an individual membership has been converted), with the legal entity, D-U-N-S, domain, and domain email in place.
- The public developer name has been chosen deliberately at first-app creation.
- The final Team ID is known and recorded privately, so no Keychain-scoped secret is created under a throwaway team.

This plan also requires macOS hardware or a hosted Mac running current Xcode and a physical iPhone for notification testing. Simulators do not faithfully exercise delivery after termination.

Slices 0–4 do **not** require the account. Run them on the simulator and local device builds signed with a free personal team. The gate blocks Slice 5 onward.

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

`AthkarCore` is a local SwiftPM package. This lets tests exercise the domain without launching the app. The compiler enforces the package boundary, which excludes platform UI.

### 8.3 Slices in build order

Each slice ends with an observable exit criterion. Section 10.1 defines the effort bands.

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

- Test on the maintainer's own iPhone(s) and, if available, one older device. Distribute each archive automatically.
- Recruit a small named group from existing PWA users for external testing. This group also provides S4. Apple must review each external build train. Submit the build early so review delays do not delay the schedule.
- Every TestFlight build carries the diagnostics screen, so testers can report planned/pending notification counts and content version without screenshots of worship data.
- Do not add a crash SDK. Use Xcode Organizer crash logs from opted-in users and TestFlight feedback (`MOBILE_APP_PLAN.md` §15 posture).

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

Defer all Android UI, `adhan-kotlin` integration, Room/SQLDelight persistence, `AlarmManager`/exact-alarm policy work, boot/time-change receivers, Glance widgets, Play Console setup, and the Data Safety form. Retain the `MOBILE_APP_PLAN.md` §9 Android subsection and §17 Android device tests as the spec for that work.

### 9.2 What is designed now so Android is not a rewrite

Android uses everything in section 4.1's table, plus:

- Keep the iOS `AthkarCore` package free of UIKit/SwiftUI/CoreLocation/UserNotifications dependencies. The package's lack of these dependencies enforces the rule. Its public types are the de facto Kotlin interface list.
- Update `spec/schema.md` with every GRDB migration. Android implements the *final* schema when its work starts and imports every envelope version iOS has ever exported.
- Describe the deck definition format (which deck, which items, counter semantics, long-order eligibility) in `spec/sessions/deck-definition.md`. Build Compose's `DeckScreen` from that same description.
- Seed the Arabic UI String Catalog from `content/ui-copy.json`. Add new keys to the JSON first, then generate Android's `strings.xml` from the same file.
- Use the route table in `spec/routes.md` for iOS deep links and quick actions. Map it to intent filters and shortcuts on Android.

### 9.3 Triggers to start Android

Start Android only when all criteria in section 1.4 (S1–S7) are met and at least one of these conditions holds:

- T1: PWA usage from Android user agents is a meaningful share of PWA traffic, read from the PWA's anonymous page-load counter (decision 11.10).
- T2: a content or rule change is being held back on the PWA side because keeping PWA and iOS behaviourally aligned has become the dominant maintenance cost.

Revisit the KMP rejection (section 4.2) only when Android starts and `AthkarCore` has exceeded roughly 3 000 lines of domain logic that fixtures alone struggle to pin. Below that, a direct Kotlin port against the fixtures remains cheaper.

---

## 10. Risks and effort

### 10.1 Effort bands

These bands estimate one maintainer's focused work with AI assistance, not elapsed time:

| Band | Meaning |
| --- | --- |
| S | Up to about 15 hours |
| M | About 15–40 hours |
| L | About 40–100 hours |
| XL | More than 100 hours |

Section 8.3 has two S slices, four M slices, and three L slices. The honest estimate for iOS 1.0 is in the **XL range, plausibly 250–400 hours of focused work**. Slices 4–6 dominate the estimate because they cover deck UI fidelity, the tracker, and notifications. Physical-device testing also takes time that AI assistance cannot shorten. First-time Swift/SwiftUI learning adds time if the maintainer has not shipped SwiftUI before `[INFERENCE: prior Swift experience is unknown]`. Android later adds another L–XL, but should take less time than iOS because the spec and fixtures already exist.

AI token costs are highest in phases with long feedback loops, such as SwiftUI layout for auto-fit Arabic cards and notification edge cases. Fixture-first ordering, with Slice 0 before UI work, helps keep later prompts short and verifiable.

### 10.2 Risk table (additions to `MOBILE_APP_PLAN.md` §21)

| Risk | Consequence | Mitigation |
| --- | --- | --- |
| Identity gate stalls (no legal entity, D-U-N-S delays) | Slices 5–9 blocked; work continues on 2–4 but cannot ship. | Start the gate before Slice 0; it has no code dependency. |
| No Mac / Xcode access | iOS cannot start at all. | Prerequisite in section 11. |
| Dropping the PWAs too early | Android users and non-App-Store iOS users lose the only working app; ruqyah users lose their history if they never exported. | Section 10.4 policy; PWAs are never removed before Android ships; export stays available indefinitely. |
| Maintaining PWA + iOS + Android simultaneously | Three codebases for one person; every content fix triples. | PWAs in maintenance mode with regenerated content (`content-export-pwa.mjs`) so a pack fix is one commit; Android only after S6 shows the iOS load has dropped. |
| Silent divergence between PWA and native rules during the long overlap | Users see different completion or reminder behaviour in the PWA and native app. | Freeze PWA rule changes (10.4). Any exception must first update the fixtures, which requires the native side to follow. |
| Quran text regression during extraction | Worst-case product failure. | Slice 0 regenerates `content.js` byte-identically and compares every Quran item to two references before any native code. |
| Adhan preset mismatch with PWA angles | Prayer times shift for existing reminder users. | P1 parity gate with written exceptions; release note if any material shift is accepted. |
| iOS 64-request budget exceeded by personal reminders | Later notifications silently dropped. | Planner budget truncation and diagnostics count in 1.0, before personal reminders exist. |
| SwiftUI auto-fit for scroll-free Quran pages harder than CSS | Ruqyah cards scroll or clip. | Slice 4 exit criterion includes all 15 ruqyah segments fitting at three text sizes on the smallest supported device; fallback is a per-segment minimum size stored in the pack. |
| Solo-maintainer burnout | Project stalls mid-slice. | Slices are independently shippable to TestFlight from Slice 5 on; nothing is half-built across slices. |

### 10.3 What would falsify this plan

- Reject this plan if Slice 3 shows that Adhan cannot reproduce the PWA's Fajr within tolerance in the launch regions and no documented rule explains the difference. In that case, extend `solarDay` into a hand-ported engine that also computes Isha/Maghrib, then regenerate the vectors.
- If Slice 4 shows that SwiftUI cannot fit ruqyah pages without scrolling on the smallest supported device with large text, add per-segment layout hints to the pack or drop the smallest device from support.
- If the identity gate proves impossible because no qualifying entity can be formed, iOS distribution is delayed or shipped under a personal seller name, against the advice in `MOBILE_APP_PLAN.md` §20. An Android-first sequence would then be reconsidered, since Play does not impose the same seller-name constraint `[INFERENCE]`.

### 10.4 Interim policy for the two live PWAs

This policy takes effect at the end of Slice 1:

| Allowed | Not allowed |
| --- | --- |
| Bug fixes that do not change stored-state semantics | New features, new storage keys, new tabs |
| Content fixes, applied to `content/` and regenerated into the PWA by `content-export-pwa.mjs` | Hand-editing `content.js` or the inline arrays in `index.html` |
| The export feature (Slice 1) and, at 1.0, the iOS install banner | Import into the PWA (native is the destination, not the PWA) |
| `sw.js` cache-name bumps to deliver the above | Any change to `normalizeState`, `rollStateToDate`, `buildDeck`, `prayerTimesForDate`, `nextReminderTime` unless the corresponding fixture is updated first |

**Owner-approved exceptions (2026-10-04).** The owner approved additions to the live PWAs that fall in the "not allowed" column. In athkar, the exceptions are the «سور» tab (`athkar-suwar-v1`, shipped 2026-10-02) and the «مسبحة» tab (`#tasbih`, `athkar-tasbih-v1`, shipped 2026-10-04). In ruqyah, the exception is one tab per sura (shipped 2026-10-03), using `ruqyah-suwar-v1` and an IndexedDB database named `ruqyah`. The database has an object store named `state`, with `daily` and `suwar` records. Backup envelope v1 does not carry the per-sura or tasbih state: `athkar-suwar-v1`, `athkar-tasbih-v1`, `ruqyah-suwar-v1`, or the `suwar` record. The `daily` record has the shape of `ruqyah-daily-v1` and is exported as before.

**Owner-approved exception: transfer import (2026-10-05).** The owner allowed import into the PWAs for one purpose only: moving progress between copies of the same PWA (for example Safari and the Home Screen app, or phone and iPad). It is the offline transfer code of [`spec/transfer/transfer-v1.md`](spec/transfer/transfer-v1.md): copied text, a file or animated QR frames, with no server, relay or WebRTC. The receiving PWA validates the code, shows a preview, and merges it with idempotent joins under reset epochs, which the three athkar stores now record in a `resets` field. It may also read an envelope-v1 `.athkarbackup` file for its adhkar part. Any other import into the PWAs remains "not allowed". The native app stays the destination for backups.

The athkar PWA's ruqyah launcher tab remains unchanged. `MOBILE_APP_PLAN.md` and this document are linked from the athkar README; the ruqyah README gains one line pointing here.

---

## 11. Open decisions before implementation

1. **Legal entity and Apple identity.** Which entity will hold the organization membership, its public developer name, the support/privacy domain, and who is Account Holder. Nothing in Slice 5+ can ship without this (section 8.1).
2. **Mac access.** Owned Mac, hosted Mac, or other; and which physical iPhone(s) are available for the notification matrix.
3. **Minimum iOS version.** Recommendation: iOS 17, for SwiftUI maturity and `@Observable`; lower only if a known user base demands it.
4. **Scope trim approval.** Confirm the 1.0 / 1.1 split in section 3.3, in particular moving travel/make-up/not-applicable ranges, search, favorites and personal reminders to 1.1.
5. **Named reviewers.** Who signs `REVIEW.md` for the adhkar pack, the ruqyah pack, and the tracker wording in `content/ui-copy.json`. Without a name the packs cannot version-bump.
6. **Launch regions and authority tables.** Which regions' published tables are the P2 reference, and which method is the default for a fresh install (the PWA defaults to `mwl`).
7. **Product name and English metadata.** The PWA titles itself "أذكار المسلم" (document title in `selectTab`); confirm the App Store name and whether English store metadata is provided at launch.
8. **Quran edition policy for adhkar items.** Keep the simplified rasm for `ayatAlKursi`, `alIkhlas`, `alFalaq`, `anNas`, `comprehensiveDua` and verify against a matching reference, or migrate them to the same Uthmani edition as ruqyah. Recommendation: keep as shipped for 1.0, record the edition in the pack, and treat unification as a reviewed content change later. **Decided 2026-09-28:** migrated to the Uthmani edition (adhkar 1.1.0, REVIEW.md R6), set in KFGQPC HAFS like the ruqyah; the validator now requires it.
9. **Fate of the ruqyah PWA after Android ships.** Keep live indefinitely, or convert to a redirect page with export instructions. Recommendation: keep live; the maintenance cost is near zero once content is regenerated from the pack.
10. **How Android demand will be judged.** **Decided 2026-10-03:** the **PWA** counts page loads on a self-hosted GoatCounter on the developer's own server (`https://count.aloqaili.xyz`), and its browser/OS breakdown judges trigger T1. An inline beacon (no remote script) sends one `GET /count?p=%2F&s=<screen width 0–99999>&b=<bot code>&rnd=<random>` per page load, with no referrer, no cookies, no title, query, hash, tab or sura, and no `localStorage` read except the `skipgc` opt-out flag. The server receives the IP address and user agent transiently and keeps aggregates (browser/OS, screen width, country); the relay keeps no access log. Exception: requests GoatCounter classifies as bots keep their raw user agent for filtering until a server maintenance job purges them hourly, normally within about an hour; the job is best-effort, not a hard bound, and GoatCounter's own ~30-day cleanup is the fallback if it fails. The PWA's Settings discloses it; details in `MOBILE_APP_PLAN.md` §15. The native app ships no counter, and its "no data collected" privacy label and release gate (section 8.5, `MOBILE_APP_PLAN.md` §15) are unchanged.
11. **Location rounding.** Confirm two decimals (section 7.4) versus the PWA's four.
12. **Backup encryption.** Whether iOS 1.0 ships plaintext-only export (with the location exclusion default) and defers the passphrase envelope to 1.1, as this plan recommends.
