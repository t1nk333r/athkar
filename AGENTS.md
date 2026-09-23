# Athkar

Arabic-first, offline-first PWA for morning and evening adhkar, published with GitHub Pages at
https://t1nk333r.github.io/athkar/. The app is a single `index.html` plus `sw.js`, `manifest.webmanifest`,
bundled icons, and the KFGQPC Uthman Taha Naskh font. There is no build step: editing `index.html`
and bumping `CACHE_NAME` in `sw.js` is how a change ships.

Content packs in `content/` are the source of truth for adhkar and ruqyah text. After changing
adhkar data in `index.html` (or a pack), keep them in sync and run
`node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah ../ruqyah-al-qareen/content.js`.
Behaviour fixtures in `spec/` are regenerated with `node tools/fixtures-generate.mjs`; see `spec/README.md`.

Planning documents: [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md) is the current stack and sequencing
decision (Swift/SwiftUI iOS first, Kotlin/Compose later); [`MOBILE_APP_PLAN.md`](MOBILE_APP_PLAN.md)
holds the domain, content-governance, privacy, and publisher-identity detail.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `t1nk333r/athkar`, driven through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.
