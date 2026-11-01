# Research: iOS version floor — adoption and SwiftUI/API requirements

Ticket: [#5](https://github.com/t1nk333r/athkar/issues/5). Branch `research/ios-version-floor`.
All sources read **2026-09-23**. Facts only — no floor is chosen or recommended here; that is the next ticket (`NATIVE_APP_PLAN.md` §11 item 3).

## 1. Adoption, as published by Apple

From Apple's App Store support page ([developer.apple.com/support/app-store](https://developer.apple.com/support/app-store/), read 2026-09-23), section "iOS and iPadOS usage", measured by Apple "on devices that transacted on the App Store on **June 7, 2026**":

| Device class | Introduced in the last four years | All devices |
| --- | --- | --- |
| iPhone — "use iOS 26" | 86% | 79% |
| iPad — "use iPadOS 26" | 79% | 68% |

Facts about that page, verified by reading it on 2026-09-23:

- It carries exactly those four numbers. Apple publishes **no per-version breakdown**; the share of devices on iOS 18/17/16 and earlier is not stated anywhere on it. Any "X% on iOS 17" figure will have to come from a source other than Apple.
- The denominator is devices that transacted on the App Store, not a device census `[INFERENCE from the page's own wording]`.
- The measurement window (7 June 2026) predates the current release cycle: Apple's iPhone User Guide lists the current system as **iOS 27**, compatible with iPhone 11 and later plus iPhone SE (2nd and 3rd generation) ([Apple Support — iPhone models compatible with iOS 27](https://support.apple.com/guide/iphone/iphe3fa5df43/ios), read 2026-09-23). `[INFERENCE: iOS 27 shipped after the 7 June 2026 measurement; the user-guide page is the current-release page as of reading]`
- Practical consequence for the decision, stated without recommendation: the compatibility list starts at iPhone 11, so A12-class devices (e.g. iPhone XR/XS) cannot run iOS 26/27 at all `[INFERENCE from the model list]`; part of the unmeasured 21% is hardware that no modern floor can serve, and part is update lag on compatible hardware.

Submission-toolchain requirement (distinct from the deployment target):

- Since **April 28, 2026**, apps uploaded to App Store Connect must be built with **Xcode 26 or later using an SDK for iOS 26** (or the matching 26 SDK for the other platforms) — [Apple Developer, Upcoming Requirements » SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements?id=02032026a), read 2026-09-23.
- [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes), read 2026-09-23: "Xcode 26 includes Swift 6.2 and SDKs for iOS 26…"; "Xcode 26 supports on-device debugging in iOS 15 and later…"; "Xcode 26 requires a Mac running macOS Sequoia 15.6 or later." The required build SDK does not set a deployment target; it constrains the toolchain, not the floor.

## 2. Minimum iOS version per API

All availability values are Apple's own documentation metadata, read 2026-09-23.

### 2.1 Observation / `@Observable`

| API | iOS minimum | Source |
| --- | --- | --- |
| Observation framework (`@Observable`, `withObservationTracking`) | **17.0** | [Observation](https://developer.apple.com/documentation/observation) |

- Implication: using `@Observable` as documented forces **iOS 17+**. No earlier availability for Observation is listed anywhere in its metadata; the framework is not back-deployed by Apple `[INFERENCE that no Apple back-deployment exists — none was found in the framework's documentation]`.

### 2.2 SwiftUI navigation and layout for the paged card deck (`NATIVE_APP_PLAN.md` §3.2/§8.3 Slice 4)

| API | iOS minimum | Source |
| --- | --- | --- |
| `NavigationStack` | 16.0 | [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) |
| `TabView` (tab container, app tabs) | 13.0 | [TabView](https://developer.apple.com/documentation/swiftui/tabview) |
| `PageTabViewStyle` (`.tabViewStyle(.page)`, the built-in paged deck route) | 14.0 | [PageTabViewStyle](https://developer.apple.com/documentation/swiftui/pagetabviewstyle) |
| `View.scrollTargetBehavior(_:)` (paging behaviour on a `ScrollView`) | 17.0 | [scrollTargetBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:)) |
| `ViewThatFits` (pick the first child that fits — auto-fit sizing) | 16.0 | [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits) |
| `ScaledMetric` | 14.0 | [ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric) |
| `GeometryReader` | 13.0 | [GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader) |
| `DragGesture` (swipe with axis lock) | 13.0 | [DragGesture](https://developer.apple.com/documentation/swiftui/draggesture) |
| `SensoryFeedback` (SwiftUI haptics) | 17.0 | [SensoryFeedback](https://developer.apple.com/documentation/swiftui/sensoryfeedback) |
| `UIFeedbackGenerator` (UIKit haptics, e.g. `UIImpactFeedbackGenerator`) | 10.0 | [UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator) |
| `Tab` (current `TabView` element syntax) | 18.0 | [Tab](https://developer.apple.com/documentation/swiftui/tab) — the older `.tabItem` form remains usable on iOS 13+ `[INFERENCE: `.tabItem` is not deprecated in the docs read, but no availability was fetched for it in this pass]` |

Implied floors: the paged deck can be built at **iOS 14** with `TabView`+`.page`, or at **17** if built on `ScrollView`+`scrollTargetBehavior`; `NavigationStack` needs **16**; auto-fit container `ViewThatFits` needs **16**; SwiftUI-native haptics need **17** but UIKit generators reach back to **10**.

### 2.3 `UNUserNotificationCenter` behaviours relied on in `NATIVE_APP_PLAN.md` §7.5

| API | iOS minimum | Source |
| --- | --- | --- |
| `UNUserNotificationCenter` | 10.0 | [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) |
| `add(_:withCompletionHandler:)` (schedule) | 10.0 | [add(_:withCompletionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)) |
| `getPendingNotificationRequests(completionHandler:)` (replan diff input) | 10.0 | [getPendingNotificationRequests](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)) |
| `removePendingNotificationRequests(withIdentifiers:)` | 10.0 | [removePendingNotificationRequests](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)) |
| `UNNotificationCategory` (actions registered via `setNotificationCategories`) | 10.0 | [UNNotificationCategory](https://developer.apple.com/documentation/usernotifications/unnotificationcategory) |
| `UNNotificationAction` (the "سجّل الصلاة" action) | 10.0 | [UNNotificationAction](https://developer.apple.com/documentation/usernotifications/unnotificationaction) |

- Terminated-state delivery, quoted from [Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) (read 2026-09-23): "The system handles delivery of notifications based on a time or location that you specify. If the delivery of the notification occurs when your app isn't running or in the background, the system interacts with the user for you. If your app is in the foreground, the system delivers the notification to your app for handling." This is the behaviour §7.5 exists to exploit; it is not version-gated beyond the iOS 10 framework introduction.
- Removal semantics, from the `removePendingNotificationRequests(withIdentifiers:)` page: identifiers that belong to a non-repeating request whose trigger condition was already met are ignored; the method executes asynchronously on a secondary thread.
- Action display budget, from the `UNNotificationCategory` page: "When the system has unlimited space, the system displays up to 10 actions. When the system has limited space, the system displays at most two actions." Categories themselves: "You can register as many category objects as you need."
- Replan triggers from §7.5: `UIApplication.significantTimeChangeNotification` is documented with no introduction version (available on all listed iOS versions) and fires on a new day (midnight), carrier time updates, and daylight-saving changes — [significantTimeChangeNotification](https://developer.apple.com/documentation/uikit/uiapplication/significanttimechangenotification). `NSSystemTimeZoneDidChange` availability was **not** separately verified in this pass.
- Note: the same doc page also declares the Swift-concurrency form `pendingNotificationRequests() async -> [UNNotificationRequest]`; its individual availability annotation was not separately verified (the completion-handler form is iOS 10.0+).
- **Implication: nothing in §7.5 requires more than iOS 10.** The notification stack does not constrain a modern floor.

### 2.4 `BGAppRefreshTask`

| API | iOS minimum | Source |
| --- | --- | --- |
| `BGAppRefreshTask` | 13.0 | [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) |
| `BGAppRefreshTaskRequest` | 13.0 | [BGAppRefreshTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest) |

The class page states app refresh tasks require the `fetch` `UIBackgroundModes` capability. Implication: **13+**; the opportunistic replan in §7.5 does not constrain the floor further.

### 2.5 WidgetKit (iOS 1.1, `NATIVE_APP_PLAN.md` §3.3)

| API | iOS minimum | Source |
| --- | --- | --- |
| WidgetKit framework | 14.0 | [WidgetKit](https://developer.apple.com/documentation/widgetkit) |
| `View.containerBackground(_:for:)` (widget container background, iOS 17-era widgets) | 17.0 | [containerBackground(_:for:)](https://developer.apple.com/documentation/swiftui/view/containerbackground(_:for:)) |

Implication: **any widget requires iOS 14+**; a widget built with current APIs uses the 17+ container-background modifier, which is below the plan's stated 1.1 target anyway `[INFERENCE: 1.1 ships after 1.0; the shipped 1.0 floor is not decided by this document]`.

### 2.6 `adhan-swift` — the plan's prayer-time engine

From the package manifest at the release tag and on the default branch ([Package.swift @ 1.5.0](https://raw.githubusercontent.com/batoulapps/adhan-swift/1.5.0/Package.swift), read 2026-09-23):

```swift
// swift-tools-version:6.0
platforms: [ .iOS(.v13), .macOS(.v10_13), .tvOS(.v12), .watchOS(.v6), .visionOS(.v1) ]
```

- Declared minimums: **iOS 13**, macOS 10.13, tvOS 12, watchOS 6, visionOS 1.
- Current release: **1.5.0**, published **2026-06-12**; notable changes include "Remove Objective-C support" and an international-date-line fix ([releases API](https://api.github.com/repos/batoulapps/adhan-swift/releases), read 2026-09-23). The previous release, 1.4.0, was 2022-03-14 — i.e. 1.5.0 is the first release in ~4 years.
- Implication: the package imposes **iOS 13**; it cannot raise the app's floor above whatever the app itself chooses. (`NATIVE_APP_PLAN.md` Slice 0 pins this package; pin 1.5.0 unless the port needs otherwise.)

### 2.7 Adjacent floors the decision may collide with (supplementary; not enumerated in the ticket)

| Item | iOS minimum | Source |
| --- | --- | --- |
| GRDB.swift (plan §6.1 storage) | 13 (`Package.swift` declaration on the default branch) | [GRDB.swift Package.swift](https://raw.githubusercontent.com/groue/GRDB.swift/master/Package.swift), read 2026-09-23 |
| `CLLocationManager.accuracyAuthorization` (plan §7.4 `.reducedAccuracy`-tolerant handling) | 14.0 | [accuracyAuthorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization) |

- The CoreLocation page adds: when the value is `.reducedAccuracy`, setting `desiredAccuracy` to anything other than `kCLLocationAccuracyReduced` has no effect; the app also cannot use region monitoring or beacon ranging. So the §7.4 handling implies **iOS 14+**.
- GRDB's declaration was read from the default branch (in-development line, Swift tools 6.1); confirm against the version pinned in Slice 0.

## 3. The 64 pending local-notification limit

- Apple states the number **only** on the deprecated `UILocalNotification` page (introduced iOS 4.0, deprecated at iOS 10.0), quoted verbatim: "An app can have only a limited number of scheduled notifications; the system keeps the soonest-firing 64 notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest." — [UILocalNotification](https://developer.apple.com/documentation/uikit/uilocalnotification), read 2026-09-23.
- The modern UserNotifications reference does **not** restate it. Both [Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) and [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) were read end-to-end on 2026-09-23 and contain no occurrence of "64" and no limit statement.
- Whether the limit varies by iOS version: **Apple documents no variation.** No Apple page was found stating a different number for any iOS version; the sentence has been carried unchanged on a page whose availability metadata ends at iOS 10 (deprecated). `[INFERENCE: it is widely reported by developers to still be enforced at 64 on current iOS, but that is community reporting (e.g. Apple Developer Forums threads), not an Apple statement; Apple's current framework documentation is silent on the numeric limit.]`
- One related number that *is* documented for the modern framework: up to 10 actions displayed with unlimited space, at most 2 with limited space ([UNNotificationCategory](https://developer.apple.com/documentation/usernotifications/unnotificationcategory), read 2026-09-23).
- Implication for §7.5: the plan's 7-day horizon (49 requests/day-budget arithmetic) is derived from 64 — a figure Apple no longer states in the framework the plan targets. The planner's truncate-furthest-first design does not depend on the source of the number, but the diagnostics screen and the fixtures' stated budget do inherit this provenance. No recommendation is made here.

## 4. What each finding implies (no decision)

- `@Observable` → **iOS 17+** if used as documented.
- Paged deck: `TabView` + `.page` → **iOS 14+**; `ScrollView` + `scrollTargetBehavior` → **iOS 17+**.
- `NavigationStack` → **iOS 16+**.
- Auto-fit: `ViewThatFits` → **16+**; `ScaledMetric` → **14+**; `GeometryReader` → **13+**.
- Haptics: `SensoryFeedback` → **17+**; UIKit `UIFeedbackGenerator` → **10+** (a fallback that does not force 17).
- Current `Tab` element syntax → **18+** (older `.tabItem` syntax works from 13+).
- §7.5 notification behaviours → **iOS 10+** (including documented delivery while the app is not running); no higher floor found.
- `BGAppRefreshTask` → **13+**.
- WidgetKit → **14+** (framework); `containerBackground` → **17+**.
- `adhan-swift` → declares **13+**.
- GRDB → declares **13+**.
- Reduced-accuracy location handling → **14+**.
- App Store submission → **Xcode 26 + iOS 26 SDK** (toolchain requirement since 2026-04-28, not a deployment-target rule).

Net statement of fact: the highest floor forced by the plan-named APIs is **iOS 17** (`@Observable`, `scrollTargetBehavior`, `SensoryFeedback`), except that adopting the iOS-18-only `Tab` API would exceed it; nothing in the notification, background-task, WidgetKit, or `adhan-swift` findings pushes above iOS 14.

## 5. Sources (all read 2026-09-23)

- Apple, App Store support page (adoption figures; measurement date 7 June 2026): https://developer.apple.com/support/app-store/
- Apple Developer, Upcoming Requirements — SDK minimum requirements (since 28 April 2026, Xcode 26 + iOS 26 SDK): https://developer.apple.com/news/upcoming-requirements?id=02032026a
- Apple, Xcode 26 Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes
- Apple Support, iPhone models compatible with iOS 27 (current release; iPhone 11 and later, SE 2nd/3rd gen): https://support.apple.com/guide/iphone/iphe3fa5df43/ios
- Apple, Observation framework (iOS 17.0+): https://developer.apple.com/documentation/observation
- Apple, `NavigationStack` (16.0+): https://developer.apple.com/documentation/swiftui/navigationstack
- Apple, `TabView` (13.0+): https://developer.apple.com/documentation/swiftui/tabview
- Apple, `PageTabViewStyle` (14.0+): https://developer.apple.com/documentation/swiftui/pagetabviewstyle
- Apple, `View.scrollTargetBehavior(_:)` (17.0+): https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:)
- Apple, `ViewThatFits` (16.0+): https://developer.apple.com/documentation/swiftui/viewthatfits
- Apple, `ScaledMetric` (14.0+): https://developer.apple.com/documentation/swiftui/scaledmetric
- Apple, `GeometryReader` (13.0+): https://developer.apple.com/documentation/swiftui/geometryreader
- Apple, `DragGesture` (13.0+): https://developer.apple.com/documentation/swiftui/draggesture
- Apple, `SensoryFeedback` (17.0+): https://developer.apple.com/documentation/swiftui/sensoryfeedback
- Apple, `UIFeedbackGenerator` (10.0+): https://developer.apple.com/documentation/uikit/uifeedbackgenerator
- Apple, `Tab` (18.0+): https://developer.apple.com/documentation/swiftui/tab
- Apple, `UNUserNotificationCenter` (10.0+): https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- Apple, `add(_:withCompletionHandler:)` (10.0+): https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)
- Apple, `getPendingNotificationRequests(completionHandler:)` (10.0+): https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)
- Apple, `removePendingNotificationRequests(withIdentifiers:)` (10.0+): https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)
- Apple, `UNNotificationCategory` (10.0+): https://developer.apple.com/documentation/usernotifications/unnotificationcategory
- Apple, `UNNotificationAction` (10.0+): https://developer.apple.com/documentation/usernotifications/unnotificationaction
- Apple, Scheduling a notification locally from your app: https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- Apple, `UILocalNotification` (4.0+, deprecated at 10.0; the 64-object statement): https://developer.apple.com/documentation/uikit/uilocalnotification
- Apple, `BGAppRefreshTask` (13.0+): https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask
- Apple, `BGAppRefreshTaskRequest` (13.0+): https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest
- Apple, WidgetKit framework (14.0+): https://developer.apple.com/documentation/widgetkit
- Apple, `View.containerBackground(_:for:)` (17.0+): https://developer.apple.com/documentation/swiftui/view/containerbackground(_:for:)
- Batoul Apps, `adhan-swift` Package.swift @ 1.5.0 (declares iOS 13): https://raw.githubusercontent.com/batoulapps/adhan-swift/1.5.0/Package.swift
- Batoul Apps, `adhan-swift` releases (latest tag 1.5.0, published 2026-06-12): https://api.github.com/repos/batoulapps/adhan-swift/releases
- Groue, GRDB.swift Package.swift (declares iOS 13): https://raw.githubusercontent.com/groue/GRDB.swift/master/Package.swift
- Apple, `CLLocationManager.accuracyAuthorization` (14.0+): https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization

## 6. Not verified in this pass (open items for the decision ticket)

- Apple's published share of devices below iOS 26 — Apple does not publish it.
- Whether the 64-object pending-notification limit differs on any iOS version — Apple documents no variation; current enforcement is community-reported only.
- `NSSystemTimeZoneDidChange` availability.
- Availability annotations of the Swift-concurrency forms of `UNUserNotificationCenter` accessors.
- Xcode 26's minimum *deployment* target (its release notes state on-device debugging support for iOS 15+, not a deployment-target floor); confirm when the Xcode project is created.
