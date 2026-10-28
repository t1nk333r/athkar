# Athkar project map

## [TECH_STACK]

- PWA: HTML, CSS and JavaScript with a service worker; no build step.
- Native iOS: Swift 6, SwiftUI, SwiftPM and an XcodeGen project under `ios/`.
- Native tests: AthkarCore Swift Testing and portable production-source XCTest on Linux;
  iOS UI/device cases retain their runtime requirements.
- Sideload delivery: the dated 1.0/1 IPA is on Feather and re-signed by the client.

## [SYSTEM_FLOW]

Content packs feed both the PWA and bundled native resources. New checks run on
Linux under the shared build lane and Athkar project lock. SDK compilation,
executed portable tests and iOS device results are separate evidence. The earlier
Feather publish was verified against the downloaded IPA's checksum.
That historical 1.0/1 IPA predates the current native haptics and follow-up changes.
Dhikr counters vibrate only on the tap that completes a target greater than one,
in both the PWA and native decks. Native ruqyah, like the ruqyah PWA, vibrates on
the tap that completes any segment. Single-count dhikr cards and earlier taps stay
quiet.

## [ARCHITECTURE]

- `content/`, `data/`, `fonts/` and `spec/` hold shared inputs and behaviour fixtures.
- `ios/AthkarCore/` holds domain logic and storage without UI framework dependencies.
- `ios/Athkar/` and `ios/AthkarUITests/` hold the app and its UI tests.
- `tools/test.sh` runs only the checks a change reaches, lane by lane; `tools/affected-tests.py`
  selects them and `tools/affected-tests-test.py` tests the selection.
- `tools/ios-mac-run.sh` is retained for historical provenance; current checks use Linux.
- [`docs/agents/ios-linux.md`](docs/agents/ios-linux.md) owns the build/test procedure
  and recorded verification limits.

## [ORPHANS & PENDING]

- History PR #16 is merged. Its exact publication head passed 114 tests in 24 suites,
  and Pages succeeded at merge commit `1c8ce891`.
- PWA haptics PR #17 is merged and deployed at `4ab95cad`, with cache v66 verified.
- Task 010's source and portable tooling have independent review. Six production
  XCTest methods passed Debug and Release at source-equivalent component heads;
  app SDK compilation passed. Hosted TestInfrastructureTests and LaunchTests,
  native haptics/device cases and test-bundle packaging remain open.
- The physical-device notification matrix and App Store publisher identity remain
  release gates in [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md).
