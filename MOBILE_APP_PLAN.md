# Athkar native iOS and Android plan

## Status

This document defines the proposed product, domain, architecture, delivery, and release plan for a native iOS and Android edition of Athkar. It is a plan, not a claim that the native app is already implemented.

**Stack decision superseded.** [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md) replaces §10 (React Native/Expo) and §19 (delivery phases) with a Swift/SwiftUI iOS-first build and a deferred Kotlin/Compose Android build, and it consolidates رقية القرين and prayer times into the same app. Its §2 classifies every section below as authoritative, superseded, or needing rewrite; where the two disagree, that document wins. The domain, content-governance, privacy, and publisher-identity sections here remain authoritative.

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

1. **Arabic first and RTL first.** Arabic is the launch language; design the layout in RTL rather than mirroring it as an afterthought.
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

The PWA's reminder timers work reliably only while the page is open. The native app addresses that limitation.

## 4. Scope and release boundaries

### Public 1.0: complete core

- Full PWA parity.
- Today dashboard with the next prayer, today's five prayers, and morning/evening completion.
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
- Add signed downloadable content packs only after the team proves the bundled-content pipeline.

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
- Add a Qibla entry point only when the user installs that module.

### Prayer tracker

- Today's five obligatory prayer occurrences.
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

The app captures the IANA time zone, scheduled UTC instant, and calculation-profile version as immutable metadata when it first creates the row. These values are not part of the row's identity. Each calculation date and prayer key has one row, even if the device changes zones that day. If the device crosses the date line and repeats a civil date, 1.0 reuses that row. The UI preserves and displays the zone recorded with it.

Changing a method later must not move, duplicate, or silently recalculate a historical log.

### 6.2 Recording state

Use a small neutral core state:

- `unrecorded`: default; never rendered as “missed.”
- `prayed`: recorded by the user.
- `not_applicable`: the user explicitly selects this state for a prayer or date range.

A `prayed` row may have an optional user-selected timing value:

- `on_time`
- `late`
- `made_up`

The user supplies those values. Content reviewers must approve the wording before release.

Optional modifiers are separate fields rather than new completion states:

- Congregation or mosque.
- Combined with previous/next.
- Shortened while traveling.
- User note, disabled by default.
- Entry source: app, notification action, widget, import, or migration.

### 6.3 Primary workflows

- **Quick log:** tap a prayer row to record it; show an undo action immediately.
- **Details:** open a sheet to choose timing and optional modifiers.
- **Correction:** users can edit or clear every value later. Ask for confirmation before clearing a day.
- **Past days:** calendar day detail supports the same controls as today.
- **Notification action:** “record as prayed” uses the same idempotent domain command as the app screen.
- **No automatic completion:** receiving or opening a notification never marks a prayer by itself.

### 6.4 Friday

On Friday, the app may display the Dhuhr occurrence as a Jumu'ah/Dhuhr choice. The user records which one they performed. The app does not infer eligibility or require demographic information. It records either choice in the single noon-prayer slot, not as two required rows.

### 6.5 Travel, combining, and shortening

- Travel mode is manually enabled for today or a selected date range.
- Available combining pairs and shortening rows come from a versioned rule set approved by a named reviewer, not from hard-coded product assumptions.
- The app surfaces only options in that reviewed rule set and never applies them automatically.
- A neutral explanation tells users to follow their own trusted scholarly guidance.
- Changing travel mode never rewrites existing records without an explicit confirmation.

### 6.6 Not-applicable ranges and sensitive details

- A user may mark a prayer or date range not applicable without providing a reason.
- The app keeps optional reasons local, omits them from diagnostics, and excludes them from backups unless the user explicitly includes them.
- The app does not require gender, health information, or an explanation.
- The app excludes these rows from completion denominators. It does not count them negatively.

### 6.7 Make-up tracking

- Entirely opt-in.
- The app never turns old `unrecorded` rows into a make-up debt.
- A user can select a historical occurrence and link a later `made_up` record to it.
- Undoing the later record restores the original state.
- A bulk make-up ledger is a 1.1 feature and requires content review.

### 6.8 Optional prayers

Sunnah, Witr, Duha, Qiyam, and Tarawih are separate optional modules. They never change obligatory-prayer completion, and the app hides them until enabled.

### 6.9 Date, midnight, and travel rules

- Athkar sessions continue to reset at local civil midnight.
- Prayer records stay attached to their original occurrence even when recorded after midnight.
- Users can always reach the previous day's Isha through day navigation. The app makes no claim about its validity window.
- Time-zone changes create new local schedule context. The app never shifts or deletes existing records.
- A backward device-clock change triggers a quiet warning and must not discard history.

## 7. The eight README features

| Feature | Release | Product contract |
| --- | --- | --- |
| Quick card index | 1.0 | Open any card in at most two taps; show number, opening text, and count/target; announce the destination to screen readers. |
| Search | 1.0 | Search both collections using an Arabic index that ignores tashkeel, tatweel, and common Alef/Hamza variants without modifying the displayed text. |
| Favorites | 1.0 | Personal reading list with no independent completion requirement; persists, exports, and supports undo on removal. |
| Monthly completion calendar | 1.0 | Unbounded local history; month grid and day detail for prayers and both adhkar periods; no shame copy or competitive streak. |
| Backup and import | 1.0 | Versioned, validated file with preview and merge/replace; malformed or newer formats fail safely; location and sensitive details excluded by default. |
| Optional audio | 1.1 | Verified per-dhikr audio, explicit download, offline cache, reciter/license attribution, no autoplay, and independent repeat controls. |
| Home-screen quick actions | 1.0 | Morning, evening, and log-prayer actions cold-start into the exact destination. |
| Personal reminders | 1.0 | Fixed local times and adjustable prayer-relative offsets, weekday selection, deduplication, and completion suppression. Replan when the platform permits or at the next launch, and disclose the iOS terminated-state limitation. |

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
- Pair automatic current location with the device's current IANA zone; manual cities carry their own zone and allow an override.
- Display which location and time zone produced the schedule and when it was last updated.

### Correctness gate

Before replacing the existing engine, compare:

- Current PWA output versus Adhan output across at least 30 locations and 12 dates.
- Published authority tables for representative launch regions.
- Equatorial, high-latitude, southern-hemisphere, daylight-saving, and polar-edge cases.

Any material time shift requires an explicit product/content sign-off and release note.

## 9. Native reminders

### Reminder planner

A deterministic planner receives the current time, location profile, time zone, calculation settings, completion/log state, reminder rules, and scheduling horizon. It returns stable notification IDs and UTC trigger instants.

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
- While the app is terminated, iOS may not notify it promptly about a time-zone or manual clock change. The app recalculates on the next launch or foreground event and discloses that already scheduled reminders may retain the old zone until then.

Apple documents system delivery while an app is not running and provides an API for removing pending requests; Athkar uses that cancellation API after completion: [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

### Android

- Use notification channels for prayer, adhkar, and custom reminders.
- Use inexact alarms by default where acceptable.
- Evaluate user-granted exact-alarm access because prayer reminders are core, but complete the Google Play policy review before requesting it.
- Android 14 and later do not pregrant `SCHEDULE_EXACT_ALARM` to fresh installs, and `USE_EXACT_ALARM` is restricted by Google Play to qualifying alarm/calendar use cases. Exact mode remains conditional on policy approval and granted access.
- If exact access is unavailable, show the user that delivery may be delayed and use the supported inexact fallback.
- Reschedule from receivers for reboot, time change, time-zone change, package replacement, and permission change.
- Do not run a permanent background service or poll location.

Android's official guidance explains the battery and permission tradeoffs for exact alarms: [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms).

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

- The team can migrate existing JavaScript domain rules and content to typed shared packages.
- The PWA and native app can share content, backup schemas, search normalization, and pure scheduling rules.
- Expo provides maintained iOS/Android notification and SQLite APIs while prebuild permits native widgets, receivers, and configuration plugins.
- It avoids maintaining two complete native UIs for a small team.

Do not use Expo Go as the production architecture; widgets, boot receivers, and alarm configuration require development builds/prebuild.

### When to reject the recommendation

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

Only move the PWA under `apps/pwa` after GitHub Pages and migration tooling work from the new layout.

### Module boundaries

- `content`: pack validation, Arabic search index, sources, favorites, and audio metadata.
- `sessions`: counters, targets, manual completion, rollover, and history.
- `prayer-times`: `PrayerTimesPort`, Adhan adapter, profiles, time zones, and Qibla.
- `prayer-tracker`: occurrence identity, status transitions, travel options, undo, and calendar queries.
- `reminders`: pure planner plus platform scheduler adapters.
- `backup`: versioned envelope, validation, encryption, merge, and PWA migration.
- `data`: SQLite migrations and repositories.
- `platform`: location, notifications, widgets, deep links, quick actions, haptics, secure storage, and diagnostics.
- `app`: screens, navigation, Arabic design system, and accessibility.

Domain packages must not import React Native or platform SDKs. Platform adapters implement explicit interfaces so developers can test time calculations, reminder planning, migration, and tracker transitions without a device.

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
- Assign shared content a stable slug for search and favorites across pack versions.
- The app derives history from persisted rows and no longer caps it at seven days.
- A unique index on `(calculation_date, prayer_key)` makes prayer-log writes idempotent. The app captures scheduled time, zone, and profile as metadata.
- All mutable records carry `updated_at`. Add tombstones only when synchronization ships.
- The tracker never infers `not_applicable`, timing, travel, or congregation.

## 12. Content-pack system and governance

Extract inline content into a versioned bundled Arabic pack containing:

- Stable slug and collection-specific ID.
- Quran/dhikr kind, Arabic text, prefix, details, count, target options, and label.
- Structured sources: collection/book, reference number, grading, grader, and scholarly note.
- The review state lets reviewers exclude an item from completion.
- Optional audio metadata: file, hash, reciter, license, and reviewer approval.

Launch packs are bundled and work offline. Do not add remote packs until signature verification and rollback exist.

Every content change requires:

1. Validate the schema.
2. Verify Quran text character for character against an approved source.
3. Obtain approval from a named content reviewer.
4. Bump the content version and update the content changelog.
5. Run a migration test to confirm favorites and history retain stable references.

The app's About screen shows the content version, sources, calculation parameters, licenses, and the recording-not-ruling disclaimer.

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

Native applications cannot read the PWA's localStorage sandbox. Migration therefore requires:

1. Add export/import to the PWA using the shared envelope.
2. Offer “Import from the web app” during native onboarding and later in settings.
3. Accept a file through the document picker/share sheet. A custom deep link may be used for convenience with non-sensitive payloads.
4. Map current progress, targets, manual completion, seven-day history, reminder preferences, theme, reading settings, and haptics. Include location only if the user selects the same explicit location-inclusion option used by normal exports.
5. Compare a native re-export with the PWA export in an automated round-trip fixture.
6. Keep the PWA available through a documented migration window.

### Encryption and synchronization

- Encrypted export is the preferred format once an interoperable PWA/native crypto envelope passes review.
- Keep plain JSON as an explicit portability option with a privacy warning. Exclude location by default.
- If a user explicitly includes sensitive reasons in a plaintext export, show a separate warning that those values will be readable in clear text.
- Do not treat system device backup, which may cover the app sandbox, as cross-platform synchronization.
- If the project ships sync, use an end-to-end encrypted blob or row protocol that prevents the service from reading worship data. Reevaluate both stores' privacy declarations before release.
- No proprietary backend is required for 1.0.

## 14. Widgets, quick actions, and deep links

### 1.0 quick actions

- Morning adhkar.
- Evening adhkar.
- Log a prayer.

Each launches the precise route on a cold start.

### 1.1 widgets

- Small: next prayer and countdown.
- Medium: today's five prayer states and both adhkar states.
- Optional dedicated adhkar widget.
- iOS uses WidgetKit; Android uses Jetpack Glance.
- Native extensions read a minimal shared snapshot, not the primary SQLite database.
- Widget data excludes history, notes, exemption reasons, and precise location.

### Deep links

Support routes for morning, evening, a specific card, a prayer occurrence, search, import, and reminder settings. Use the custom scheme as the guaranteed path. Universal/App Links require an early hosting spike for both Apple and Android association files.

## 15. Privacy and security

### Launch posture

- No ads, behavioral analytics, accounts, remote content, or third-party tracking in the native app.
- The **PWA** (not the native app) counts page loads with a self-hosted GoatCounter on the developer's own server (`https://count.aloqaili.xyz`) to measure usage and platform distribution.
  A small inline beacon in `index.html` (no remote script) sends one request per page load: `GET /count?p=%2F&s=<screen width>&b=<bot code>&rnd=<random>`.
  The request has exactly these parameters, no referrer (`referrerPolicy: no-referrer`), and no cookies (`credentials: omit`). The width is a finite integer clamped to 0–99999; otherwise, the beacon sends nothing.
  The bot code mirrors GoatCounter's `count.js`. The beacon never sends a title, query string, hash, tab, or sura. It reads no `localStorage` key except GoatCounter's opt-out flag `skipgc`.
  No counter, history, location, setting, or backup data leaves the device. The beacon skips requests when offline, inside frames, and on local hosts. It checks again immediately before sending, and `sw.js` never handles the cross-origin request.
  The server receives the IP address and user agent transiently for counting. It keeps aggregate data (browser/OS, screen width, and country), not individual pageviews. The relay keeps no access log for the counter.
  As an exception, GoatCounter keeps the raw user agent for requests it classifies as bots so it can filter them. A server maintenance job purges those bot records hourly. The job normally removes them within about an hour. This is a best-effort job, not a hard bound.
  If it fails, GoatCounter's own cleanup (about 30 days) is the fallback. The PWA's Settings discloses this.
- The native app's 1.0 release gate of "no data collected/shared" (Store declarations below) is unchanged. It ships no counter.
- No worship or location data leaves the device during ordinary use.
- The app requests location once, uses a coarse location sufficient for calculations, rounds coordinates before storage, and never collects location in the background.
- Notification text contains no personal prayer history.
- Exclude sensitive details from default exports and redact them from diagnostics.
- Offer delete-all in settings and require deliberate confirmation.
- The app blurs sensitive tracker details in the app switcher.

### Storage and secrets

- Keep the SQLite database in the app sandbox and protect it with platform data protection.
- A launch threat model must decide whether platform data protection is sufficient or whether to protect the full database with SQLCipher. Do not selectively encrypt one worship field.
- Never store backup passphrases or encryption keys with backup ciphertext.
- Sync keys, if introduced, live in Keychain/Keystore and have a documented recovery decision.
- Lock dependency versions and checksums. Minimize native permissions and review them for each release.

### Store declarations

Apple requires privacy details for apps and third-party SDKs. Google requires a Data Safety form even for apps that collect nothing. Treat "no data collected/shared" as a release gate for 1.0. Reassess the declarations after adding crash reporting, remote audio, or sync.

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)

## 16. Accessibility and localization

- Provide VoiceOver and TalkBack labels and announcements in Arabic for every status change.
- Support Dynamic Type/font scaling through at least 200% without clipping dhikr or controls.
- Preserve the bundled Uthman Taha Quran font and validate its shaping and diacritics on physical Android devices.
- Set a minimum touch target of 44 points or the platform equivalent.
- Never use color as the only status signal. Include text and glyphs.
- Apply RTL to navigation, calendars, progress, swipes, and chevrons.
- Disable card and completion animations when reduced motion is enabled.
- Let users disable haptics. Do not use haptics to convey unique information.
- Label Gregorian and Hijri dates clearly, and let users configure numeral style.
- Add an English UI after launch. Never machine-translate Quran or dhikr source text.

## 17. Quality strategy

### Domain and calculation tests

- Capture golden fixtures of current PWA behavior before extraction.
- Test prayer times across methods, cities, seasons, hemispheres, high latitudes, and DST boundaries.
- Test reminder planning with a fake clock for deterministic IDs, horizon budget, completion cancellation, duplicate prevention, and catch-up behavior.
- Test prayer-tracker transitions for undo, Friday choice, travel modifiers, not-applicable ranges, and import idempotence.
- Test Arabic search normalization without modifying displayed text.
- Test backup round trips with wrong passphrases, corruption, unsupported versions, merge, replace, and rollback.
- Test every SQLite migration against seeded previous-version databases.

### Device tests

- Test on at least one current and one older iPhone.
- Test on a Pixel and a low-memory Android device.
- Test on at least one Android OEM device with aggressive battery management.
- Run physical-device notification tests with the app foregrounded, backgrounded, and terminated. Also test the devices while idle, after reboot, and after changing the time or time zone.
- Test offline first launch, permission denial, approximate location, no compass, and storage pressure.

### UI and accessibility tests

- Capture RTL screenshots in light and dark modes, with three text sizes and three line spacings.
- Script and run VoiceOver/TalkBack flows for logging and undoing a prayer, completing a wird, changing a target, manual completion, search/jump, importing a backup, and changing reminders.
- Test large text, reduced motion, high contrast, long Arabic strings, and small screens.
- Test widget and quick-action deep links from a terminated state.

### Content checks

- Validate the schema and unique IDs.
- Check the Quran corpus checksum.
- Require source and review metadata for release content.
- Verify the audio hash, text match, attribution, license, and offline playback.

## 18. Nonfunctional targets

- All 1.0 core features work in airplane mode after installation.
- No permanent background service and no background location polling.
- Reach an interactive Today/adhkar screen within 1.5 seconds of a cold start on the agreed baseline Android device.
- Respond to a card tap within 50 ms and keep navigation smooth at supported font sizes.
- Do not lose a committed row after process termination.
- Notification planner never exceeds the validated platform request budget.
- When policy approves exact Android scheduling and the user grants access, target one-minute accuracy. Measure and disclose fallback behavior.
- Crash-free sessions target at least 99.5% using Play vitals and the subset of App Store users who opted into analytics sharing. Never attach worship data to crash diagnostics.
- The app without optional audio remains within a 30 MB download target.

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

**Exit:** Reviewers approve font rendering, notifications survive the physical-device run, and none of these conditions applies.

### Phase 1: shared foundation and migration

- Complete the iOS organization-membership conversion and finalize the public publisher identity before creating or releasing the App Store record.
- Define content, domain, and backup schemas.
- Extract the current content into a validated pack without changing wording or order.
- Capture PWA parity fixtures.
- Add PWA export/import before native beta.
- Establish SQLite migrations and repository interfaces.

**Exit:** Approve the iOS organization membership and public identity before creating any App Store Connect record or uploading a TestFlight build. The native app's re-export after PWA import must match the PWA export with no semantic difference, and content checks must pass.

### Phase 2: native PWA parity

- Native shell, navigation, design tokens, fonts, settings, and accessibility.
- Morning/evening decks, counters, targets, reset, completion, manual external completion, free browsing, history, source sheets, haptics, and offline assets.
- Quick index, search, favorites, and quick actions.

**Exit:** every baseline workflow passes on iOS and Android, including offline and accessibility scripts.

### Phase 3: prayer engine and tracker

- Full prayer-times screen, profiles, manual city, Hijri display, and calculation tests.
- Today dashboard and prayer occurrence model.
- Logging, edit/undo, Friday choice, travel options, not-applicable ranges, single-occurrence make-up links, and monthly calendar.

**Exit:** The domain transition suite passes, prayer times meet approved reference tolerances, and reviewers approve the content and religious wording.

### Phase 4: reminder reliability

- Native scheduler adapters, rolling horizon, channels, actions, cancellation, Android receivers, permission flows, and diagnostics.
- Existing adhkar reminders, all five prayer reminders, and personal reminder rules.

**Exit:** The physical-device notification matrix shows zero duplicates and verifies that the app cancels reminders after completion. Users can see fallback limitations.

### Phase 5: privacy, release, and migration beta

**Entry:** Phase 1's organization-identity gate is complete before anyone creates the App Store Connect app record or uploads a TestFlight build.

- Backup/import UI, privacy screen, delete-all, store disclosures, diagnostics export, support copy, and PWA migration banner.
- TestFlight external and Play closed testing across regions, time zones, and OEMs.

**Exit:** migration, accessibility, privacy, content, crash, and notification release gates all pass.

### Phase 6: complete native suite

- Widgets, Qibla, optional audio, optional prayers, Ramadan mode, encrypted backups, biometric lock, and English UI.

**Exit:** each module has its own content, privacy, offline, accessibility, and platform-integration acceptance evidence.

### Phase 7: optional synchronization

Proceed only after a threat model and product decision confirm demand.

**Exit:** Obtain approval for end-to-end encryption, conflict handling, deletion, recovery, privacy declarations, and cross-device tests before enabling sync publicly.

## 20. CI/CD and release operations

### iOS public identity: remove the Account Holder's personal name

#### What can and cannot be hidden

Apple must know the real Account Holder and legal entity. The goal is to remove the person's name from public App Store surfaces, not to give Apple false information.

| Surface | What controls it | Required action |
| --- | --- | --- |
| Seller name | Apple Developer Program membership | An individual membership uses the member's legal name. Use a verified organization membership so the organization's legal name is the seller. |
| Developer name shown below the app | App Store Connect publisher identity | An individual cannot choose another name. An organization may choose a registered trade name, DBA, or fictitious business name for its first app. Apple says organizations cannot change this choice later. |
| App name and icon label | App Store metadata and `CFBundleDisplayName`/Expo configuration | Set both to the product brand. This does not change the seller or developer name. |
| Support, privacy, marketing, copyright, and trader details | App Store Connect metadata and compliance records | Use organization-owned domains, email addresses, phone numbers, and lawful business details in every public field. |
| Bundle ID, Team ID, and signing certificate | Developer and build configuration | These are technical identifiers. Changing the app name does not change the public seller; changing teams requires a signing and entitlement cutover. |

Apple does not offer a supported self-service switch from an individual seller name to a brand. Apple says changing the Apple Account profile name does not change an existing individual membership or App Store seller name in its [account-information guidance](https://developer.apple.com/help/account/membership/updating-your-account-information/). If no qualifying legal entity exists, create one and have Apple verify it, keep the legal personal seller name, or delay iOS distribution. A DBA or trade name alone does not qualify as the organization legal entity.

#### Recommended path: convert the existing individual membership

Use this path before creating the first App Store app record. Request it first if an unreleased app record already exists.

1. **Pause App Store setup.** Do not submit or release the app under the individual identity merely to make it transferable.
2. **Confirm the legal entity.** Use an existing corporation, LLC, nonprofit, or other entity that can enter contracts with Apple. If none exists, establish the appropriate entity through the applicable jurisdiction before continuing. A DBA alone is insufficient.
3. **Verify the organization's D-U-N-S record.** Obtain or look up the D-U-N-S Number and make its legal name, address, and phone match the formation documents exactly.
4. **Prepare the organization's presence.** Provide a functional public website on the organization's domain and a work email address on that domain. Social-media-only or parked pages do not satisfy Apple's published organization requirements.
5. **Confirm authority and account security.** Apple's current [individual-to-organization guidance](https://developer.apple.com/help/account/membership/updating-your-account-information/#updating-an-individual-membership-to-an-organization-membership) says the current Account Holder must be a founder or cofounder. That person must also have authority to bind the entity and use an Apple Account with two-factor authentication.
6. **Gather verification material.** Prepare formation/registration documents, D-U-N-S details, organization address and phone, website, domain email, and the existing Team ID. Keep these private and never commit them to this repository.
7. **Submit Apple's migration request.** Sign in as the Account Holder and use [Update an individual membership to an organization membership](https://developer.apple.com/contact/request/migrate-individual-account). Include any existing app Apple ID and bundle ID so Apple can advise on the unreleased record.
8. **Complete Apple's verification.** Respond to requests for business documents or a verification call. Do not change the D-U-N-S or legal-entity spelling while review is in progress.
9. **Verify the approved membership.** Check the Apple Developer account and App Store Connect for an Organization entity type and the correct seller/legal-entity name before uploading a release build.
10. **Set the developer name deliberately.** If this organization has never added an app, choose the registered public trade/DBA name in the **Company Name** field while creating its first app. If an app record already exists, include the desired developer name in the migration case and obtain Apple's written answer. Do not assume the choice can be edited afterward.
11. **Finalize the security owner before storing keys.** Compare the Team ID before and after conversion. Until you confirm the final Team ID, do not place an unrecoverable database, app-lock, backup, or sync key only in a team-scoped Keychain group. If users already have such keys, require a reviewed recovery/migration design before changing teams.
12. **Reaccept operational records.** Complete any new agreements, tax, banking, trader-status, and compliance prompts using accurate organization information.
13. **Record the final identity privately.** Document the legal seller name, public developer name, Team ID, App Store Connect provider, support domain, and responsible Account Holder in the private release runbook. Include only non-sensitive public values in the repository.

If Apple cannot migrate an unreleased app record, open a Developer Support case for the record and bundle ID. Do not publish a placeholder version under the personal name just to satisfy the transfer requirement.

#### Fallback path: transfer an already released app

Use this path only when the app has at least one App Store release and a separate verified organization account will become its legal owner. The transfer preserves the bundle ID, reviews, ratings, availability, and user updates. It also changes ownership and affects entitlements and signing.

1. **Finish the receiving organization account first.** Confirm its organization seller name and, where still configurable, its public developer name.
2. **Accept current agreements on both accounts.** Neither account may have a pending membership change. Both Account Holders must accept the latest free and paid agreements. If the transferor accepted the Alternative Terms Addendum for EU distribution, the recipient must accept it too.
3. **Check Apple's transfer criteria.** The app must have a released version, must not be in pre-order or a blocked review/release state, and must meet current in-app-purchase and asset-pack conditions. Confirm that none of its in-app-purchase product IDs collide with IDs in the recipient account.
4. **Inventory capabilities before initiating the transfer.** Record APNs/remote push, the default and custom Keychain access groups, App Groups/widgets, associated domains/universal links, iCloud/CloudKit, and Xcode Cloud usage. Assign an owner and cutover action for each enabled capability.
5. **Back up App Store records.** Save metadata, pricing, availability dates, sales/download reports, privacy answers, screenshots, build details, and support/compliance values outside the public repository.
6. **Prepare the app.** Turn off TestFlight testing and remove its builds, testers, and localized test information as Apple directs. Remove Xcode Cloud data when applicable and resolve every failed transfer criterion.
7. **Initiate as the current Account Holder.** In App Store Connect, open **Apps → Athkar → App Information → Additional Information → Transfer App**, pass the criteria screen, enter the receiving Account Holder's Apple Account and Team ID, accept the terms, and request the transfer.
8. **Accept within 60 days.** The receiving Account Holder opens **Business → Agreements → App Transfers → Review**, supplies organization support/marketing/privacy URLs and contact details, reviews app privacy and user access, accepts the terms, and completes any export-compliance request.
9. **Wait for completion.** Apple states that processing can take up to two business days. Do not alter ownership assumptions or ship from the receiving team until both Account Holders receive completion notice.
10. **Recreate signing assets.** The receiving team creates new development/distribution provisioning profiles for the transferred App ID and configures new team-owned credentials. Never reuse or publish private keys from the old account.
11. **Migrate capability-specific assets.** Recreate or update APNs keys or certificates, associated domains, iCloud entitlements, and every other item identified in step 4. Re-register transferred App Groups in the recipient account, and account for Apple converting a wildcard App ID to an explicit App ID. Local-only notifications do not require an APNs server. Run a physical-device regression test for them.
12. **Protect Keychain-backed data.** Apple says old Keychain sharing works only until the app receives an update under the recipient. Before transfer, ship or require a reviewed migration/recovery path for every recovery-critical key. After transfer, replace access groups with recipient-Team-ID groups and verify explicit restore, reauthentication, or unlock behavior. Never silently reset encrypted worship data, backup keys, or app-lock state.
13. **Move the build pipeline.** Point Expo/EAS and CI signing to the receiving organization, verify the final Team ID and provider, and remove the former account's access after a successful organization-signed build.
14. **Verify the public result.** Confirm that the live App Store product page and install sheet show the approved organization seller/developer identity and that no public support, privacy, copyright, or trader field exposes the personal name.

Do not transfer the app to a friend's or unrelated company's account merely to hide the name. The recipient becomes the legal owner and controls future releases.

#### Repository and build cutover

1. Finalize the product display name, organization-owned reverse-DNS bundle ID, support domain, privacy-policy URL, and public contact email before the first production signing.
2. Set the Expo app name and iOS display-name localization to the product brand. Set the final `ios.bundleIdentifier` once and avoid temporary identifiers.
3. Bind the Expo/EAS project and iOS credentials to the organization team. Compare the Team ID before and after conversion instead of assuming it remains unchanged.
4. Regenerate provisioning profiles and revalidate widgets, App Groups, keychain access and recovery, associated domains, universal links, local notifications, and export/import on physical iOS devices.
5. Search public store copy, About screens, source notices, support pages, privacy pages, screenshots, copyright text, and repository metadata for the personal name. Replace it only where the organization lawfully owns that public identity. Do not falsify required private Apple records.
6. Store Apple verification documents, tax/banking data, certificates, private keys, and account screenshots outside the repository and outside ordinary diagnostics.

#### Identity and first-record gate

Do not create an App Store Connect app record, upload a TestFlight build, or release the iOS app publicly until these conditions are met:

- App Store Connect identifies the provider as the approved organization.
- The seller name and developer name match the approved identity and contain no personal name.
- Public support, privacy, marketing, copyright, and applicable trader disclosures use organization-controlled details.
- Sign a TestFlight build with the final team and verify that it installs, launches, schedules reminders, writes/restores local data, opens widgets and deep links, and upgrades without data loss.
- Every Keychain-held secret remains readable after an organization-signed upgrade, or an explicit tested recovery/restore path preserves the protected data after a Team ID change.
- Record the final bundle ID, Team ID, App Store app ID, and EAS project owner in the private release runbook.
- Do not include credentials or private verification documents in evidence. You may retain redacted screenshots of public-facing identity checks.

### Continuous integration

- Run type checks, unit tests, schema/content checks, dependency/license audits, and backup fixtures on every pull request.
- Build iOS and Android previews from the main branch.
- Create production builds only from signed release tags.
- Pin Expo/React Native versions and use controlled upgrade branches.
- Use reproducible build profiles and protect signing credentials.

### Distribution

- Verified organization-owned Apple Developer and Google Play accounts, final bundle/package identifiers, signing, an organization support contact, and a privacy-policy URL are prerequisites. Do not create or release the iOS App Store record under a personal seller identity.
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

1. Final app name, organization legal seller name, public iOS developer name, bundle identifiers, Team ID/provider, support address, privacy-policy host, and store accounts.
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
- [ ] Ship all eight README features in their assigned release or explicitly hold them for the named 1.1 gate.
- [ ] Prayer calculations pass approved golden and authority comparisons.
- [ ] Never describe an unrecorded prayer as missed.
- [ ] Test tracker edits, undo, Friday, travel, and not-applicable cases for reversibility.
- [ ] Adhkar and prayer reminders survive termination and cancel after completion.
- [ ] Test time-zone, DST, reboot, clock-change, permission, and OEM battery cases on physical devices. Verify and disclose iOS reschedule-on-launch limitations.
- [ ] PWA export imports into native with a semantic round-trip match.
- [ ] Core use works offline with no account and no network dependency.
- [ ] VoiceOver, TalkBack, large text, RTL, contrast, and reduced motion pass.
- [ ] Complete content and audio review records.
- [ ] Privacy policy, Apple privacy details, Google Data Safety, permissions, licenses, and exact-alarm declarations are accurate.
- [ ] Prove the delete-all, backup restore, database migration, and rollback paths.
- [ ] Put store beta and gradual-release halt criteria in place.
- [ ] The public iOS seller, developer, support, privacy, copyright, and applicable trader identity uses the approved organization and exposes no personal name.
- [ ] Prove Team-change and Keychain migration on an upgrade build, or record them as not applicable if the final organization owned the app before any user data existed.

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
- [Apple Developer Program organization requirements](https://developer.apple.com/programs/enroll/)
- [Apple individual-to-organization membership update](https://developer.apple.com/help/account/membership/updating-your-account-information/#updating-an-individual-membership-to-an-organization-membership)
- [Apple developer-name rules](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)
- [Apple app-transfer overview](https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer/)
- [Apple app-transfer criteria](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria/)
- [Apple app-transfer initiation](https://developer.apple.com/help/app-store-connect/transfer-an-app/initiate-an-app-transfer/)
- [Apple app-transfer acceptance](https://developer.apple.com/help/app-store-connect/transfer-an-app/accept-an-app-transfer/)
