# Routes

The places the native app opens at from outside it. One table, one router: a URL, a home-screen quick action and a
tapped adhkar reminder all name a route here, and `AppModel.open(_:)` opens it (`ios/Athkar/App/AppRoute.swift`).
`AthkarPortableTests` reads this table and checks it against `AppRoute` and the Info.plist entries in
`ios/project.yml`.

| Route | URL | Quick action type | Quick action title | Opens |
| --- | --- | --- | --- | --- |
| `morning` | `athkar://morning` | `athkar.route.morning` | أذكار الصباح | the الصباح deck |
| `evening` | `athkar://evening` | `athkar.route.evening` | أذكار المساء | the المساء deck |
| `ruqyah` | `athkar://ruqyah` | `athkar.route.ruqyah` | رقية القرين | the رقية القرين deck in أخرى |
| `prayers` | `athkar://prayers` | `athkar.route.prayers` | سجّل الصلاة | «اليوم» in أخرى, where a prayer is recorded |

## URLs

- A custom scheme, `athkar`, declared in `CFBundleURLTypes`. No universal links: they need an associated domain, which
  waits for the publisher identity (NATIVE_APP_PLAN.md §8.1).
- The route is the URL's host: `athkar://morning`. `athkar:///morning` and `athkar:morning` (the route as the only
  path component) read the same. The scheme and the route ignore case. A query or fragment is ignored. Any other
  form, or a name not in the table, is not a route, and the app stays where it was.
- A file URL is not a route: a backup or transfer file opened in the app goes to «استيراد من تطبيق الويب», as before.

## Quick actions

`UIApplicationShortcutItems` lists the four routes in the table's order, with the titles above (SF Symbols `sun.max`,
`moon`, `book`, `checkmark.circle`). An action that launches the app is held until the app has started, then opened.
«سجّل الصلاة» opens «اليوم»; it records nothing by itself.

## Reminders

A tapped adhkar reminder opens its deck: `adhkar.morning.<date>` the `morning` route, `adhkar.evening.<date>` the
`evening` route. A tapped prayer reminder is not a route: it opens أوقات الصلاة, as before, and its «سجّل الصلاة» action
still records the prayer without opening the app (NATIVE_APP_PLAN.md §7.5).

## Opening a route

A route opens over whatever was on screen: the home screen closes its sheets (الإعدادات and everything opened from
it, the reset and completion sheets) so the opened place shows. Opening a route writes nothing.

## First launch

On a fresh install with no user data, the أخرى list offers «استيراد من تطبيق الويب» once, below its sections. It does
not block anything and asks nothing. It goes for good when it is used, when it is closed, or at a launch that finds
user data. «حذف كل البيانات» clears it, so the next launch offers it again.
