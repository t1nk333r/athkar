# Native verification from Linux

All new iOS checks run on Linux under the current user instruction and
`/home/t1nk33r/.agents/AGENTS.md`. The coordinator owns the native execution queue.
Source work and light shell checks may proceed before a native grant. Return a
`linux-request.json` with the exact head, commands, selectors and required gates;
do not start a native run without that turn's grant.

| Check | Tool and host | Evidence |
| --- | --- | --- |
| AthkarCore rules, SQLite storage, content, backups and prayer calculations | Installed Linux Swift, Luna | Nonempty Swift Testing summary and exit status |
| Portable app deck models, bundled content and production database writes | Installed Linux Swift and real swift-crypto, Luna | Executed production-source XCTest method identifiers, count and exit status |
| All app sources and optional app-unit test compilation | Existing Linux Darwin SDK, Luna | Compiler and packaging outcomes, zero executed tests |
| Ad hoc signed sideload IPA | Existing Linux Darwin SDK, actool and rcodesign, Luna | IPA path, size, SHA-256 and archive checks; no runtime result |
| AppModel integration, UI, accessibility, location, heading, haptics and notification delivery | An authorized iOS device route orchestrated from Linux | Exact device, test identifiers and runtime result |

Linux XCTest covers the production files selected by `ios/Package.swift`. It
does not import CoreLocation, UserNotifications or SwiftUI. AppModel's iOS
dependencies therefore remain outside that portable target. A compiled Darwin
XCTest bundle cannot execute as Linux XCTest. Keep its compilation result
separate from tests that actually ran.

## Installed tools

On Luna, inspected on 2026-10-14:

- `/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift` reports Swift 6.4,
  `swift-6.4-RELEASE`, target `x86_64-unknown-linux-gnu`.
- `/home/t1nk33r/.local/bin/xtool` reports commit
  `f0a1f90efdbb0dc023e276ff529da92618da7a87`. Its app build route takes a SwiftPM
  project and exposes no job-count argument. The bounded repository adapter uses
  SwiftPM directly instead.
- The existing `~/.swiftpm/swift-sdks/darwin.artifactbundle` contains iOS 27.0 SDKs,
  toolset metadata and Apple XCTest frameworks. Implicit `swift sdk list` found
  no SDKs during inventory. Explicit selection works:

```bash
/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift sdk list \
  --swift-sdks-path /home/t1nk33r/.swiftpm/swift-sdks
# darwin
```

SDK inventory must supply this directory explicitly. Set
`ATHKAR_SWIFT_SDKS_PATH` if the same existing bundle lives elsewhere. It does not
install SDKs or modify their metadata. SDK discovery is not compiler verification.
Mars and Jupiter lack Swift/xtool; send their committed source bundles to the
coordinator. Do not provision hosts or use Terra for new checks.

The portable package pins official `apple/swift-crypto` 5.0.1. Its manifest
requires Swift 6.2, which Luna's Swift 6.4 satisfies. BundledContent uses CryptoKit
on Apple platforms and Crypto on Linux, with the same SHA-256 operation.
`ios/Package.resolved` records the actual resolved revisions, including
swift-crypto `1c80d3aff53fedc445b60692980cb4f19a618657`. Runs use that lockfile with
`--force-resolved-versions`. A dependency update must resolve in an isolated
snapshot, return the generated resolution file for a signed-off source revision,
and rerun the committed head.

## Queue ownership and isolated output

The runners acquire `/tmp/hikaya-build-suite.lock` first, then
`/tmp/athkar-build-suite.lock`, using nonblocking exclusive flock. A busy lane
returns exit 3. If the project lane is busy, the runner immediately releases the
shared lane. It never waits while holding only one lock and never removes a
shared lock file. Existing lock files are not evidence that a lane is free.
`ATHKAR_SHARED_BUILD_LOCK` may select an absolute shared-lane path for a separately
coordinated host or harmless fixture. Luna's native grants use the default above.

The runners select `ATHKAR_SWIFT`, Swift on PATH, or the installed Swift 6.4 path.
They accept only one or two build jobs and disable test parallelism. They archive
the exact clean Git HEAD into a fresh directory outside the checkout. Tests retain
the whole repository because core fixtures and portable content use repository
paths. Scratch, dependency caches, test bundles and logs belong to that run.

### Affected tests

`tools/test.sh` runs every lane, each for only what the changes since the merge base with
`origin/main` reach: the selector's own tests, the Node content checks, the core and portable
suites and the app's SDK compilation. It lists the app-unit and UI classes that need a device or
the Mac, and the AthkarTests compilation, whose bundle packaging still fails on Linux (below).
`tools/test.sh --plan` prints each lane's selection and the reason without running anything.
`--base REF` compares with another branch or commit, and `--all` runs every lane in full. The
last line is `RESULT status=pass|fail|incomplete lanes=<lane>:<outcome>,...`. A busy build lane
is `busy`, and uncommitted changes leave the native lanes `unavailable`.

`tools/affected-tests.py` makes the selection. A test runs when it depends on a changed file
through the Swift code compiled into its target, or reads a changed fixture, pack or data file.
A removal also reaches the files still using the removed name. A UI test checks the app files in
its `UI_BLACK_BOX` entry and every app file that spells an accessibility identifier it uses,
directly or through a `UITestSupport.swift` helper. Documentation runs nothing.
`ios/Package.swift`, `ios/project.yml`, the lockfiles, these runners, any file no rule maps and
any selector error run everything.
`python3 tools/affected-tests.py check` fails when a rule no longer matches the repository.
`python3 tools/affected-tests-test.py` tests the rules against fixture changes.

After the coordinator grants the selected check, run from the checkout:

```bash
ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/test-native-core.sh --jobs 2

ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/test-native-models.sh --jobs 2 -c release

ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/test-native-core.sh --jobs 2 --filter 'Storage|BackupContentTests'
```

Without `--filter`, each runner runs only the suites or classes the committed changes reach.
It prints them with the reason, and exits 0 with "Nothing to run" when no change reaches the
suite. `--base REF` changes the comparison, `--all` runs the whole suite, and `--filter REGEX`
runs an explicit selection. The full core suite follows Task
001's integrated history fix. `--results /absolute/new-directory` selects a fresh
output directory with an existing parent. Otherwise the runner creates a unique
directory under `$XDG_CACHE_HOME/athkar-native-checks` or
`$HOME/.cache/athkar-native-checks`. It prints the output path and retains:

- `resource.log`, with host, source head, lane paths, ownership, process/group IDs
  and terminal/release state.
- `toolchain.log`, `command.log`, `check.log` and `exit-status`.
- `repo/`, the source snapshot, and private `scratch/`, caches and test data.

Count the final Swift Testing result for core coverage. An earlier XCTest
"Executed 0 tests" line is not the Swift Testing count. For portable coverage,
record the actual `PortableModelTests` XCTest method names and count. The runners
fail a zero-test selection even if Swift exits successfully.
Release test runs explicitly pass `-Xswiftc -enable-testing` so XCTest can import
the actual production module with `@testable`.

### Caller-held lanes

A coordinator that already owns both locks can pass their inherited descriptors.
The wrapper verifies each descriptor's exact lane path and exclusive flock in
`/proc`. An environment claim alone is insufficient. For example, inside the
coordinator's granted turn:

```bash
(
  exec 8>>/tmp/hikaya-build-suite.lock
  flock -n 8 || exit 3
  exec 9>>/tmp/athkar-build-suite.lock
  if ! flock -n 9; then
    exec 8>&-
    exit 3
  fi
  tools/test-native-core.sh --caller-held-locks 8 9 --jobs 2 --filter Storage
)
```

The wrapper does not unlock the caller's file descriptions. The coordinator
releases them after the wrapper's terminal return. For runner-owned lanes,
cleanup waits for the owned Linux subreaper to reap the whole process tree before
closing lock descriptors or writing the completion marker. The subreaper adopts
orphaned children, including descendants that start separate sessions. TERM/INT
cleanup signals only those owned processes, allows five seconds for termination,
then kills resistant owned descendants and waits for their actual exit.
Never stop shared daemons,
historical jobs or processes belonging to another owner.

## Compile against the existing iOS SDK

Request a separate SDK turn before running either command:

```bash
ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/ios-linux-compile.sh --jobs 2

ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/ios-linux-compile.sh --jobs 2 --build-tests
```

The adapter stages the exact shipped manifest, adhkar/ruqyah packs, both fonts
and city list in its isolated snapshot. SDK mode selects every actual app source
and the real assets. The adapter follows the installed xtool revision's
[SwiftBuild settings](https://github.com/xtool-org/xtool/blob/f0a1f90efdbb0dc023e276ff529da92618da7a87/Sources/PackLib/BuildSettings.swift#L58-L70).
SwiftPM uses `--build-system swiftbuild`, `--triple arm64-apple-ios`, the existing
`toolset-swb.json` and at most two jobs. The command environment supplies
`XCODE_EXTRA_PLATFORM_FOLDERS` with the existing bundle's `Developer/Platforms`,
prepends its `toolset/bin` to PATH and unsets SDKROOT. These settings apply only
to this process. The optional test build selects `AthkarTests`, enables testable
imports and adds the SDK's actual XCTest framework search path.

SwiftBuild may invoke the existing actool for asset-symbol generation, even with
copied catalogue resources. This adapter does not execute iOS tests, sign an app or
install anything; `tools/ios-linux-ipa.sh` packages the app (below). Report the exact
compiler outcome, each failed build/packaging step and the retained log. A
successful source compilation leaves packaging and device gates open. The initial
2026-10-14 attempt using `--swift-sdk` failed before source compilation with
`unable to find platform for 'iphoneos'`. With xtool's documented platform search
path and toolset, app compilation passed at `c49655124e4159b904db54504ba700d54802ac1d`.
App-unit sources compiled and linked at `39832e4c7033accbcd601996f84d0af9097990f3`,
then XCTest bundle packaging failed in `CopySwiftLibs` with
`Passed --strip-bitcode without --strip-bitcode-tool.` Both runs executed zero
tests and produced no installable IPA. Use the exact run's retained outcome when
verifying a later head. Hikaya's inert CI
candidate is not an approved route. Leave live CI and historical remote jobs
unchanged.

## Package a sideload IPA

`tools/ios-linux-ipa.sh` builds the app on Linux and packages an ad hoc signed IPA
for Feather. Request a native turn for it like any other SDK build:

```bash
ATHKAR_SWIFT=/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift \
  tools/ios-linux-ipa.sh --jobs 2 --wait
```

It holds both lanes for the whole build, in the runners' order. A busy lane exits 3
and names its holder. `--wait` retries every 150 seconds for up to 90 minutes and
holds no lock while it waits. The tool archives the clean HEAD and runs XcodeGen 2.46.0
in that snapshot. The committed `ios/Athkar.xcodeproj` and `ios/Athkar/Info.plist` must
equal the regenerated files. It then builds Release through `tools/ios-linux-compile.sh`
with the lanes it holds. `tools/ios-linux-ipa.py` lays out `Payload/Athkar.app` from the
generated project's Release settings, Info.plist and Resources phase:

- Each resource file is copied byte for byte. The SDK's actool compiles the asset
  catalogue into `Assets.car` and the loose icons, and SwiftBuild's `GRDB_GRDB.bundle`
  is included.
- The generated Info.plist gains Xcode's build keys. The DT keys come from the iOS 27.0
  SDK and the Xcode 27.0 record that xtool kept for it.
- Build-host rpaths are dropped, and LC_BUILD_VERSION records SDK 27.0 instead of the
  deployment target that the Linux link writes.
- rcodesign 0.29.0 signs ad hoc, with no identity and no entitlements. Like Xcode, it
  seals `GRDB_GRDB.bundle` in the app's `CodeResources`. The zip carries no extended
  attributes.

The tool writes `Athkar-<CFBundleShortVersionString>+<CFBundleVersion>-linux.ipa` and
its `.sha256` to `~/Projects/athkar-builds` or `--out`. It never replaces an IPA. Before
publishing, it checks the archive: architecture, LC_BUILD_VERSION, every code page and
special-slot hash, sealed resources, each resource against the repository and the pack
digests against `manifest.json`. `rcodesign verify` cannot serve as that check, because
it rejects every ad hoc signature, including the Xcode build's. Results hold
`resource.log`, `toolchain.log`, the XcodeGen and package logs, the compile runner's own
`build/` directory and a `.done` exit marker.

The Linux actool's loose-icon downsampler (darwin-tools `d993142`) writes solid white
PNGs. SpringBoard can read those files when its `Assets.car` lookup misses. The tool
detects a uniform icon from a varied source and replaces it with the same area average,
computed from that source. Remaining differences from the Xcode-built 1.0 (1) IPA:
there is no `BuildMachineOSBuild`, `Assets.car` and the PNGs are not Xcode's bytes, the
PNGs are standard rather than CgBI, the code directory uses 4 KiB rather than 16 KiB
pages, and the binary keeps SwiftBuild's `@loader_path` rpath instead of
`@executable_path/Frameworks`.

A Linux-built IPA has not been run on a device until someone installs it. Packaging,
the signature check and the comparison above are not runtime evidence; Feather re-signs
the app when it installs it. Publishing remains the coordinator's step. This tool does
not read the Feather token, publish or install anything.

## Required runtime cases and historical results

`AthkarTests` is a hosted app-unit target. Starting its host runs the normal
`AthkarApp` entry point, which opens `Application Support/Athkar/athkar.sqlite`
through `AppModel.launch()` and attaches and replans reminders. The tests' own
in-memory databases do not isolate that host startup. The host bundle identity is
`local.dev.athkar`, matching the user's existing Feather installation. No current
device run against that installation is approved. Runtime acceptance requires a
separately authorized, isolated route that preserves the user's app, database and
notifications. Do not use `--reset-data`, uninstall, change bundle identity,
pairing or device permissions under this source-verification grant.

`ios/project.yml` is authoritative. The committed `ios/Athkar.xcodeproj` was
regenerated from it on Luna with XcodeGen 2.46.0. It includes the hosted
`AthkarTests` target and both test targets in the shared scheme. Xcode has not
opened it; a future authorized Xcode route must verify the project before use.
No new Mac work or changes to historical jobs and their running copies are
authorized by this infrastructure work.

After a `project.yml` change or an added or removed source file, regenerate on
Linux. Build tag `2.46.0` (commit `8445e778451c7e44237b90281bde622d764b0084`) in a
new directory outside every repository, holding both lane locks:

```bash
git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen "$src"
/home/t1nk33r/.local/share/swift-6.4.0/usr/bin/swift build -c release --jobs 2 \
  --package-path "$src" --scratch-path "$scratch" --force-resolved-versions \
  --product xcodegen
```

Keep `$src` in place, because the binary also looks there for its setting
presets. From the root of a clean checkout, run
`"$scratch/release/xcodegen" generate --spec ios/project.yml`. Commit the
regenerated `ios/Athkar.xcodeproj`, and explain any other changed file.

Without an authorized iOS device result, these app-unit cases remain required
unrun:

- `TestInfrastructureTests.testBundledPacksRecordActualChecksumsAndVersions`
- `TestInfrastructureTests.testAppModelBuildsDecksFromBundledContent`
- `TestInfrastructureTests.testInMemoryModelsPersistWithoutSharingDatabaseState`
- `AthkarUITests/LaunchTests.testLaunchShowsPrayerRow`

Keep any task's UI, accessibility, sensor, notification, allocation and device
acceptance criteria open as well. A remaining required runtime gate means
`BLOCKED`, even when committed source is ready for paired review. The coordinator
integrates reviewed source serially; workers do not merge or settle themselves.

`tools/ios-mac-run.sh` is retired from current verification. Its historical
signal cleanup does not provide the required process-tree and marker lifetime.
Its `test` action passes `-only-testing` for just the app-unit and UI classes the
changes reach. The selection compares with `origin/main`, so it needs a Git
checkout with that branch, or `--base REF`. `--all` runs both targets, and a single
test identifier still selects that test.
Leave existing historical jobs and their running copies untouched. Do not use
the runner for new checks or request Mac keys, wake-up or provisioning. Preserve the
user's physical-device data and the existing signing/publisher identity.

XcodeGen generates `ios/Athkar/Info.plist`. Declare future version/build bumps in
`ios/project.yml` under `targets.Athkar.info.properties`, using
`CFBundleShortVersionString` and `CFBundleVersion`. Their current values are
`1.1` and `2`. Feather already has `1.0` (`1`) and never replaces the bytes of an
existing version, so every published IPA needs a new pair.

Historical evidence from 2026-10-13 predates this infrastructure: Linux Swift
Testing ran 108 tests in 23 suites, with four session history-fixture failures.
History PR #16 resolved that divergence. Its exact publication head
`e446f126770473df455ae7c4bf0917181f95e7ef` passed all 114 Swift Testing declarations
in 24 suites on Linux on 2026-10-14, including all 22 loadState and ten rollover
fixtures. Pages passed at merge commit `1c8ce891bcda7b6edb74496e8143d62c19c6b39f`.
This is a core-only result, with zero XCTest methods and no device/runtime claim.
The historical Mac simulator passed the single
LaunchTests case, and Feather published `local.dev.athkar` version 1.0, build 1,
with 4,513,557 bytes. Its downloaded SHA-256 matched
`4ca66bbe9a61ec0d5c2be28e148517fadccb483ee1571478d4fe29ad7ada79bd`.
Those records do not verify the current source head or the new tests.
