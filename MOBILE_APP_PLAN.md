# Athkar Native iOS and Android Plan

## Status

This document defines the proposed product, domain, architecture, delivery, and release plan for a native iOS and Android edition of Athkar. It is a plan, not a claim that the native app is already implemented.

## 1. Product outcome

Build an Arabic-first, offline-first mobile companion that combines:

- The existing morning and evening adhkar experience without regressions.
- A complete, private five-prayer tracker.
- Reliable native prayer and adhkar reminders.
- Prayer times, a monthly calendar, search, favorites, backup/import, quick actions, optional audio, and personal reminders.
- Native system integration through notifications, widgets, deep links, accessibility, and store distribution.

The app should help a person remember and record worship without judging, ranking, or broadcasting it.

### Definition of a complete public release

A release is complete only when it:

1. Preserves every current PWA workflow on both platforms.
2. Works offline after installation, including prayer calculations and logging.
3. Handles time zones, daylight-saving changes, travel, app termination, reboot, and permission changes.
4. Never converts an unrecorded prayer into a claim that it was missed.
5. Stores worship data locally by default and sends none of it to a server.
6. Meets the Arabic RTL, accessibility, migration, notification, content-review, and store gates in this plan.

## 2. Product principles

1. **Arabic first and RTL first.** Arabic is the launch language; layout is designed in RTL rather than mirrored as an afterthought.
2. **Local first.** Reading, counting, prayer calculations, tracking, history, search, and reminders work without an account or network.
3. **Private by default.** Prayer logs, exemptions, location, favorites, and history stay on the device unless the user explicitly exports them.
4. **Record, do not judge.** No leaderboards, public sharing, guilt copy, red “failed day” treatment, or competitive streaks.
5. **Verified content.** Quran text, adhkar, sources, audio, and prayer-calculation parameters have named provenance and review.
6. **User-selected religious settings.** The app exposes calculation methods and recording options but does not issue rulings.
7. **Reliable but honest reminders.** Use native scheduling and clearly disclose platform or permission limitations instead of promising impossible precision.
8. **No account required.** Optional synchronization must never become a prerequisite for core features.
9. **One domain model.** The PWA and mobile app share content schemas, backup format, and pure TypeScript rules wherever practical.

## 3. Current PWA baseline that must survive

The native app must preserve these existing behaviors:

- 25 morning cards and 23 evening cards, including Quran styling, details, source notes, configurable targets, and the existing review-card mechanism.
- Tap counting, per-item reset, whole-session reset, previous/next controls, touch swipe, auto-advance, and first-incomplete resume.
- Completion by counters or by “completed outside the app.” Manual completion leaves counters untouched and allows free browsing.
- Completion dialog, completion time, switching between morning and evening, and reminder suppression after completion.
- Local midnight rollover and the existing seven-day history, migrated into an unbounded history store.
- Fajr-relative morning reminder and Asr-relative evening reminder, current calculation methods, Asr school selection, location, and the 15-minute catch-up rule.
- Theme, text size, line spacing, haptics, reduced motion, sources/details, Arabic accessibility announcements, and offline use.
- Morning and evening launch shortcuts and notification deep links.

The native app improves the PWA’s current limitation that reminder timers are dependable only while the page is open.

## 4. Scope and release boundaries

### Public 1.0: complete core

- Full PWA parity.
- Today dashboard with next prayer, today’s five prayers, and morning/evening completion.
- Prayer-times screen: Fajr, sunrise, Dhuhr, Asr, Maghrib, and Isha, plus next-prayer countdown.
- Five-prayer tracker with editing, undo, Friday handling, travel/combining/shortening options, single-occurrence make-up linking, and a neutral not-applicable state.
- Prayer and adhkar local notifications with completion suppression.
- Quick card index, Arabic search, favorites, monthly calendar, backup/import, home-screen quick actions, and personal reminders.
- Manual city/location entry, calculation method, Asr school, high-latitude rule, per-prayer adjustment, and Hijri date display.
- Privacy controls, delete-all, local diagnostics, PWA-to-native migration, and store compliance.

### 1.1: rich native experience

- iOS WidgetKit and Android Glance widgets.
- Qibla direction with a numeric fallback when a compass is unavailable.
- Optional verified audio packs.
- Optional Sunnah, Witr, Duha, Qiyam, and Tarawih tracking.
- Bulk make-up ledger for users who explicitly enable it.
- Ramadan mode, fasting log, suhoor/iftar reminders, and Hijri event notes.
- Passphrase-encrypted backups and optional biometric app lock.
- English interface while preserving Arabic source text.

### 2.0: optional connected features

- End-to-end encrypted cross-device synchronization if user demand justifies it.
- Watch complications or wearable quick logging.
- Signed downloadable content packs after the bundled-content pipeline is proven.

### Explicitly out of scope unless separately approved

- A full Quran reader, tafsir platform, or all-occasion Hisn al-Muslim library.
- Social feeds, public worship sharing, leaderboards, badges, points, or competitive streaks.
- Advertising, tracking SDKs, background location, mosque maps, or an account requirement.
- Automatic religious judgments based on notification taps, location, motion, or timestamps.

## 5. Information architecture

### Today

- Current date in Gregorian and Hijri calendars.
- Next prayer and countdown.
- Five prayer rows with quick logging and an edit affordance.
- Morning and evening adhkar status and direct entry.
- Non-blocking notices for stale location, denied notification access, or schedule problems.

### Prayer times

- Six daily times: Fajr, sunrise, Dhuhr, Asr, Maghrib, and Isha.
- Calculation profile, location, time zone, adjustments, and fallback indicator.
- Previous/next day navigation and monthly view.
- Qibla entry point when that module is installed.

### Prayer tracker

- Today’s five obligatory prayer occurrences.
- Tap to record; detail sheet for timing and optional context.
- Calendar/history editing for previous dates.
- Optional travel, make-up, Sunnah, and exemption tools.

### Athkar

- Morning and evening decks with current behavior.
- Quick index, search, favorites, source details, audio when installed, and progress/history.

### Calendar and insights

- Month grid showing prayer and morning/evening completion without a “failed” state.
- Day detail with edit and undo.
- Plain counts and patterns only; no public scores or competitive presentation.

### Data and settings

- Reading and appearance.
- Location, time zone, calculation method, Asr school, high-latitude handling, and Hijri offset.
- Prayer, adhkar, and custom reminders.
- Optional tracker fields and modules.
- Export, import, privacy, diagnostics, delete-all, sources, licenses, and content version.

## 6. Prayer tracker domain

### 6.1 Prayer occurrence identity

A prayer occurrence has one stable identity in 1.0:

- Calculation date.
- Prayer key: `fajr`, `dhuhr`, `asr`, `maghrib`, or `isha`.

The IANA time zone, scheduled UTC instant, and calculation-profile version are immutable metadata captured when the row is first created; they are not part of its identity. There is one row per calculation date and prayer key even if the device changes zones that day. Crossing the date line and repeating a civil date therefore reuses that row in 1.0, while the UI preserves and displays the zone in which it was recorded.

Changing a method later must not move, duplicate, or silently recalculate a historical log.

### 6.2 Recording state

Use a small neutral core state:

- `unrecorded`: default; never rendered as “missed.”
- `prayed`: recorded by the user.
- `not_applicable`: explicitly selected by the user for a prayer or date range.

A `prayed` row may have an optional user-selected timing value:

- `on_time`
- `late`
- `made_up`

The app must not derive those labels from the clock. The user supplies them, and wording receives content review before release.

Optional modifiers are separate fields rather than new completion states:

- Congregation or mosque.
- Combined with previous/next.
- Shortened while traveling.
- User note, disabled by default.
- Entry source: app, notification action, widget, import, or migration.

### 6.3 Primary workflows

- **Quick log:** tap a prayer row to record it; show an undo action immediately.
- **Details:** open a sheet to choose timing and optional modifiers.
- **Correction:** every value can be edited or cleared later; clear-day requires confirmation.
- **Past days:** calendar day detail supports the same controls as today.
- **Notification action:** “record as prayed” writes the same domain command as the app screen and is idempotent.
- **No automatic completion:** receiving or opening a notification never marks a prayer by itself.

### 6.4 Friday

On Friday, the Dhuhr occurrence may be displayed as a Jumu’ah/Dhuhr choice. The user records which one they performed; the app does not infer eligibility or require demographic information. Both choices are recorded in the single noon-prayer slot rather than creating two required rows.

### 6.5 Travel, combining, and shortening

- Travel mode is manually enabled for today or a selected date range.
- Available combining pairs and shortening rows come from a named-reviewer-approved, versioned rule set rather than hard-coded product assumptions.
- The app surfaces only options in that reviewed rule set and never applies them automatically.
- A neutral explanation tells users to follow their own trusted scholarly guidance.
- Changing travel mode never rewrites existing records without an explicit confirmation.

### 6.6 Not-applicable ranges and sensitive details

- A user may mark a prayer or date range not applicable without providing a reason.
- Optional reasons remain local, are omitted from diagnostics, and are excluded from backups unless explicitly included.
- The app does not require gender, health information, or an explanation.
- These rows are excluded from completion denominators rather than counted negatively.

### 6.7 Make-up tracking

- Entirely opt-in.
- The app never turns old `unrecorded` rows into a make-up debt.
- A user can select a historical occurrence and link a later `made_up` record to it.
- Undoing the later record restores the original state.
- A bulk make-up ledger is a 1.1 feature and requires content review.

### 6.8 Optional prayers

Sunnah, Witr, Duha, Qiyam, and Tarawih are separate optional modules. They never change obligatory-prayer completion and are absent until enabled.

### 6.9 Date, midnight, and travel rules

- Athkar sessions continue to reset at local civil midnight.
- Prayer records stay attached to their original occurrence even when recorded after midnight.
- The previous day’s Isha is always reachable through day navigation, without the app making a claim about its validity window.
- Time-zone changes create new local schedule context; existing records are never shifted or deleted.
- A backward device-clock change triggers a quiet warning and must not discard history.

## 7. The eight README features

| Feature | Release | Product contract |
| --- | --- | --- |
| Quick card index | 1.0 | Open any card in at most two taps; show number, opening text, and count/target; announce the destination to screen readers. |
| Search | 1.0 | Search both collections with a display-safe Arabic index that ignores tashkeel, tatweel, and common Alef/Hamza variants without modifying shown text. |
| Favorites | 1.0 | Personal reading list with no independent completion requirement; persists, exports, and supports undo on removal. |
| Monthly completion calendar | 1.0 | Unbounded local history; month grid and day detail for prayers and both adhkar periods; no shame copy or competitive streak. |
| Backup and import | 1.0 | Versioned, validated file with preview and merge/replace; malformed or newer formats fail safely; location and sensitive details excluded by default. |
| Optional audio | 1.1 | Verified per-dhikr audio, explicit download, offline cache, reciter/license attribution, no autoplay, and independent repeat controls. |
| Home-screen quick actions | 1.0 | Morning, evening, and log-prayer actions cold-start into the exact destination. |
| Personal reminders | 1.0 | Fixed local times and adjustable prayer-relative offsets, weekday selection, deduplication, completion suppression, and replanning when the platform permits or on next launch; the iOS terminated-state limitation is disclosed. |

## 8. Prayer calculations, location, and Hijri dates

### Calculation boundary

Adopt the MIT-licensed [Adhan JS](https://github.com/batoulapps/adhan-js) library behind a project-owned `PrayerTimesPort`, pinning and auditing the selected version. Keep the current solar implementation only as a parity oracle during migration.

The port returns UTC instants plus the IANA zone for:

- Fajr
- Sunrise
- Dhuhr
- Asr
- Maghrib
- Isha
- Optional middle-of-night and last-third values
- Qibla bearing through the same reviewed adapter

### User configuration

- Calculation method with documented parameters.
- Asr school.
- High-latitude rule.
- Per-prayer minute adjustments.
- Hijri date offset of up to two days for local moon-sighting differences.
- Location profile and IANA time zone.

### Location policy

- Request only when the user asks for current-location calculations.
- Use one-shot, when-in-use location; never background-track.
- Round stored coordinates and keep them on device.
- Offer an offline city list and manual coordinates when permission is denied.
- Pair automatic current location with the device’s current IANA zone; manual cities carry their own zone and allow override.
- Display which location and time zone produced the schedule and when it was last updated.

### Correctness gate

Before replacing the existing engine, compare:

- Current PWA output versus Adhan output across at least 30 locations and 12 dates.
- Published authority tables for representative launch regions.
- Equatorial, high-latitude, southern-hemisphere, daylight-saving, and polar-edge cases.

Any material time shift requires an explicit product/content sign-off and release note.

## 9. Native reminders

### Reminder planner

A pure deterministic planner receives current time, location profile, time zone, calculation settings, completion/log state, reminder rules, and a scheduling horizon. It outputs stable notification IDs and UTC trigger instants.

Replan after:

- App foreground or update.
- Location, time zone, clock, method, offset, or reminder-setting change.
- Prayer or adhkar completion.
- Import, restore, or day rollover.
- Android reboot, package replacement, and exact-alarm permission change.

Completion cancels the pending notification immediately. Replanning with the same input is idempotent and cannot duplicate a notification.

### iOS

- Schedule local calendar/date notifications through `UNUserNotificationCenter` via Expo Notifications.
- Pre-schedule a rolling horizon so delivery does not require the app to be running.
- Enforce a configurable pending-request budget validated during the platform spike.
- Use background refresh only as an opportunistic refresh, never as the sole scheduling mechanism.
- Explain that reminders can lapse if the app remains unopened beyond the scheduled horizon.
- While the app is terminated, iOS may not provide a timely time-zone or manual-clock-change callback. Recalculate on the next launch/foreground and disclose that already scheduled reminders may retain the old zone until then.

Apple documents system delivery while an app is not running and provides an API for removing pending requests; Athkar uses that cancellation API after completion: [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

### Android

- Use notification channels for prayer, adhkar, and custom reminders.
- Use inexact alarms by default where acceptable.
- Evaluate user-granted exact-alarm access because prayer reminders are core, but complete the Google Play policy review before requesting it.
- Android 14 and later do not pregrant `SCHEDULE_EXACT_ALARM` to fresh installs, and `USE_EXACT_ALARM` is restricted by Google Play to qualifying alarm/calendar use cases. Exact mode remains conditional on policy approval and granted access.
- If exact access is unavailable, show the user that delivery may be delayed and use the supported inexact fallback.
- Reschedule from receivers for reboot, time change, time-zone change, package replacement, and permission change.
- Do not run a permanent background service or poll location.

Android’s official guidance explains the battery and permission tradeoffs for exact alarms: [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms).

### Notification behavior

- Permission is requested only after the user enables a reminder.
- Notification actions may open the exact prayer/wird or record a prayer with undo available on next app open.
- Adhkar reminders retain the existing 15-minute foreground catch-up behavior.
- Optional sound respects silent and focus modes; no claim that a full adhan can bypass platform restrictions.
- Diagnostics show planned, pending, delivered, opened, and cancelled IDs without storing worship text or precise location.

## 10. Recommended architecture

### Stack decision

Use **React Native, TypeScript, Expo Router, and Expo Continuous Native Generation/prebuild**, with small native Swift/Kotlin targets where platform APIs require them.

Why this is the default:

- Existing JavaScript domain rules and content can be migrated to typed shared packages.
- The PWA and native app can share content, backup schemas, search normalization, and pure scheduling rules.
- Expo provides maintained iOS/Android notification and SQLite APIs while prebuild permits native widgets, receivers, and configuration plugins.
- It avoids maintaining two complete native UIs for a small team.

Do not use Expo Go as the production architecture; widgets, boot receivers, and alarm configuration require development builds/prebuild.

### Architecture falsifiers

Run a native spike before committing. Switch the recommendation if:

- Uthman Taha text has unacceptable shaping or diacritic defects in React Native on representative Android devices and Flutter passes the same visual corpus.
- The selected notification layer cannot preserve multi-day scheduled notifications while the app is terminated, even with a thin native scheduler.
- The project intentionally retires the PWA, removing the primary shared-TypeScript advantage.

### Proposed repository shape

Keep the current root PWA deployable during migration.

```text
mobile/                 React Native/Expo application
packages/domain/        Pure TypeScript rules; no React Native imports
packages/content/       Versioned Arabic content packs and schemas
packages/backup/        Shared export/import envelope and migrations
packages/platform/      Native-facing TypeScript ports
native-plugins/         Config plugins, iOS widget, Android widget/receivers
tools/                  Content validation, parity fixtures, release scripts
```

Only move the PWA under `apps/pwa` after GitHub Pages and migration tooling are proven from the new layout.

### Module seams

- `content`: pack validation, Arabic search index, sources, favorites, and audio metadata.
- `sessions`: counters, targets, manual completion, rollover, and history.
- `prayer-times`: `PrayerTimesPort`, Adhan adapter, profiles, time zones, and Qibla.
- `prayer-tracker`: occurrence identity, status transitions, travel options, undo, and calendar queries.
- `reminders`: pure planner plus platform scheduler adapters.
- `backup`: versioned envelope, validation, encryption, merge, and PWA migration.
- `data`: SQLite migrations and repositories.
- `platform`: location, notifications, widgets, deep links, quick actions, haptics, secure storage, and diagnostics.
- `app`: screens, navigation, Arabic design system, and accessibility.

Domain packages must not import React Native or platform SDKs. Platform adapters implement explicit interfaces so time calculations, reminder planning, migration, and tracker transitions can be tested without a device.

## 11. Persistence and data model

Use SQLite in WAL mode with forward-only numbered migrations. Secure keys belong in Keychain/Keystore, not the database.

### Core tables

- `settings(key, value_json, updated_at)`
- `location_profiles(id, label, latitude, longitude, zone_id, source, updated_at)`
- `calculation_profiles(id, method, asr_school, high_latitude_rule, adjustments_json, version)`
- `content_packs(id, version, language, checksum, installed_at, source)`
- `day_sessions(local_date, zone_id, period, pack_version, completed_at, completion_origin)`
- `item_progress(local_date, period, item_id, count, target, updated_at)`
- `favorites(item_slug, added_at)`
- `prayer_logs(id, calculation_date, prayer_key, zone_id, scheduled_at_utc, profile_version, state, timing, linked_occurrence_id, modifiers_json, logged_at, updated_at)`
- `not_applicable_ranges(id, prayer_key, starts_on, ends_on, reason, created_at)` where a null prayer key applies to every prayer in the range
- `optional_practices(local_date, practice_key, state, updated_at)`
- `reminder_rules(id, kind, prayer_key, offset_minutes, local_time, weekday_mask, sound, enabled, updated_at)`
- `notification_audit(plan_id, scheduled_for, scheduled_at, delivered_at, opened_at, cancelled_at, cancelled_reason)`

### Data rules

- Existing `morning-NN` and `evening-NN` IDs remain stable for migration.
- Shared content receives a stable slug for search/favorites across pack versions.
- History is derived from persisted rows and is no longer capped at seven days.
- Prayer-log writes are idempotent under a unique index on `(calculation_date, prayer_key)`; scheduled time, zone, and profile are captured metadata.
- All mutable records carry `updated_at`; tombstones are added only when synchronization ships.
- The tracker never infers `not_applicable`, timing, travel, or congregation.

## 12. Content-pack system and governance

Extract inline content into a versioned bundled Arabic pack containing:

- Stable slug and collection-specific ID.
- Quran/dhikr kind, Arabic text, prefix, details, count, target options, and label.
- Structured sources: collection/book, reference number, grading, grader, and scholarly note.
- Review state that can exclude an item from completion.
- Optional audio metadata: file, hash, reciter, license, and reviewer approval.

Launch packs are bundled and work offline. Remote packs are deferred until signature verification and rollback exist.

Every content change requires:

1. Schema validation.
2. Character-for-character Quran text verification against an approved source.
3. Named content-review approval.
4. A content-version bump and content changelog.
5. A migration test proving favorites and history retain stable references.

The app’s About screen shows content version, sources, calculation parameters, licenses, and the recording-not-ruling disclaimer.

## 13. Backup, migration, and optional sync

### Shared backup envelope

A versioned envelope includes:

- Export format and app/content versions.
- Settings and calculation profiles.
- Athkar sessions, counters, targets, and manual completion.
- Prayer logs and optional-practice rows.
- Favorites and reminder rules.
- Explicit inclusion flags for location and sensitive optional reasons.
- Checksums and encryption metadata.

Import always validates before writing and shows:

- Date range and record counts.
- Included sensitive categories.
- Merge versus replace.
- Conflicts and unsupported future versions.

Malformed input must never partially modify the database. Import runs in one transaction after a restorable pre-import snapshot.

### PWA migration

Native applications cannot read the PWA’s localStorage sandbox. Migration therefore requires:

1. Add export/import to the PWA using the shared envelope.
2. Offer “Import from the web app” during native onboarding and later in settings.
3. Accept a file through the document picker/share sheet; a custom deep link may be an optional convenience for non-sensitive payloads.
4. Map current progress, targets, manual completion, seven-day history, reminder preferences, theme, reading settings, and haptics. Location is included only when the user selects the same explicit location-inclusion option used by normal exports.
5. Compare a native re-export with the PWA export in an automated round-trip fixture.
6. Keep the PWA available through a documented migration window.

### Encryption and synchronization

- Encrypted export is the preferred format once an interoperable PWA/native crypto envelope passes review.
- Plain JSON remains an explicit portability option with a privacy warning and location excluded by default.
- If a user explicitly includes sensitive reasons in a plaintext export, show a separate warning that those values will be readable in clear text.
- System device backup may cover the app sandbox but is not treated as cross-platform synchronization.
- If sync ships, use an end-to-end encrypted blob or row protocol where the service cannot read worship data. Reevaluate both stores’ privacy declarations before release.
- No proprietary backend is required for 1.0.

## 14. Widgets, quick actions, and deep links

### 1.0 quick actions

- Morning adhkar.
- Evening adhkar.
- Log a prayer.

Each launches the precise route on a cold start.

### 1.1 widgets

- Small: next prayer and countdown.
- Medium: today’s five prayer states and both adhkar states.
- Optional dedicated adhkar widget.
- iOS uses WidgetKit; Android uses Jetpack Glance.
- Native extensions read a minimal shared snapshot, not the primary SQLite database.
- Widget data excludes history, notes, exemption reasons, and precise location.

### Deep links

Support routes for morning, evening, a specific card, a prayer occurrence, search, import, and reminder settings. Use the custom scheme as the guaranteed path. Universal/App Links require an early hosting spike for both Apple and Android association files.

## 15. Privacy and security

### Launch posture

- No ads, behavioral analytics, accounts, remote content, or third-party tracking.
- No worship or location data leaves the device during ordinary use.
- Location is one-shot, coarse enough for calculation, rounded before storage, and never collected in the background.
- Notification text contains no personal prayer history.
- Sensitive details are omitted from default export and redacted diagnostics.
- Delete-all is available in settings with deliberate confirmation.
- App-switcher privacy blur is enabled on sensitive tracker detail screens.

### Storage and secrets

- SQLite remains inside the app sandbox under platform data protection.
- A launch threat model decides whether platform data protection is sufficient or the full database uses SQLCipher; do not selectively encrypt only one worship field.
- Backup passphrases and encryption keys are never stored with backup ciphertext.
- Sync keys, if introduced, live in Keychain/Keystore and have a documented recovery decision.
- Dependency versions and checksums are locked; native permissions are minimized and reviewed per release.

### Store declarations

Apple requires privacy details for app and third-party SDK behavior, while Google requires a Data Safety form even for apps that collect nothing. Treat “no data collected/shared” as a release gate for 1.0 and reassess after adding crash reporting, remote audio, or sync.

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)

## 16. Accessibility and localization

- VoiceOver and TalkBack labels and announcements in Arabic for every status change.
- Dynamic Type/font scaling through at least 200% without clipped dhikr or controls.
- Preserve the bundled Uthman Taha Quran font and validate shaping/diacritics on physical Android devices.
- Minimum 44-point-equivalent touch targets.
- Color is never the only status signal; use text and glyphs.
- Full RTL treatment for navigation, calendars, progress, swipes, and chevrons.
- Reduced motion disables card and completion animations.
- Haptics can be disabled and never carry unique information.
- Gregorian and Hijri dates have clear labels; numeral style is configurable.
- English UI is post-launch; Quran and dhikr source text is never machine-translated.

## 17. Quality strategy

### Domain and calculation tests

- Current PWA behavior becomes golden fixtures before extraction.
- Prayer times across methods, cities, seasons, hemispheres, high latitudes, and DST boundaries.
- Reminder planning with a fake clock: deterministic IDs, horizon budget, completion cancellation, no duplicates, and catch-up behavior.
- Prayer tracker transition tests for undo, Friday choice, travel modifiers, not-applicable ranges, and import idempotence.
- Arabic search normalization without modifying displayed text.
- Backup round-trip, wrong passphrase, corruption, unsupported version, merge, replace, and rollback.
- Every SQLite migration against seeded previous-version databases.

### Device tests

- At least one current and one older iPhone.
- Pixel plus a low-memory Android device.
- At least one heavily battery-managed Android OEM device.
- Physical-device notification runs with app foregrounded, backgrounded, terminated, device idle, rebooted, time changed, and time zone changed.
- Offline first launch, permission denial, approximate location, no compass, and storage pressure.

### UI and accessibility tests

- RTL screenshots across light/dark, three text sizes, and three line spacings.
- VoiceOver/TalkBack scripted flows: log/undo prayer, complete a wird, change target, manual completion, search/jump, import backup, and change reminders.
- Large text, reduced motion, high contrast, long Arabic strings, and small screens.
- Widget and quick-action deep links from terminated state.

### Content checks

- Schema and unique-ID validation.
- Quran corpus checksum.
- Source and review metadata required for release content.
- Audio hash, text match, attribution, license, and offline playback.

## 18. Nonfunctional targets

- All 1.0 core features work in airplane mode after installation.
- No permanent background service and no background location polling.
- Cold start to an interactive Today/adhkar screen within 1.5 seconds on the agreed baseline Android device.
- Card tap response within 50 ms and smooth navigation at supported font sizes.
- No lost committed row after process termination.
- Notification planner never exceeds the validated platform request budget.
- When exact Android scheduling is both policy-approved and granted, target one-minute accuracy; fallback behavior is measured and disclosed rather than hidden.
- Crash-free sessions target at least 99.5% using Play vitals and the subset of App Store users who opted into analytics sharing; worship data is never attached to crash diagnostics.
- App without optional audio remains within a 30 MB download target.

## 19. Delivery phases and gates

### Gate 0: platform proof

Build a disposable React Native/Expo prototype that proves:

- Uthman Taha shaping and diacritics on representative iOS/Android devices.
- A 25-card RTL deck with accessibility-sized text.
- Adhan parity report against current PWA calculations.
- Multi-day local notifications while the app is terminated.
- Android reboot/time-zone rescheduling.
- One quick action and skeleton WidgetKit/Glance targets.
- A terminated-state notification action that records a prayer idempotently and exposes undo on the next launch.

**Exit:** font rendering is approved, notifications survive the physical-device run, and no architecture falsifier is triggered.

### Phase 1: shared foundation and migration

- Define content, domain, and backup schemas.
- Extract the current content into a validated pack without changing wording or order.
- Capture PWA parity fixtures.
- Add PWA export/import before native beta.
- Establish SQLite migrations and repository interfaces.

**Exit:** PWA export to native import round-trips with no semantic difference, and content checks pass.

### Phase 2: native PWA parity

- Native shell, navigation, design tokens, fonts, settings, and accessibility.
- Morning/evening decks, counters, targets, reset, completion, manual external completion, free browsing, history, source sheets, haptics, and offline assets.
- Quick index, search, favorites, and quick actions.

**Exit:** every baseline workflow passes on iOS and Android, including offline and accessibility scripts.

### Phase 3: prayer engine and tracker

- Full prayer-times screen, profiles, manual city, Hijri display, and calculation tests.
- Today dashboard and prayer occurrence model.
- Logging, edit/undo, Friday choice, travel options, not-applicable ranges, single-occurrence make-up links, and monthly calendar.

**Exit:** domain transition suite passes; prayer times meet approved reference tolerances; content/religious wording is signed off.

### Phase 4: reminder reliability

- Native scheduler adapters, rolling horizon, channels, actions, cancellation, Android receivers, permission flows, and diagnostics.
- Existing adhkar reminders, all five prayer reminders, and personal reminder rules.

**Exit:** physical-device notification matrix passes with zero duplicates and correct completion cancellation; fallback limitations are visible.

### Phase 5: privacy, release, and migration beta

- Backup/import UI, privacy screen, delete-all, store disclosures, diagnostics export, support copy, and PWA migration banner.
- TestFlight external and Play closed testing across regions, time zones, and OEMs.

**Exit:** migration, accessibility, privacy, content, crash, and notification release gates all pass.

### Phase 6: complete native suite

- Widgets, Qibla, optional audio, optional prayers, Ramadan mode, encrypted backups, biometric lock, and English UI.

**Exit:** each module has its own content, privacy, offline, accessibility, and platform-integration acceptance evidence.

### Phase 7: optional synchronization

Proceed only after a threat model and product decision confirm demand.

**Exit:** end-to-end encryption, conflict handling, deletion, recovery, privacy declarations, and cross-device tests are approved before public enablement.

## 20. CI/CD and release operations

### Continuous integration

- Type checking, unit tests, schema/content checks, dependency/license audit, and backup fixtures on every pull request.
- iOS and Android preview builds from the main branch.
- Production builds only from signed release tags.
- Pinned Expo/React Native versions and controlled upgrade branches.
- Reproducible build profiles and protected signing credentials.

### Distribution

- Apple Developer and Google Play accounts, final bundle/package identifiers, signing, support contact, and privacy-policy URL are prerequisites.
- Use TestFlight and Play internal/closed tracks before public rollout.
- Arabic RTL screenshots, store copy, age rating, permission explanations, privacy labels, Data Safety, exact-alarm declaration if used, export-compliance declarations for backup/sync cryptography, and third-party licenses are part of the release artifact.
- Roll out gradually with explicit halt criteria for crashes, data loss, reminder duplication, content errors, or migration failures.
- Keep the PWA live and supported until native migration is stable.

### Support and diagnostics

- A local diagnostics screen shows app/content/database versions, calculation profile, time zone, location age, pending notification count, and redacted scheduler events.
- Shared diagnostics never include prayer records, exemption details, free-text notes, or coordinates.
- Use App Store and Play vitals as passive health signals; any optional crash SDK requires opt-in and a fresh privacy review.

## 21. Major risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Religious text, grading, or wording error | Versioned content, named review, checksums, review-state exclusion, and visible content version. |
| Prayer-time shift during engine migration | Legacy/Adhan golden comparison, authority tables, explicit profiles, and product sign-off. |
| Missed or duplicate reminders | Deterministic planner, stable IDs, rolling horizon, completion cancellation, receivers, diagnostics, and physical-device runs. |
| Android exact-alarm policy or OEM battery restrictions | Policy gate, user-granted access, honest inexact fallback, and OEM-specific testing/help. |
| iOS cannot recompute indefinitely while terminated | Pre-scheduled horizon, opportunistic refresh, foreground replanning, and clear staleness disclosure. |
| Arabic font or RTL defects | Gate 0 physical-device visual corpus with Flutter as the fallback architecture. |
| Time-zone/DST/travel corruption | UTC instants plus IANA zones, immutable historical occurrence metadata, and edge-case tests. |
| Sensitive worship data exposure | Local-first design, no tracking SDK, redacted diagnostics, selective export, encryption, and delete-all. |
| PWA data cannot be read by native sandbox | Shared file export/import shipped in PWA first and automated round-trip fixtures. |
| Scope expansion delays a trustworthy core | Public 1.0 gate, modular 1.1 features, and explicit non-goals. |
| Audio text/license mismatch | Separate reviewed pack, hashes, named reciter/license, and no release without two-person verification. |
| Sync conflicts or key loss | Defer sync; threat model, row identity, tombstones, recovery decision, and E2E tests before enabling. |

## 22. Decisions required before implementation

1. Final app name, bundle identifiers, support address, privacy-policy host, and store accounts.
2. Named content/religious reviewers and the review record format.
3. Launch regions and their default calculation profiles.
4. Approved Arabic wording for timing, travel, Friday, not-applicable, and make-up states.
5. Minimum iOS/Android versions after the device-support review.
6. Android exact-alarm strategy and Play declaration.
7. Backup encryption format shared by Web Crypto and React Native.
8. Audio source, reciter, license, download hosting, and verification workflow.
9. Whether optional crash reporting is worth changing the no-data-collected posture.
10. Whether a custom domain will host universal/app-link association files.

## 23. Final launch acceptance checklist

- [ ] Every current PWA workflow passes on iOS and Android.
- [ ] All eight README features have shipped in their assigned release or are explicitly held for the named 1.1 gate.
- [ ] Prayer calculations pass approved golden and authority comparisons.
- [ ] Unrecorded prayers are never described as missed.
- [ ] Tracker edits, undo, Friday, travel, and not-applicable cases are reversible and tested.
- [ ] Adhkar and prayer reminders survive termination and cancel after completion.
- [ ] Time-zone, DST, reboot, clock-change, permission, and OEM battery cases are tested physically; iOS reschedule-on-launch limitations are verified and disclosed.
- [ ] PWA export imports into native with a semantic round-trip match.
- [ ] Core use works offline with no account and no network dependency.
- [ ] VoiceOver, TalkBack, large text, RTL, contrast, and reduced motion pass.
- [ ] Content and audio review records are complete.
- [ ] Privacy policy, Apple privacy details, Google Data Safety, permissions, licenses, and exact-alarm declarations are accurate.
- [ ] Delete-all, backup restore, database migration, and rollback paths are proven.
- [ ] Store beta and gradual-release halt criteria are in place.

## 24. Primary implementation references

- [Adhan JS](https://github.com/batoulapps/adhan-js)
- [Expo Notifications](https://docs.expo.dev/versions/latest/sdk/notifications/)
- [Expo SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/)
- [Expo Continuous Native Generation](https://docs.expo.dev/workflow/continuous-native-generation/)
- [Apple local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Apple Background Tasks](https://developer.apple.com/documentation/backgroundtasks)
- [Apple WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Android alarms](https://developer.android.com/develop/background-work/services/alarms)
- [Android app widgets](https://developer.android.com/develop/ui/views/appwidgets/overview)
- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)
