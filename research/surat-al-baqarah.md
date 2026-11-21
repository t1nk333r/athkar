# Research: Surat al-Baqarah as one whole reading page

Asked by the owner: "research adding albaqarah to the app as the whole page not in shortened cards". That means
al-Baqarah (2:1–286) in full, read as one continuous page, not split into the few-ayah swipe cards of the «سور» tab.

Written 2026-11-21 against commit `3107295` (branch `fix/sleep-salawat-cards`, clean tree). All repository line
numbers refer to that commit. Upstream sources were read on 2026-11-21. Numbers marked "measured" come from the
downloaded upstream texts, processed with the validator's own transforms copied from `tools/content-validate.mjs`.

**Later on the same branch (PR #76):** «أذكار النوم» and «الصلاة على النبي ﷺ» became counted card decks.
`renderSleepPanel`, `#sleep-panel`, `.sleep-basmala`, `SleepView` and `SalawatView` are gone after it merges, and
migration `v6` is taken by `reading_item_progress`/`reading_days`. Read the sleep-page references below (D5, §2.1,
§2.2, §3.1, §4) as the `3107295` baseline, and take the page styles and the view pattern from that commit
(`git show 3107295:index.html`, `git show 3107295:ios/Athkar/Screens/SleepView.swift`).

---

## Decisions (recommended)

| # | Decision | Why, in one line |
| --- | --- | --- |
| D1 | **Show the sura as one continuous scrolling page** (option a). Divide it into the 48 Madani mushaf pages (2–49) with in-flow page headings. Mark juz' and hizb starts on those headings. Keep the ۞ quarter glyph that is already in the text. Add a jump index and an automatic resume position. | This is what was asked for. Short cards would need about 135 cards, more than the transfer limit of 64 pages per sura. Full mushaf-page cards do not fit a phone screen (§2). |
| D2 | **Put it in a new content pack** (working name `tilawah.v1.json`, pack `tilawah`, one sura `baqarah`). Do not add a sixth sura to `suwar.v1.json`. | `suwar` means daily page checklists in the PWA store, the iOS DB, transfer and history. A whole-sura reading page has different semantics, so a separate pack keeps every `suwar` consumer unchanged (§1.7). |
| D3 | **Use the same text pipeline as the suwar pack**: the `alquran-cloud:quran-uthmani` (Tanzil Uthmani) snapshot, checked against quran.com v4 `text_uthmani`, with the R13 «لأٓ» spelling. Al-Baqarah needs **three new handling rules** and **one exception** (§1.3). | With the existing rules, 18 of the 286 ayat fail against quran.com. With the three rules, only 2:181 still differs, and that is a real word-division difference. |
| D4 | **No daily completion.** Keep one persistent resume position (page and ayah) per device, with no ✓ and no history entry. A completion record ("ختمت السورة") is optional (open question Q3). | Recited aloud, the sura takes about 2 hours (Mishary al-Afasy's murattal is 7,264 s). The authentic virtues are about reading it at home and holding to it, not finishing it each day (§2.3). |
| D5 | **Navigation.** In the PWA, add a chip «البقرة» first in the «سور» picker (mushaf order). It swaps the deck for a reading panel. On iOS, add a row «سورة البقرة» in أخرى › أوراد right after «سور». | The PWA tab bar is already designed for exactly seven tabs (`index.html:2115-2134`). The iOS chips are tied to `DeckModel`, and أخرى rows already open non-deck pages such as Sleep (§4). |
| D6 | **Rendering.** In the PWA, render 48 `<section>`s with `content-visibility: auto` and restore by element, not by pixel offset. On iOS, use a `LazyVStack` of 48 page rows with `.scrollTargetLayout()` + `.scrollPosition(id:)` (iOS 17, the app's floor) and `ScrollViewReader` for jumps. Never set the sura as one `Text`. | Sleep sets al-Mulk (2,901 characters) as one `Text`/`<p>`. Al-Baqarah is 19 times larger (56,416 characters) and needs position tracking (§3). |
| D7 | **Virtues.** Show four short notes at the top of the page, each bound to a new `reference/hadith.tilawah.json` snapshot: Muslim 780, Muslim 804, Muslim 810 (Ayat al-Kursi) and Bukhari 5009 (the last two ayat), with Muslim 806 optional. The wording is in §2.4 and was checked against the validator's «…» rule. | This follows the sleep and salawat binding rules (`tools/content-validate.mjs:22-27, 379-387`). |

---

## 1. Text sourcing

### 1.1 What the suwar pack is today

- **Edition.** The edition is `alquran-cloud:quran-uthmani`, which is Tanzil's Uthmani text as served by
  api.alquran.cloud. It is fixed by the schema (`content/schema/suwar.schema.json` `edition.const`). Each ayah was
  "taken from the alquran-cloud.quran-uthmani snapshot (basmala dropped from ayah 1 and kept once as `basmala`)"
  (`content/REVIEW.md` R8, R9).
- **Validation.** Every ayah is compared against two sources: the alquran.cloud snapshot, exact except for the seat
  of a hamza after lam, and quran.com v4 `text_uthmani`, normalised for encoding
  (`tools/content-validate.mjs:4-16, 243-247, 331-337`). Snapshots live in `content/reference/*.json`. They are
  written only by `tools/content-reference-refresh.mjs`, which fetches whole suras
  (`content-reference-refresh.mjs:41-55`) and must run as a deliberate commit (`:2`).
- **Spelling convention.** The «لأٓ» convention comes from commit `a4971bf` (R13). Where a hamza with fatha after a
  lam is followed by an alef, packs write alef + hamza + madda joined to the lam, as the King Fahd Complex does. The
  validator maps the references only, so a pack that keeps «لـَٔا» still fails
  (`tools/content-validate.mjs:228-238`).
- **Font.** The text is shown in **KFGQPC HAFS Uthmanic Script 3.0** after `kfgqpcEncoding` / `MushafEncoding.kfgqpc`
  convert Tanzil's encoding to the Complex's (`index.html:7504-7535`;
  `ios/AthkarCore/Sources/AthkarCore/Content/MushafEncoding.swift:1-17`). Ayah numbers are written ﴿n﴾ with
  Arabic-Indic digits and set in Uthman Taha (`index.html:7538-7544`; `fonts/README.md`). The packs never store
  markers; the apps add them (`content-validate.mjs:205`).
- **Basmala.** One shared `basmala`, checked against the first four words of `n:1` in the alquran.cloud snapshot
  (`content-validate.mjs:197-198`). Al-Baqarah opens with it: quran.com `bismillah_pre: true`, and alquran.cloud
  prepends it to 2:1.

### 1.2 What al-Baqarah adds (measured)

| Quantity | Value | Source |
| --- | --- | --- |
| Ayat | 286 | alquran.cloud surah 2, quran.com `chapters/2` (`verses_count`) |
| Words | 6,116 tokens with letters in Tanzil. text_qpc_hafs has 6,136 tokens; the difference is the 19 ۞ marks and the split «بَعْدَ مَا» | measured |
| Characters (code points) | 56,416, against 14,202 for al-Kahf, the largest sura in the pack today | measured; `content/suwar.v1.json` |
| UTF-8 text | 106.5 KB | measured |
| Mushaf pages | 2–49 (48 pages). Page lengths are 343–1,461 characters, mean 1,175. Cards today are 235–512 characters | quran.com `pages:[2,49]`; measured |
| Juz' starts | 2:142 (juz' 2), 2:253 (juz' 3). Both fall at the start of a page (pages 22 and 42) | quran.com, Tanzil, alquran.cloud (§1.5) |
| Hizb quarters | 20 (rub' 1–20) | as above |
| Sajda | none | quran.com `sajdah_number` all null; Tanzil `QuranData.Sajda` has no sura-2 entry; alquran.cloud `sajda` false |
| Recitation length | 7,264,000 ms, about 2 h 01 min (al-Afasy murattal) | `api.qurancdn.com/api/qdc/audio/reciters/7/audio_files?chapter=2` |

### 1.3 Spelling findings specific to al-Baqarah

I ran the validator's comparison logic over all 286 ayat. The pack text was built as the suwar pack is: the
alquran.cloud text, then `tanzilHamzaSeat`, then `lamHamzaMadda`. Results:

- **23 «لأٓ» words** («وَبِٱلْأٓخِرَةِ», «لِأٓدَمَ», «ٱلْأٓيَٰتِ», «لَأٓيَةًۭ» …) and all the Tanzil bare-hamza-after-lam words
  are already handled by the R10/R13 rules. text_qpc_hafs has the same 23 «لأٓ» tokens, so the convention holds
  unchanged.
- **18 ayat fail with today's rules** (2:61, 71, 124–127, 130, 132, 133, 135, 136, 140, 177, 181, 187, 213, 258,
  260). There are three causes:
  1. **Small yeh inside a word (18 words).** Tanzil writes «إِبْرَٰهِۦمَ» (15×, the al-Baqarah-only spelling of
     Ibrahim without a full ya) and «ٱلنَّبِيِّۦنَ» (2:61, 177, 213) with U+06E6 ARABIC SMALL YEH. quran.com and the
     Complex write tatweel + U+06E7 SMALL HIGH YEH: «إِبْرَٰهِـۧمَ».
     - This matters for display, not only for validation. U+06E6 is General Category Lm, and ArabicShaping.txt gives
       Joining_Type U to unlisted non-Mn characters. Inside a word it therefore **breaks the cursive join**, so ه
       and م would be drawn unjoined. This is the same defect R10 fixed for the bare hamza.
     - **Rule:** the pack takes quran.com's spelling. The validator maps alquran.cloud's mid-word U+06E6 to
       U+0640 U+06E7 alongside `tanzilHamzaSeat`, with the regex `/ۦ(?=[ء-ي])/g`.
     - No current pack has a mid-word U+06E6 (measured: 0), so the rule cannot affect existing text.
  2. **Mark order in «ٱلْـَٰٔنَ» (2:71, 2:187).** quran.com writes «ٱلْـَٔـٰنَ». `quranComEncoding` deletes the
     tatweel before U+0670 *after* NFC has run, which leaves hamza-above (ccc 230) before the superscript alef
     (ccc 35).
     - **Rule:** end `quranComEncoding` with `.normalize("NFC")`. This is a one-line fix.
     - The Complex writes «ٱلۡـَٰٔنَ» here, not «ٱلۡأٓنَ» as in 72:9, because Tanzil has no full alef here.
       `lamHamzaMadda` correctly leaves it alone.
  3. **2:181 «بَعْدَمَا» (Tanzil, one word)** against «بَعْدَ مَا» (quran.com `text_uthmani` and text_qpc_hafs, two
     words). The house follows the King Fahd Complex (R4, R13), so the pack writes «بَعْدَ مَا». Record this in
     `content/reference/exceptions.json` against `alquran-cloud.quran-uthmani`, bound to the new review row. That is
     the documented path for reviewed deviations (`content-validate.mjs:16, 289-290, 365-368`).
- **Simulation result.** With rules 1 and 2 and the 2:181 spelling, **285 of 286 ayat equal both references**. Only
  2:181 is left, and the exception covers it.
- **Import caution.** Store the alquran.cloud text in its own mark order, **not NFC-normalised**. `kfgqpcEncoding`
  converts open tanween only when the small meem directly follows the tanween («كُلٌّۭ» stored as
  lam + shadda + dammatan + U+06ED). An NFC pass moves the tanween before the shadda, which silently breaks 21
  conversions in al-Baqarah. The validator compares NFC copies, so it would not catch this. The ruqyah reference
  shows the expected result: «كُلࣱّ» = U+0644 U+0651 U+08F1 (`content/reference/kfgqpc-hafs.ruqyah.json`, 50:14).

### 1.4 King Fahd Complex cross-check

- **The existing check.** `MushafEncodingTests` compares the converted ruqyah text, scalar for scalar, with the
  Complex's own text from the Word file shipped with HAFS v3.0
  (`ios/AthkarCore/Tests/AthkarCoreTests/MushafEncodingTests.swift:6-22`;
  `content/reference/kfgqpc-hafs.ruqyah.json` header, `docxSha256`).
- **Why quran.com is not a substitute.** quran.com's `text_qpc_hafs` uses other code points for open tanween
  (U+0656/U+0657/U+065E, not U+08F0–U+08F2). Even after mapping those, 63 ayat differ from our converted text:
  - most are waqf signs (ۗ against ۚ, ۙ missing);
  - ۞ is placed differently;
  - «هُدࣰى» keeps ى after open fathatan, where `kfgqpcEncoding` writes ي (4×; HAFS draws final ي undotted, so this
    may look the same);
  - 2:72 «فَٱدَّٰرَٰٔتُمۡ» and 2:97 «لِّـجِبۡرِيلَ» differ.
- **Recommendation.** Add `content/reference/kfgqpc-hafs.tilawah.json` with 2:1–286 taken from the same Word file
  (same `docxSha256`, so it is the same Complex text). Extend `MushafEncodingTests` to cover it. That settles which
  of the 63 differences are real in the Complex's text and which are differences between quran.com's text and the
  font. Fix any real gap in both encoders, JS and Swift, as one change with a test, as the ruqyah work did.

### 1.5 Page, quarter and juz' metadata: three sources agree

- **Page starts** for all 48 pages are identical in quran.com v4 (`page_number`), Tanzil `quran-data.js`
  (`QuranData.Page`) and alquran.cloud (`page` per ayah):
  2:1, 6, 17, 25, 30, 38, 49, 58, 62, 70, 77, 84, 89, 94, 102, 106, 113, 120, 127, 135, 142, 146, 154, 164, 170, 177,
  182, 187, 191, 197, 203, 211, 216, 220, 225, 231, 234, 238, 246, 249, 253, 257, 260, 265, 270, 275, 282, 283.
- **Quarter starts** are identical in quran.com (`rub_el_hizb_number`) and Tanzil (`QuranData.HizbQaurter`, Tanzil's
  spelling): 2:1, 26, 44, 60, 75, 92, 106, 124, 142, 158, 177, 189, 203, 219, 233, 243, 253, 263, 272, 283. Tanzil's
  text already carries ۞ (U+06DE) at the head of each of these 19 ayat after 2:1, so the quarter mark is already in
  the text.
- **Verse-level only.** All three sources assign a page per ayah, by its first word; for example 2:282 fills page 48.
  Page headings therefore go before an ayah, never inside one.
- **Recommendation.** Store the boundaries in the pack and check them against two layout snapshots written by the
  refresh tool: quran.com `page_number`/`rub_el_hizb_number`/`juz_number`, and alquran.cloud
  `page`/`hizbQuarter`/`juz`. This is the same two-source rule as the text. The reviewer should still spot-check a
  few page breaks against a printed Madinah mushaf (open question Q6).

### 1.6 Size

| Artifact | Today | With al-Baqarah | Basis |
| --- | --- | --- | --- |
| New pack JSON (pretty, 2-space) | none | about 130 KB (ayat 126 KB + markers + virtues) | measured |
| `index.html` raw | 638,788 B (not the ~550 KB assumed) | about 777 KB (+22%) | the inline literal with 6-space indent measured at 133 KB, like `suwarContent` (131 KB at `index.html:3011-5572`) |
| `index.html` gzip -9 | 135 KB | about 159 KB (+24 KB) | measured |
| iOS bundle | packs total 198 KB | +130 KB JSON (about +23 KB compressed in the IPA). Launch also SHA-256-checks and decodes it (`BundledContent.swift:219-245`), which is negligible | measured |
| Reference snapshots (repo only, not shipped) | 4 files × ~92 KB | about +100 KB each for the 282 new verses (2:201, 2:255 and 2:285–286 are already there) | measured |

Keep the data inline in `index.html`, as every other pack is. `tools/content-lib.mjs:15-23` (`loadPwaContent`) and
`content-export-pwa --check` depend on that. A separately fetched JSON file would save 24 KB gzip but add a second
precache entry and a new loading path.

### 1.7 New pack or a sura in `suwar.v1.json`

**Arguments for a sixth sura:** fewer files change (manifest, manifest schema, bundle lists).

**Arguments against, which decide it:**

- **Daily semantics.** Everything keyed by suwar pages is daily:
  - the PWA's `read`, `completedAt` and 7-day `history` (`index.html:6828-6860`, `rollSuwarStateToDate` at
    `:6911-6916`);
  - iOS `suwar_page_reads` / `suwar_sura_days` (`spec/schema.md:207-228`);
  - transfer `athkar.suwar` (`spec/transfer/transfer-v1.md:41`);
  - the history list and backup v2 (`spec/backup/envelope-v2.md:51-53`).
  Each of these would have to exclude al-Baqarah.
- **Picker code.** The PWA picker treats every `[data-sura]` chip as a deck sura (`index.html:8079-8089`).
- **iOS.** `SuwarDeckModel` builds cards from every sura (`ios/Athkar/Deck/SuwarDeckModel.swift:1-50`).
- **Shape.** A sura there must be `pages` of length-balanced cards (`suwar.schema.json:56-99`). The page IDs are
  keyed into the stores (`:72`) and limited to 64 per sura by transfer (`transfer-v1.md:109`).

**Cost of a new pack.** It is mechanical, and merge `9b94005` (sleep pack) is a ready template: 35 files, including
the manifest schema, `content-lib`, export, refresh, validate, `affected-tests.py`, `project.yml`, the pbxproj,
`BundledContent`, `DiagnosticsReport`, `HomeView`, `OtherSectionsView` and the UI tests.

**Proposed shape** (`content/schema/tilawah.schema.json`). The `suwar` array lets Al Imran (the other «زهراوين») be
added later with no schema change:

```json
{
  "pack": "tilawah", "version": "1.0.0", "edition": "alquran-cloud:quran-uthmani",
  "basmala": "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
  "suwar": [{
    "id": "baqarah", "surah": "سورة البقرة", "surahNumber": 2,
    "ayahs":    [{ "number": 1, "text": "الٓمٓ" }, "… 286, no ﴿n﴾ markers"],
    "pages":    [{ "page": 2, "from": 1 }, { "page": 3, "from": 6 }, "… 48"],
    "quarters": [{ "quarter": 1, "from": 1 }, { "quarter": 2, "from": 26 }, "… 20; juz' = ⌈q/8⌉, hizb = ⌈q/4⌉"],
    "virtues":  [{ "text": "قال ﷺ: «…» (رواه مسلم).", "hadith": "muslim:780" }]
  }]
}
```

The validator checks:
- ayat 1…286 are contiguous, with no ﴿﴾ in the text;
- `pages` and `quarters` ascend and equal both layout snapshots;
- the basmala matches;
- each virtue passes `checkNote` against `hadith.tilawah.json`;
- the sura ID is in a table (`["baqarah", "سورة البقرة", 2, 286]`), as `suwarTable` does at
  `content-validate.mjs:191`.

### 1.8 Import steps, in order

1. **Pack and refresh.** Generate `content/tilawah.v1.json` from the snapshot path, not by hand:
   1. Take alquran.cloud `quran-uthmani` surah 2 and drop the basmala from 2:1.
   2. Apply `tanzilHamzaSeat`, the new small-yeh rule and `lamHamzaMadda`. Do not run NFC.
   3. Write «بَعْدَ مَا» in 2:181.
   4. Add `pages` and `quarters` from the layout snapshots.
   Then add the pack to `content-reference-refresh.mjs` (the `wanted` loop, `:20-25`) and run it. `per_page=300`
   already covers 286, as measured. Check that the snapshot diff only adds verses.
2. **Validator.**
   - Load and schema-check the pack.
   - Add the small-yeh mapping and the NFC fix to `quranComEncoding`. Both are proven inert on the existing packs;
     check this by running `content-validate` before and after.
   - Add the structure, layout and virtue checks, and the summary line (`:425-429`).
   - Add `content-review-test.mjs` cases for the two new rules.
3. **Exception.** Add `exceptions.json` with the 2:181 entry and `reviewRecord: "R16"`.
4. **Hadith snapshot.** Add `reference/hadith.tilawah.json`, keyed as `hadith.sleep.json` is (`edition`,
   `hadithnumber`, `url`, `text`). The ara-muslim numbers are 780→1824, 804→1874, 806→1877, 810→1885, and
   bukhari:5009→5009.
5. **KFGQPC snapshot.** Add `reference/kfgqpc-hafs.tilawah.json` from the Complex's Word file (§1.4).
6. **Review and manifest.** Add a `REVIEW.md` row R16 (`tilawah`, 1.0.0, SHA-256) and the manifest entry. Add
   `tilawah` to `manifest.schema.json` (`required` and `properties`; `additionalProperties: false`).

### 1.9 Review row

The validator accepts a blank reviewer only at 1.0.0 (`content-validate.mjs:123`). Even so, a 286-ayah text should
ship with the owner named, as R12 and R13 did for suwar. A draft Scope cell:

> New pack for the «سورة البقرة» reading page (PWA «سور» chip, iOS «أخرى»): 2:1–286 from the
> alquran-cloud.quran-uthmani snapshot (basmala kept once as `basmala`), with the R13 «لأٓ» spelling (23 words) and
> quran.com's tatweel + small high yeh for 18 words («إِبْرَٰهِـۧمَ» ×15, «ٱلنَّبِيِّـۧنَ» ×3); 2:181 «بَعْدَ مَا» as
> quran.com and the King Fahd Complex write it (exception against alquran.cloud «بَعْدَمَا»). Page and quarter starts
> equal quran.com v4 and alquran.cloud. Virtues bound to reference/hadith.tilawah.json: Muslim 780, 804, 810, Bukhari
> 5009.

---

## 2. Presentation

### 2.1 Options compared

| | (a) One continuous page | (b) 48 mushaf-page cards in the deck | (c) Short cards (status quo) |
| --- | --- | --- | --- |
| Matches the ask | **Yes**: "the whole page" | Partly: whole pages, but still cards | No |
| Fit on a phone | Scrolls freely | A page is 343–1,461 characters (mean 1,175), against today's card maximum of 512. `fitSuraPage` steps the font down 6 times and then scrolls inside the card (`index.html:8012-8018`; iOS `FittedBody`, `DeckCardView.swift:223-246`), which fights tap-to-mark | Fits by design |
| Card count | 1 page | 48 | about 135 at al-Kahf's 418 characters per card. That is **more than the transfer limit of 64 pages per sura** (`transfer-v1.md:109`) |
| Progress model | Resume position | 48 daily page marks, lost at midnight (`rollSuwarStateToDate`) | 135 daily marks |
| Precedent in the app | Sleep and salawat pages (`renderSleepPanel`, `index.html:8382-8405`; `SleepView.swift`) | «سور» deck | «سور» deck |

**Recommendation: (a).** It keeps the mushaf's own structure through the page headings, which also answers the
"page" reading of the request if that is what the owner meant (open question Q1).

### 2.2 Layout of (a)

- **Top:** the title, the basmala (the `.sleep-basmala` style), the virtue block (§2.4), then a slim bar:
  «متابعة من الصفحة ٢٢» (resume) and «الفهرس» (index).
- **Page sections.** Each of the 48 Madani pages is a section with a small heading: «الصفحة ٢٢». When a juz' or
  hizb starts on the page, the heading adds «· الجزء ٢» / «· الحزب ٣». Juz' 2 and 3 and hizb 4 start exactly on
  page heads (pages 22, 42, 32), so no in-flow break is needed for them. Other quarter starts stay inline as the ۞
  already in the text.
- **Ayat.** The ayat flow inline with ﴿n﴾ markers, centred, exactly as `quranTextMarkup` sets text today.
- **Jump index** (a sheet). It has three groups:
  - by juz' and hizb quarter (20 entries: «الحزب ١», «ربع الحزب ١», «نصف الحزب ١», «ثلاثة أرباع الحزب ١», …), each
    with its page;
  - by page (2–49);
  - by ayah number (a numeric field, 1–286).
  Notable anchors can be listed: آية الكرسي (2:255, page 42) and خواتيم البقرة (2:285–286, page 49).

### 2.3 Progress semantics

- **Reading time.** About two hours recited. Many readers split it across days.
- **What the virtues say.** None of the authentic virtues ties reward to daily completion:
  - Muslim 780 speaks of the house in which al-Baqarah is read;
  - Muslim 804 speaks of «أَخْذَهَا» (holding to it) as blessing.
- **Recommendation.** A daily ✓ or a progress bar would create a false daily obligation and break the
  midnight-rollover model the stores use. Instead:
  - **A resume position.** The page heading at the top of the viewport, plus the first ayah on it, saved
    automatically (debounced) and kept until changed. It is not daily and adds no history entry.
  - **No ✓** on the «البقرة» chip, and nothing added to the adhkar or «سور» history or progress bars.
  - **Optional, open question Q3:** at the end of the page, «ختمت سورة البقرة» records a completion instant, shown
    as «آخر ختم: …». Per-quarter marks that persist until the next completion are possible, but they add a store and
    UI. Defer them unless the owner wants them (Q4).

### 2.4 Virtue texts

The texts below were checked against the hadith-api Arabic editions, the source the repository already binds to
(`reference/hadith.sleep.json` header). sunnah.com links are given for readers; sunnah.com returned HTTP 403 to
automated fetches on 2026-11-21.

Each note has exactly one «…» quotation, and every part split at «…» occurs in the hadith once both are reduced to
bare letters (`bareLetters`, `content-validate.mjs:371-387`). A second quotation would put the narration text
between them into the checked slice and fail.

1. `muslim:780` (Abu Hurayra): قال ﷺ: «لَا تَجْعَلُوا بُيُوتَكُمْ مَقَابِرَ، إِنَّ الشَّيْطَانَ يَنْفِرُ مِنَ الْبَيْتِ
   الَّذِي تُقْرَأُ فِيهِ سُورَةُ الْبَقَرَةِ» (رواه مسلم).
2. `muslim:804` (Abu Umama al-Bahili): قال ﷺ: «اقْرَءُوا سُورَةَ الْبَقَرَةِ، فَإِنَّ أَخْذَهَا بَرَكَةٌ، وَتَرْكَهَا
   حَسْرَةٌ، وَلَا تَسْتَطِيعُهَا الْبَطَلَةُ» (رواه مسلم). البطلة: السحرة.
   - The gloss is the narrator Mu'awiya ibn Sallam's «بَلَغَنِي أَنَّ الْبَطَلَةَ السَّحَرَةُ», in the same entry,
     and stays outside the quotation.
3. `muslim:810` (Ubayy ibn Ka'b, Ayat al-Kursi): سأل النبي ﷺ أُبيَّ بن كعب: «أَتَدْرِي أَيُّ آيَةٍ مِنْ كِتَابِ اللَّهِ
   مَعَكَ أَعْظَمُ»، فأجاب بآية الكرسي، فأقرّه ﷺ (رواه مسلم).
   - Ubayy's answer and the Prophet's «لِيَهْنِكَ الْعِلْمُ» are summarised rather than quoted, so the one quotation
     contains only the Prophet's words.
4. `bukhari:5009` (Abu Mas'ud; also Muslim 807–808): قال ﷺ: «مَنْ قَرَأَ بِالْآيَتَيْنِ مِنْ آخِرِ سُورَةِ الْبَقَرَةِ فِي
   لَيْلَةٍ كَفَتَاهُ» (متفق عليه). This is the same note as `sleep-02`.
5. Optional, `muslim:806` (Ibn Abbas; these are the angel's words, so attribute them to him): قال المَلَك للنبي ﷺ:
   «أَبْشِرْ بِنُورَيْنِ أُوتِيتَهُمَا لَمْ يُؤْتَهُمَا نَبِيٌّ قَبْلَكَ: فَاتِحَةُ الْكِتَابِ وَخَوَاتِيمُ سُورَةِ الْبَقَرَةِ، لَنْ تَقْرَأَ
   بِحَرْفٍ مِنْهُمَا إِلَّا أُعْطِيتَهُ» (رواه مسلم).

Left out:
- Narrations outside the two Sahihs, such as at-Tirmidhi's «لكل شيء سنام…» and the "three nights" report. The
  repository binds wording only and records no grading, so these need a grading source from the reviewer.
- Bukhari 2311, the bedtime Ayat al-Kursi hadith. It is already on the sleep page and concerns bedtime, not this
  page.

Note for the reviewer: the page shows 2:201 in Uthmani text, while the adhkar dua card keeps the simplified text by
the R7 choice. That is consistent (the card is a dua excerpt), but say so in R16.

---

## 3. Performance

### 3.1 How sleep does it today

- **PWA.** `renderSleepPanel` flattens al-Mulk's pages into one string and sets it in a single `<p class="salawat-ayah">`
  (`index.html:8382-8396`). The panel scrolls itself (`#sleep-panel { overflow: hidden auto }`, `:2047-2053`).
- **iOS.** `SleepView` puts each passage in one `Text(DhikrCardBody.quranText(...))` inside a plain, non-lazy
  `VStack` in a `ScrollView` (`ios/Athkar/Screens/SleepView.swift:13-27, 74-94`). `resolvingSuwar` builds the
  al-Mulk passage (`BundledContent.swift:170-185`).
- **Fine at that size.** At 2,901 characters this works. At 56,416 characters it would lay out the whole sura on
  open, block programmatic positioning inside it, and re-lay out everything on every Dynamic Type or rotation change.

### 3.2 PWA

- **Markup.** One `innerHTML` of about 130 KB of markup: 48 `<section class="mushaf-page" id="baqarah-p22">`, each
  with a heading and one `<p>` built by `quranTextMarkup`. Each ayah is wrapped in `<span id="b-2-142">` so the index
  can jump to an ayah. That is about 600 inline nodes plus 48 sections, trivial for the DOM. The cost is shaping and
  layout of HAFS text full of marks.
- **CSS.** `.mushaf-page { content-visibility: auto; contain-intrinsic-size: auto 900px; }`. Off-screen sections then
  skip layout and paint, while staying in the DOM, the accessibility tree and find-in-page. `auto` remembers each
  section's real size once it has been rendered. MDN rates it Baseline 2024 (Safari 18). On older WebKit it is
  ignored, and the page simply lays out in full.
- **Reading position.** An `IntersectionObserver` on the section headings records the top page. Save to a new key
  `athkar-tilawah-v1` (`{ position: { baqarah: { page, ayah, at } } }`), debounced.
  - **Restore** with `element.scrollIntoView({ block: "start" })` on the section or ayah, **not** a stored `scrollTop`:
    with intrinsic placeholder sizes, pixel offsets drift until sections have been rendered.
  - The panel needs `scroll-margin-top` for the sticky header (`.period-tabs` is sticky, `index.html:232-240`).
- **Fallback.** If measurement on an older iPhone shows a slow first open, render the resume page ±2 sections first
  and the rest in `setTimeout` chunks. Safari has no `requestIdleCallback`.
- **Service worker.** Bump `CACHE_NAME` (`sw.js:4`, currently `athkar-static-v74`). No new precache entry is needed
  while the data stays inline.
- **Budget to verify.** Measure the panel open in Safari Web Inspector on the oldest supported iPhone. Suggested
  acceptance: under 100 ms of script and layout before the first paint.

### 3.3 iOS (SwiftUI, iOS 17 floor, `ios/project.yml:3-4`)

- **Structure.** Use `ScrollView { LazyVStack { ForEach(pages) { PageRow } }.scrollTargetLayout() }` with
  `.scrollPosition(id: $topPage)`. Both modifiers are iOS 17.0. Save `topPage` on change, debounced, and restore it
  by setting the binding or via `ScrollViewReader.scrollTo(page, anchor: .top)` (iOS 14). `LazyVStack` creates rows
  only as needed, so opening the view shapes about two pages, not 48.
- **Rows.** Each row is the existing pieces: `MushafEncoding.kfgqpc` text, `ReadingFont.mushaf(metrics.quranText)`,
  `.cssLineHeight(metrics.quranLineHeight…)`, and markers in Uthman Taha as `SuwarPageBody.ayat(size:)` builds them
  (`DeckCardView.swift:579-634`). There is no `FittedBody`, because the text never steps down. Rows run from 343 to
  1,461 characters, so per-row layout stays small.
- **Dynamic Type.** It comes for free: `ReadingMetrics.typeScale` already scales `quranText`
  (`ios/Athkar/Design/ReadingMetrics.swift:8-22, 47`). Lazy rows re-lay out only when visible. Because the position
  is a row ID, it survives a type-size change; a pixel offset would not.
- **Granularity.** Rows are per page, so iOS resume and jumps land on the page. A jump to an ayah lands on its page,
  with the ayah number in the toast or heading.
  - Per-ayah rows would break the mushaf's inline flow (each ayah would start a new paragraph). They are not worth it.
  - A known `LazyVStack` caveat: `scrollTo` towards a far, never-measured row can land a little off while estimated
    heights resolve. Re-issue the scroll once after layout settles, and cover it with the UI test in §5.

---

## 4. Navigation

- **PWA tab bar.** Its CSS is written for exactly seven tabs. Short labels apply up to 48rem; at 26rem the salawat
  tab keeps only «ﷺ»; at 23rem and below the row may scroll sideways (`index.html:2115-2134`, tabs at `:2211-2240`).
  An eighth tab would push most phones into the scrolling case.
- **Chip in «سور» (recommended for the PWA).** Insert `<button class="sura-chip" data-reading="baqarah">البقرة</button>`
  first in `#sura-picker` (`index.html:2244-2250`). This follows mushaf order: 2 before 18, and the validator already
  requires mushaf order for suwar.
  - Use its own attribute, not `data-sura`: `updateSuraPicker` resolves every `[data-sura]` through `suwarById`
    (`:8079-8089`).
  - Selecting it hides the deck, `.summary-row` and `.deck-navigation`, and shows a new `#baqarah-panel`, styled and
    scrolling like `#sleep-panel`.
  - Remember the choice in `athkar-suwar-v1.selected` only if the owner wants «سور» to reopen on al-Baqarah (Q5).
    Otherwise use the tilawah key, which avoids touching the suwar store's normaliser (`:6841-6846`).
  - Deep link `#baqarah`. Six chips at 0.9rem fit 320px: «البقرة» is no wider than «الصافات».
- **iOS (recommended).** A new `OtherSection.baqarah` with title «سورة البقرة», placed in the أوراد group right after
  `.suwar` (`ios/Athkar/Screens/OtherSectionsView.swift:12-51`).
  - It opens `BaqarahView` the way sleep opens `SleepView` (`ios/Athkar/Screens/HomeView.swift:57-58`).
  - Its status line is the resume page («الصفحة ٢٢ من ٤٩»), or «ابدأ القراءة».
  - The alternative, a chip in the «سور» section, needs `SectionChips`/`DeckView` to host a non-deck body. They are
    built on `DeckModel.sections` (`ios/Athkar/Deck/SectionChips.swift:1-40`), so that change is far more invasive.

---

## 5. Implementation plan, in order

Each step lands with its own checks. The scope comes from `tools/test.sh` and the rules in `tools/affected-tests.py`.

1. **Content** (the content lane: `content-validate`, `content-review-test`, `content-export-pwa --check`, fixtures)
   - §1.8 steps 1–6.
   - `tools/content-lib.mjs:14-22`: return `tilawah: tilawahContent` from `loadPwaContent`.
   - `tools/content-export-pwa.mjs`: an equality block like the sleep one (`:62-71`).
   - `tools/affected-tests.py`: add `content/tilawah.v1.json` to `APP_RESOURCES`, `BUNDLED_PACKS` and the
     `content-export-pwa` inputs (`:88-92, 115-117`). `content/**` already feeds the validator.
2. **Encoders**
   - Extend `MushafEncodingTests` to `kfgqpc-hafs.tilawah.json` (286 ayat). Fix in both `kfgqpcEncoding` and
     `MushafEncoding.kfgqpc` any gap that turns out to be real (§1.4), with a rule test.
   - Lanes: core and models.
3. **PWA**
   - In `index.html`:
     - the inline `tilawahContent` literal, between `ayatAlKursi` and `collections` (`content-lib.mjs:17-18`);
     - the `#baqarah-panel` markup and CSS;
     - the chip;
     - `renderBaqarahPanel()` and the position store, with `normalize`/`parse`/`save` functions written like the
       suwar ones;
     - the index sheet;
     - clearing on «حذف كل البيانات».
   - Bump `sw.js` `CACHE_NAME`.
   - Generate a fixture file `spec/sessions/fixtures/tilawah-position.json` from the PWA functions with
     `node tools/fixtures-generate.mjs`, so iOS can prove it parses the same values. Add it to `GENERATED_FIXTURES`.
4. **Persistence spec**
   - `spec/schema.md`: a new settings key `tilawah_position` (JSON `{ "baqarah": { "page", "ayah", "at" } }`, default
     absent). As a setting it needs **no DB migration**. If Q3 adds completion records, that needs migration `v7`
     (`v6` is the reading decks') with its own survival test (`spec/schema.md:30-35`).
   - State that transfer v1 and backup envelope v1 do not carry it. Transfer shapes are closed (`transfer-v1.md:105`),
     and envelope v1 leaves out suwar (`spec/schema.md:521-522`). Backup format 2 does carry suwar and the reading
     decks (`spec/backup/envelope-v2.md`), so decide whether it adds an optional `tilawah` section or carries the key
     under `preferences`.
5. **iOS**
   - `ios/project.yml` resource plus pbxproj.
   - `BundledContent`: decode and validate the pack.
   - `BaqarahView` (§3.3).
   - `OtherSection.baqarah` and its `HomeView` routing.
   - The settings repository key.
   - `DiagnosticsReport` pack list.
   - Lanes: ios-build and app-unit.
6. **Tests**
   - Portable: update `BundledIntegrityTests`, and add a position-fixture parity test.
   - UI: a new `BaqarahUITests`:
     - opens from أخرى;
     - the first heading «الصفحة ٢» is visible;
     - the index jump to «الجزء ٢» shows «الصفحة ٢٢»;
     - after a relaunch it resumes on the same page;
     - at the largest Dynamic Type size the text is visible and the page scrolls.
   - Update the `OtherSectionsUITests` row count.
   - Add the `affected-tests.py` mapping, like `SleepUITests` (`:159`).
   - These run on the macOS runner via `.github/workflows/ios-ipa.yml`. Record SDK compilation, executed tests,
     simulator and device results separately (`AGENTS.md`).
7. **Docs.** Add a row for this report in `research/README.md`. Update `AGENTS.md` (pack list) and `CONTEXT.md` if
   "tilawah page" becomes a domain term.

---

## 6. Open questions for the owner

- **Q1.** Did "whole page" mean one continuous page (recommended) or one card per mushaf page (option b)?
- **Q2.** Should the pack be called `tilawah` and leave room for Al Imran (the «زهراوين», Muslim 804), or be
  al-Baqarah only?
- **Q3.** Should finishing the sura be recorded («ختمت السورة», last completion date)? A record needs a DB migration
  on iOS; resume alone does not.
- **Q4.** Should there be optional per-quarter marks that persist until the next completion, or resume only?
- **Q5.** Should «سور» reopen on al-Baqarah when it was last open, or always on the last deck sura?
- **Q6.** Will you, as reviewer, spot-check a few page breaks and the 2:181 «بَعْدَ مَا» decision against a printed
  Madinah mushaf? Do you want the optional Muslim 806 virtue?
- **Q7.** Should the resume position travel in transfer codes (a transfer v2) or stay on the device?

---

## 7. Method, and what is not verified

**Method.**
- Upstream texts were downloaded into a scratch directory: alquran.cloud surah 2 (`quran-uthmani`, `quran-simple`);
  quran.com v4 `verses/by_chapter/2` (`text_uthmani`, `text_imlaei`, `text_qpc_hafs`, page, juz', hizb, rub' and
  sajda fields); `chapters/2`; Tanzil `quran-data.js`; the hadith-api `ara-muslim` edition.
- The scripts processed them with transforms copied verbatim from `tools/content-validate.mjs:221-238` and
  `index.html:7508-7535`.
- Nothing in the repository was changed except this file.

**Not verified.**
- Rendering on a device. The unjoined small yeh is inferred from Unicode joining types, not from a screenshot.
- Real layout timings.
- The Complex's Word-file text for al-Baqarah (§1.4).
- sunnah.com pages, which were blocked (403). Hadith numbers and texts come from hadith-api; the sunnah.com numbering
  `muslim:780` follows Fuad Abd al-Baqi, as `hadith.sleep.json` states.

## Sources (read 2026-11-21)

- alquran.cloud API, surah 2: https://api.alquran.cloud/v1/surah/2/editions/quran-uthmani,quran-simple
- quran.com API v4, verses: https://api.quran.com/api/v4/verses/by_chapter/2?fields=text_uthmani,text_imlaei,text_qpc_hafs&per_page=300
- quran.com API v4, chapter: https://api.quran.com/api/v4/chapters/2
- quran.com audio (al-Afasy, duration): https://api.qurancdn.com/api/qdc/audio/reciters/7/audio_files?chapter=2&segments=false
- Tanzil metadata (pages, quarters, juz', sajda): https://tanzil.net/res/text/metadata/quran-data.js
- King Fahd Complex, KFGQPC HAFS v3.0 and its Word file: https://fonts.qurancomplex.gov.sa/hafs-reading/ (`fonts/README.md`, `content/reference/kfgqpc-hafs.ruqyah.json`)
- Unicode ArabicShaping.txt (default Joining_Type U for unlisted non-Mn characters, lines 114-119): https://www.unicode.org/Public/UCD/latest/ucd/ArabicShaping.txt
- hadith-api, Sahih Muslim, Arabic: https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/ara-muslim.min.json (780 = 1824.json, 804 = 1874.json, 806 = 1877.json, 810 = 1885.json)
- sunnah.com: https://sunnah.com/muslim:780, https://sunnah.com/muslim:804, https://sunnah.com/muslim:806, https://sunnah.com/muslim:810, https://sunnah.com/bukhari:5009
- MDN, `content-visibility`: https://developer.mozilla.org/en-US/docs/Web/CSS/content-visibility
- Apple, SwiftUI `scrollPosition(id:anchor:)` (iOS 17.0): https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)
- Apple, `scrollTargetLayout(isEnabled:)` (iOS 17.0): https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)
- Apple, `LazyVStack` (iOS 14.0): https://developer.apple.com/documentation/swiftui/lazyvstack
- Apple, `ScrollViewReader` (iOS 14.0): https://developer.apple.com/documentation/swiftui/scrollviewreader
