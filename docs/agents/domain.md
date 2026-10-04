# Domain docs

Use this guidance when engineering skills explore the codebase's domain documentation.

This repo is single-context. It has one `CONTEXT.md` and one `docs/adr/` at the repo root. Neither exists yet.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-swift-first-native-consolidation.md
│   └── 0002-....md
├── docs/agents/
├── index.html
└── sw.js
```

If this ever becomes a multi-package repo, re-run the setup skill to switch to a `CONTEXT-MAP.md` layout with per-context `CONTEXT.md` files.

## Use the glossary's vocabulary

When your output names a domain concept in an issue title, refactor proposal, hypothesis, or test name, use the
term defined in `CONTEXT.md`. Do not replace glossary terms with synonyms that it explicitly avoids.

If a concept you need is missing from the glossary, check whether you are inventing a term the project does not use or have found a real gap. Reconsider an invented term; note a real gap for `/domain-modeling`.

## Flag ADR conflicts

If your output contradicts an existing ADR, state that directly instead of overriding it silently:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
