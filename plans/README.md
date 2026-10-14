# Athkar follow-up work

The user requested ten Athkar follow-up threads, five on Opus 5.5 xhigh and five on Sol 6.1 xhigh, monitored through review and merge. The explicit START on 2026-10-14 supersedes the earlier wait for Hikaya settlement. Athkar has no source, review, CI-migration, proxy-repair or acceptance dependency on NAS or Hikaya. Each coordinator retains its own unfinished work and rechecks shared resources before use.

At most three workers run concurrently in isolated worktrees. New checks run on Linux. Luna owns the installed Swift/iOS SDK lane under `/tmp/hikaya-build-suite.lock` then `/tmp/athkar-build-suite.lock`, acquired nonblocking, with at most two jobs and separate scratch directories. The coordinator grants native execution, integrates reviewed heads and settles threads after required checks and cleanup. Historical Mac work retains its owner and is not replayed.

| Task | Work | Executor | Host | Reviewer | Status |
| --- | --- | --- | --- | --- | --- |
| [001](001-session-history.md) | Restore native session history parity | Sol xhigh | Luna | 002 | RELEASED |
| [002](002-adhkar-save.md) | Commit adhkar UI state only after a successful save | Opus xhigh | Mars | 006 | RELEASED |
| [003](003-ruqyah-save.md) | Preserve ruqyah completion and counters through storage failures | Opus xhigh | Jupiter | 008 | RELEASED |
| [004](004-reminder-races.md) | Serialize reminder replans so obsolete requests cannot return | Opus xhigh | Mars | 009 | RELEASED |
| [005](005-bundled-integrity.md) | Reject inconsistent bundled content in Release builds | Opus xhigh | Jupiter | 001 | RELEASED |
| [006](006-location-wait.md) | Bound one-shot location waits and reject invalid fixes | Sol xhigh | Luna | 003 | RELEASED |
| [007](007-card-index.md) | Add the planned quick card index to native decks | Opus xhigh | Mars | 010 | RELEASED |
| [008](008-compass-validity.md) | Stop reporting Qibla alignment from invalid or stale headings | Sol xhigh | Jupiter | 007 | RELEASED |
| [009](009-settings-save.md) | Keep reading settings consistent when SQLite rejects a change | Sol xhigh | Luna | 004 | RELEASED |
| [010](010-native-verification.md) | Make native model tests runnable on Linux | Sol xhigh | Luna | 005 | RELEASED |

## Ordering

Start 010 for app-unit-test infrastructure and 001 for the known core failures. Once 010's actual Linux tests pass and its opposite-family reviewer approves the exact infrastructure head, later model tasks can use the portable target. Required device cases remain separate and open where unrun. Coordinate 007's design contract with 005 before its implementation. Review every change with the paired opposite-family seat, and integrate serially. A review is read-only; revisions return to the original executor. Recheck the exact final commit before merge.

The earlier Linux/iOS workflow commit `9423e08` is locally recorded. Task 005 reviews that Sol-authored work before it is published. The Feather IPA 1.0 build 1 was published and verified separately; these follow-ups do not overwrite that version.

## Scope decisions preserved

Publisher identity, App Store/TestFlight, physical-iPhone notification delivery, launch-region authorities and future content/religious-review approvals remain separate gates. The backup envelope's seven-entry limit is deliberate and distinct from the newer session date window. Unbounded native SQL history must remain intact. Suwar/tasbih/new adhkar collections, tracker, search/favorites and other deferred product features are outside this bounded wave. No pending issue is closed merely because native code exists or because its human decision appears obvious.

## Preparation coverage

Directly inspected native sessions/storage, app/deck models, notifications, location, compass, content loading, project scheme, existing fixture/UI tests and planning documents. No new audit agents were started while predecessors were active. This pass does not claim a full PWA/security audit or a physical-device test.

## Findings considered and rejected

- Envelope-v1 history limit of seven: explicit schema contract; do not silently expand it when fixing session parity.
- Unbounded database history: already the storage policy; do not delete rows for PWA parity.
- New religious collections and suwar bundling: require content/scope decisions beyond this wave.
- Tracker, backup UI and new notification features: sequencing gates remain pending; this wave fixes existing code.
