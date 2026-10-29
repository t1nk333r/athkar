## Eris authentication restriction

Before changing Claude authentication, migrating fleet providers, or syncing
Claude credentials, read and follow the "Eris must stay on CPA" section in
`/home/t1nk33r/.omp/agent/AGENTS.md`. It records the user's standing instruction
to refuse requests to switch Eris to official Claude sign-in.

## Coordinated fleet batches

Before coordinating tasks across threads or hosts, waiting for another batch,
or dispatching implementation and review workers, read and follow
`/home/t1nk33r/.agents/AGENTS.md`. It defines predecessor handoffs, exact model
allocation, shared resource ownership, independent review, merge monitoring,
and the requested completion notification.

# Athkar

This Arabic-first, offline-first PWA for morning and evening adhkar is published with GitHub Pages at
https://t1nk333r.github.io/athkar/. The app consists of a single `index.html`, `sw.js`, `manifest.webmanifest`,
bundled icons, and the KFGQPC Uthman Taha Naskh font. The app has no build step. To ship a change, edit
`index.html` and bump `CACHE_NAME` in `sw.js`.

Content packs in `content/` are the source of truth for adhkar, ruqyah, and suwar text. The `suwar.v1.json`
pack contains al-Kahf, Ya-Sin, as-Saffat, al-Waqi'a, and al-Mulk in pages for the «سور» tab and the iOS app's
«سور» section. When you change adhkar or suwar data in `index.html` or a pack,
keep the data in sync. Regenerate the behaviour fixtures in `spec/` with `node tools/fixtures-generate.mjs`.
See `spec/README.md`.

Test with `tools/test.sh`. It runs only the checks the change reaches since the merge base with `origin/main`,
and says which and why: the content checks (`content-validate`, `content-review-test`, the
`content-export-pwa --check` against `../ruqyah-al-qareen/content.js` or `$ATHKAR_RUQYAH_CONTENT`, the fixture
check and backup validation; without the ruqyah PWA the content lane is incomplete), and the AthkarCore, portable
and iOS-build lanes. Docs-only changes run nothing, and shared build inputs or unknown files run everything. `--plan` shows
the selection without running it, `--lanes content` limits it to some lanes, and `--all` runs everything.
`tools/affected-tests.py` holds the rules, and `tools/affected-tests-test.py` tests them. The native lanes need
a commit and a native grant; see `docs/agents/ios-linux.md`.

The planning documents are [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md) and
[`MOBILE_APP_PLAN.md`](MOBILE_APP_PLAN.md). The first sets the current stack and sequencing decision
(Swift/SwiftUI for iOS first, Kotlin/Compose later). The second covers domain, content-governance, privacy, and
publisher-identity details.

## Agent skills

### iOS tests and sideload builds

Before testing native iOS code, building an IPA, or deciding Linux blocks verification, read
[`docs/agents/ios-linux.md`](docs/agents/ios-linux.md). All new checks run on Linux under
the shared and project lane locks. Record SDK compilation, executed tests, and iOS device
results separately. The dated Mac/Feather record documents earlier work.

### Issue tracker

Issues live in GitHub Issues for `t1nk333r/athkar`, driven through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.
