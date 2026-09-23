# Content review log

Every text or order change to a pack needs a row here before its version can bump
(NATIVE_APP_PLAN.md 5.3). `manifest.json` points each pack at the row that covers its current
version; `tools/content-validate.mjs` enforces the link. Rows are append-only and identified by a
sequence id, not a date. The **Reviewer** column must name a person for any version after 1.0.0.

| ID | Pack | Version | Reviewer | Scope | Outcome |
| --- | --- | --- | --- | --- | --- |
| R1 | adhkar | 1.0.0 |  | Baseline: morning-01…morning-26, evening-01…evening-24 extracted verbatim from index.html; no text change | Shipped PWA text; ayat al-kursi deviations recorded in reference/exceptions.json pending review |
| R2 | ruqyah | 1.0.0 |  | Baseline: all 15 segments extracted verbatim from ruqyah-al-qareen content.js; no text change | Shipped PWA text; matches both references |
