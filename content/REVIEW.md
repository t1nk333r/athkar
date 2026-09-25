# Content review log

Every text or order change to a pack needs a row here and a version bump (NATIVE_APP_PLAN.md 5.3).
`manifest.json` points each pack at the row that covers its current version. Each row records the SHA-256 of
the exact pack file it approved (`shasum -a 256 content/<pack>.v1.json`); `tools/content-validate.mjs` fails
when the pack's SHA-256 differs from the one its row approved, and when a pack's rows do not bump its version,
so an unreviewed change cannot ship. Rows are append-only and identified by a sequence id, not a date. The
**Reviewer** column must name a person for any version after 1.0.0.

| ID | Pack | Version | Pack SHA-256 | Reviewer | Scope | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | adhkar | 1.0.0 | d5f1e0e814b701fb6cb20bf7b8dd4493552df99c5f501b7d8a6d6eb358909e60 |  | Baseline: morning-01…morning-26, evening-01…evening-24 extracted verbatim from index.html; no text change | Shipped PWA text; ayat al-kursi deviations recorded in reference/exceptions.json pending review |
| R2 | ruqyah | 1.0.0 | a7a3dc2172268088aa3295a9fc2f23973fcb0a14b39891c07e2fd5018274bfcf |  | Baseline: all 15 segments extracted verbatim from ruqyah-al-qareen content.js; no text change | Shipped PWA text; matches both references |
| R3 | adhkar | 1.0.1 | becbe67effba87898692f24e8d9ff299aaf4cebd300b6662be1ef4de121f8148 | t1nk333r | morning-25, evening-23: detail citation «(سورة الأحزاب/56)» → «(سورة الأحزاب/٥٦)» (Arabic-Indic digits, matching every other number on screen); no Quran text or order change | Approved |
| R4 | ruqyah | 1.0.1 | 6f84db7ade29161d3b7ae756fe8a6ba45b962c35225e33cdd891cba013e5ff89 | t1nk333r | jinn-8-13, al-Jinn 72:9: «ٱلْءَانَ» → «ٱلْأٓنَ», the King Fahd Complex's spelling (HAFS 3.0 mushaf text); the two Uthmani references keep the old spelling, recorded in reference/exceptions.json. No other text or order change | Approved |
