# Athkar

A mobile-first Arabic PWA for morning and evening adhkar.

**Live app:** https://t1nk333r.github.io/athkar/

## Native iOS testing and builds

[Native verification from Linux](docs/agents/ios-linux.md). The coordinator queues bounded
AthkarCore Swift Testing, portable production-model XCTest and iOS SDK compilation through
the repository runners. App-unit and UI runtime gates remain open until an authorized iOS
device run. Historical Mac jobs are preserved; the Mac runner is retired from new
verification.
Hosted app-unit tests start the normal app database and reminders. They require an
isolated, authorized device route that preserves the existing Feather installation.
The committed generated Xcode project is stale; `ios/project.yml` is authoritative.

## Planning

- [Native app plan: Swift first, Kotlin later](NATIVE_APP_PLAN.md). This is the current stack and sequencing decision.
- [Native iOS and Android product and engineering plan](MOBILE_APP_PLAN.md). It covers domain, content, privacy, and release details. Its stack decision is superseded by the plan above.

## TODO

- [ ] **Quick card index.** Jump directly to any dhikr in the current wird.
- [ ] **Search.** Find a dhikr by a word or phrase.
- [ ] **Favorites.** Save selected adhkar in a personal collection.
- [ ] **Monthly completion calendar.** Extend completion history beyond seven days.
- [ ] **Backup and import.** Export and restore settings, progress, history, and favorites.
- [ ] **Optional audio.** Provide verified recitation with play, pause, and repeat controls.
- [ ] **Home-screen quick actions.** Open morning or evening adhkar directly.
- [ ] **Personal reminders.** Allow optional custom times alongside prayer-relative reminders.
