# Athkar

This Arabic-first, offline-first PWA for morning and evening adhkar is published with GitHub Pages at
https://t1nk333r.github.io/athkar/. The app consists of a single `index.html`, `sw.js`, `manifest.webmanifest`,
bundled icons, and the KFGQPC Uthman Taha Naskh font. The app has no build step. To ship a change, edit
`index.html` and bump `CACHE_NAME` in `sw.js`.

Content packs in `content/` are the source of truth for adhkar, ruqyah, and suwar text. The `suwar.v1.json`
pack contains al-Kahf, Ya-Sin, as-Saffat, al-Waqi'a, and al-Mulk in pages for the «سور» tab. It is not in
`manifest.json` until the iOS app bundles it. When you change adhkar or suwar data in `index.html` or a pack,
keep the data in sync. Then run `node tools/content-validate.mjs` and
`node tools/content-export-pwa.mjs --check --ruqyah ../ruqyah-al-qareen/content.js`.
Regenerate the behaviour fixtures in `spec/` with `node tools/fixtures-generate.mjs`. See `spec/README.md`.
After changing the REVIEW.md rules in `tools/content-validate.mjs`, run `node tools/content-review-test.mjs`.

The planning documents are [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md) and
[`MOBILE_APP_PLAN.md`](MOBILE_APP_PLAN.md). The first sets the current stack and sequencing decision
(Swift/SwiftUI for iOS first, Kotlin/Compose later). The second covers domain, content-governance, privacy, and
publisher-identity details.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `t1nk333r/athkar`, driven through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.
