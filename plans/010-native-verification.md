# Make native model tests runnable on Linux

Planned on 2026-10-13; revised after the Linux-only instruction and independent-work START on 2026-10-14.
Executor: GPT-6.1 Sol xhigh on Luna. Independent final reviewer: task 005, Opus 5.5 xhigh.
Dependencies: None; full core verification incorporates task 001's history fix.

## Goal

Add meaningful production-source XCTest for the portable native deck/content models and a bounded Linux core runner. Keep the iOS app-unit target available without claiming its runtime cases executed on Linux. Compile real app sources against the existing iOS SDK where supported. Preserve Release behavior, source-of-truth content and resource ownership.

## Scope

ios/project.yml; ios/Package.swift and its pinned resolution; ios/AthkarPortableTests/; ios/AthkarTests/NativeTestSupport.swift and TestInfrastructureTests.swift; AppModel initializer access only; BundledContent.swift CryptoKit/Crypto import only; tools/test-native-core.sh; tools/test-native-models.sh; tools/ios-linux-compile.sh; docs/agents/ios-linux.md; README testing guidance. A source-only ownership fix in the historical Mac runner is allowed; existing remote jobs and copies remain untouched.

## Execution

Select the actual DeckModel, AdhkarDeckModel, RuqyahDeckModel, ArabicFormat, BundledContent and TestHooks sources with a deterministic target layout. Use the official swift-crypto dependency pinned to a compatible reviewed release and record its exact resolved revision. Keep that dependency confined to the portable package. Load repository content in place or into a unique runtime scratch bundle; commit no duplicate packs and use no process-global content override in parallel tests.

Create real in-memory database/content regressions. Add the Xcode XCTest target/scheme and narrow initializer access where needed. Linux runners select installed tools, use unique scratch paths, acquire the shared then project lock nonblocking, limit Luna to two jobs, and retain ownership until their entire native process tree is terminal. Prove TERM/INT and zero-selected-test failure with isolated harmless fixtures. Support Debug and Release tests. Record actual XCTest method identifiers/counts separately from the AthkarCore Swift Testing summary.

The SDK adapter uses existing tooling and real sources/resources. No SDK installation/configuration, Apple identity/signing changes, host provisioning, live CI migration, copied model implementations or Apple API shadows. A compiled bundle executes no tests and is not an installable app; record compiler and packaging failures honestly. Keep the historical Mac/Feather result dated and its runner retired from new verification.

## Verification and delivery

Run bash syntax, shellcheck and meaningful ownership/argument/count fixtures. Under the granted Linux queue, execute portable production-source XCTest and the relevant core suites; full core gates incorporate task001. Run the supported SDK compile separately. Preserve religious text and golden fixtures; run content/export checks and git diff --check.

Return signed-off commits, a source bundle and structured exact-head evidence with host, commands, outcomes, executed methods, required unrun cases, owned process identities and released locks. App-unit AppModel and UI/Launch cases require an authorized iOS device result and remain open when unrun. The coordinator owns opposite-family review, serial integration, current-main gates, PR linking and post-merge monitoring.
