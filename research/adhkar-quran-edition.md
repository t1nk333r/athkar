# Research: provenance of the Quran text in the adhkar cards

Ticket: [t1nk333r/athkar#11](https://github.com/t1nk333r/athkar/issues/11), child of the map [Map: clear the way to Slice 0 of the native app](https://github.com/t1nk333r/athkar/issues/1).
Branch: `research/adhkar-quran-edition`. All upstream sources read **2026-09-23**.

This file records findings only. It takes no position on which edition the app should adopt; that is the dependent decision ticket's job.

---

## 1. What was compared, and against what

### 1.1 The five items

All five live in `/home/t1nk33r/Projects/athkar/index.html` as object literals spread into `morningAthkar` / `eveningAthkar`.

| Item (const) | index.html lines | Quran reference | Card ids |
| --- | --- | --- | --- |
| `ayatAlKursi` | 1962-1969 | al-Baqara 2:255 | `morning-01`, `evening-01` |
| `alIkhlas` | 1971-1978 | al-Ikhlas 112:1-4 | `morning-02`, `evening-02` |
| `alFalaq` | 1980-1987 | al-Falaq 113:1-5 | `morning-03`, `evening-03` |
| `anNas` | 1989-1996 | an-Nas 114:1-6 | `morning-04`, `evening-04` |
| `comprehensiveDua` | 2083-2092 | al-Baqara 2:201 (final clause) | `morning-26`, `evening-24` |

Shape observed: each item is `{ quran: true, text: `...` }`. `alIkhlas`, `alFalaq` and `anNas` additionally carry `prefix: `بسم الله الرحمن الرحيم`` (undiacritised). The `﴿...﴾` ayah markers are **inside the `text` string**, one pair per ayah, with Arabic-Indic digits.

### 1.2 The editions compared

| # | Edition / text | Endpoint (all read 2026-09-23) |
| --- | --- | --- |
| 1 | AlQuran Cloud `quran-uthmani` | `https://api.alquran.cloud/v1/ayah/2:255/quran-uthmani`, `https://api.alquran.cloud/v1/surah/{112,113,114}/quran-uthmani` |
| 2 | Quran.com API v4 `text_uthmani` | `https://api.quran.com/api/v4/quran/verses/uthmani?verse_key=2%3A255` (and 2:201), `?chapter_number={112,113,114}` |
| 3 | AlQuran Cloud `quran-simple` | `https://api.alquran.cloud/v1/ayah/{2:255,2:201}/quran-simple`, `https://api.alquran.cloud/v1/surah/{112,113,114}/quran-simple`, full surah 2 |
| 4 | Quran.com API v4 `text_imlaei` | `https://api.quran.com/api/v4/quran/verses/imlaei?verse_key=2%3A255` (and 2:201), `?chapter_number={112,113,114}` |
| 5 | Tanzil Quran Text (the authority's own download) | `https://tanzil.net/pub/download/index.php?quranType={simple,simple-plain}&outType=txt-2&agree=true&marks=true&sajdah=true` |
| 6 | Disqualification sweep, AlQuran Cloud Arabic text editions | `quran-simple-enhanced`, `quran-simple-min`, `quran-uthmani-min`, `quran-tajweed`, `quran-kids`, `quran-unicode`, `quran-corpus-qd`, `quran-simple-clean` (2:255 each) |

The full list of AlQuran Cloud Arabic Quran text editions was read from `https://api.alquran.cloud/v1/edition?format=text&language=ar&type=quran` (13 editions).

The comparison corpus from the sibling repo is `~/Projects/ruqyah-al-qareen/content.js` (`RUQYAH_SEGMENTS`), which holds AlQuran Cloud `quran-uthmani` text.

---

## 2. Normalisation rules used (definitions of "match")

A given item "matches" an edition only if, after all five rules, the two strings are identical as Unicode code points.

| Rule | Action | Rationale |
| --- | --- | --- |
| **N1** | Delete every embedded ayah marker: `﴿` (U+FD3F, ornate paren), the digits U+0660-U+0669, `﴾` (U+FD3E), and collapse the whitespace left behind to a single space. | Exactly the normalisation `NATIVE_APP_PLAN.md` §5.3 prescribes for `kind: quran` items ("strip ayah markers `﴿...﴾`, collapse whitespace"). |
| **N2** | Compare against the addressed ayah *range* only; the mushaf basmala is excluded from `text` and handled as `prefix` (see §6.4). | AlQuran Cloud and Quran.com both prepend `بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ` to ayah 1 of a surah request; the app keeps it in a separate field. |
| **N3** | Trim leading and trailing whitespace. | Quran.com v4 returns ayah 1 with a leading space (basmala placeholder), e.g. `" قُلْ هُوَ ٱللَّهُ أَحَدٌ"`. |
| **N4** | Compare code points; **no** diacritic stripping, no letter folding, no NFC/NFD normalisation, no combining-mark reordering. | The question asked is which published edition the strings *are*, not which they resemble after cleaning. |
| **N5** | Nothing else. `﷿٢٥٥﴾` is deleted by N1; it is never treated as text. | |

### 2.1 Caveat that N1-N5 does not cover: combining-mark order

The two corpora do not always encode shadda+vowel clusters in the same *order*.

| Word | Where | Byte sequence (verified by code-point probe) |
| --- | --- | --- |
| `رَبَّنَا` | `comprehensiveDua`, index.html line 2085 | `ب` U+0628 + **U+064E (fatha) + U+0651 (shadda)** + `ن` |
| `رَبَّنَا` | AlQuran Cloud `quran-simple` 2:201 | `ب` U+0628 + **U+0651 (shadda) + U+064E (fatha)** + `ن` |
| `الدُّنْيَا` | `comprehensiveDua`, line 2085 | `د` U+062F + **U+064F (damma) + U+0651** |
| `اللَّهُ` | `ayatAlKursi`, line 1964 | `ل` U+0644 + **U+0651 + U+064E** (shadda first) |
| `مِنْ شَرِّ` | `anNas`, line 1992 | `ر` U+0631 + **U+0651 + U+0650** (shadda first) |

The four short surah items and `ayatAlKursi` use shadda-then-vowel, the same order as AlQuran Cloud, Tanzil and Quran.com. **`comprehensiveDua` uses the reverse order** for both of its shadda clusters. The two render identically and are canonically equivalent (NFC would reorder one to the other), but they are different code-point sequences. Consequence for the pipeline: a "character-for-character comparison" that stops at N1-N5 will report `comprehensiveDua` as a mismatch against an otherwise identical reference text.

---

## 3. Verdict table

Cell = result of comparing the app's item against that edition under N1-N5.

| Item | AQC `quran-uthmani` | Quran.com `text_uthmani` | AQC `quran-simple` | Quran.com `text_imlaei` | Closest published edition |
| --- | --- | --- | --- | --- | --- |
| `ayatAlKursi` (2:255) | **differs** (Uthmani rasm) | **differs** (Uthmani rasm) | **differs - 2 points** (see §4.1) | **differs** (also drops sukun across idgham) | none exactly; `quran-simple` with 2 deviations |
| `alIkhlas` (112:1-4) | differs (wasla, `ۥ`, `ۢ`) | differs (wasla, `ۥ`, `ۢ`) | **exact match** | differs at 112:4 only | AlQuran Cloud `quran-simple` |
| `alFalaq` (113:1-5) | differs (wasla, dagger alefs, `ى`) | differs (wasla, dagger alefs, tatweel) | **exact match** | differs (no sukun after `مِن`) | AlQuran Cloud `quran-simple` |
| `anNas` (114:1-6) | differs (wasla, `ۥ`/`ۦ`, `ى`) | differs (wasla, `ى`) | **exact match** | differs at 114:4 only | AlQuran Cloud `quran-simple` |
| `comprehensiveDua` (2:201 tail) | differs (`رَبَّنَآ`, `ءَاتِنَا`, `ى`) | differs (same class) | **exact match of the quoted clause** (mark-order caveat in §2.1) | **exact match of the quoted clause** | AlQuran Cloud `quran-simple` (text); ayah is quoted in part |

No AlQuran Cloud Arabic text edition embeds `﴿...﴾` markers; the markers are app-side in both the adhkar items (embedded in `text`) and the ruqyah deck (generated at render time, §6.3).

---

## 4. Per-item detail

### 4.1 `ayatAlKursi` - al-Baqara 2:255 (lines 1962-1969)

App text (verbatim, markers included):

> `اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ ۖ وَلَا يَؤُودُهُ حِفْظُهُمَا وَهُوَ الْعَلِيُّ الْعَظِيمُ ﷿٢٥٥﴾`

Against **AlQuran Cloud `quran-simple` 2:255** (read 2026-09-23) the string is identical **except two points**:

| # | App | Reference | Character detail |
| --- | --- | --- | --- |
| D1 | `وَلَا يَؤُودُهُ` | `وَلَا يَئُودُهُ` | The hamza carrier differs: app uses **U+0624 ARABIC LETTER WAW WITH HAMZA ABOVE** (`ؤ`); the reference uses **U+0626 ARABIC LETTER YEH WITH HAMZA ABOVE** (`ئ`). One code point; a letter-level difference that no whitespace/marker normalisation removes. |
| D2 | `... حِفْظُهُمَا وَهُوَ ...` | `... حِفْظُهُمَا ۚ وَهُوَ ...` | The reference carries **U+06DA ARABIC SMALL HIGH JEEM** (the `ۚ` pause mark) between `حِفْظُهُمَا` and `وَهُوَ`; the app has no mark there. |

Both differences were located by code-point probes: `U+0624` occurs in `index.html` lines 1962-1996 **only** on line 1964; the code-point sequence `U+064A U+064E U+0624 U+064F U+0648 U+062F U+064F U+0647 U+064F` matches in the app while `U+064A U+064E U+0626 U+064F U+0648 U+062F U+064F U+0647 U+064F` does not; the reverse holds for the `quran-simple` response and for Tanzil's own text; and the sequence `U+062D U+0650 U+0641 U+0652 U+0638 U+064F U+0647 U+064F U+0645 U+064E U+0627 U+0020 U+06DA` matches in the references but not in the app.

Against the **Uthmani** editions the same ayah differs at every point where Uthmani rasm is distinguished. The app contains **none** of these code points anywhere in its five items (tested as a character class over lines 1962-1996 and 2083-2092): U+0671 (alef wasla), U+06E1, U+06E2, U+06E5, U+06E6 (small high dotless head of khah / meem / waw / yeh), U+06ED (small low meem), U+0653 (maddah above), U+0654, U+0655, U+0640 (tatweel), U+06DF, U+06E0. Both Uthmani editions use all of them here. Worked examples:

| Position | App (and `quran-simple`) | AQC `quran-uthmani` | Quran.com `text_uthmani` |
| --- | --- | --- | --- |
| 1st word | `اللَّهُ` | `ٱللَّهُ` (U+0671) | `ٱللَّهُ` (U+0671) |
| `لَا` | `لَا` | `لَآ` (U+0653) | `لَآ` (U+0653) |
| `إِلَٰهَ` | `إِلَٰهَ` | `إِلَـٰهَ` (U+0640) | `إِلَـٰهَ` (U+0640) |
| 6th word | `الْحَيُّ` (U+064A) | `ٱلْحَىُّ` (U+0649, U+0671) | `ٱلْحَىُّ` (U+0649, U+0671) |
| `لَهُ` | `لَهُ` | `لَّهُۥ` (U+06E5) | `لَّهُۥ` (U+06E5) |
| `فِي` | `فِي` (U+064A) | `فِى` (U+0649) | `فِى` (U+0649) |
| `مَنْ ذَا` | sukun present | `مَن ذَا` (no sukun) | `مَن ذَا` (no sukun) |
| `الَّذِي` | U+064A | `ٱلَّذِى` (U+0649) | `ٱلَّذِى` (U+0649) |
| `وَلَا يَؤُودُهُ` | U+0624 | `يَـئُودُهُۥ` (U+0640, U+0626, U+06E5) | `يَـئُودُهُۥ` |

The two Uthmani sources are also not identical to each other for this ayah: AQC writes `سِنَةٌۭ` and `نَوْمٌۭ` (with U+06ED, small low meem), Quran.com writes `سِنَةٌ` and `نَوْمٌ`; AQC writes `مِّنْ` (shadda before kasra, no sukun before the shadda) where Quran.com writes `مِّنْ`.

Against **Quran.com `text_imlaei`** the app differs in D1 and D2 as well **and** at idgham/ikhfa positions where that edition drops the sukun: `لَّهُ` (imlaei) vs app `لَهُ`; `مَن ذَا` vs `مَنْ ذَا`; `عِندَهُ` vs `عِنْدَهُ`; `مِّنْ عِلْمِهِ` vs `مِنْ عِلْمِهِ`.

Disqualified alternatives (each fetched for 2:255, 2026-09-23): `quran-simple-enhanced` (same D1/D2 as `quran-simple` plus `مَن ذَا`, `عِندَهُ`), `quran-simple-min` and `quran-uthmani-min` (minimal tashkeel, `لا` without maddah, `أَخُذُهُ` forms), `quran-tajweed` (interleaved rule markup), `quran-kids` (`|`-separated word/gloss/timing records), `quran-unicode` (Uthmani rasm with Farsi yeh), `quran-corpus-qd` (morphological markup), `quran-simple-clean` (no diacritics).

### 4.2 `alIkhlas` - al-Ikhlas 112:1-4 (lines 1971-1978)

App text: `قُلْ هُوَ اللَّهُ أَحَدٌ ﷿١﴾ اللَّهُ الصَّمَدُ ﷿٢﴾ لَمْ يَلِدْ وَلَمْ يُولَدْ ﷿٣﴾ وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ ﷿٤﴾`

* **AlQuran Cloud `quran-simple`: exact match** for 112:2-4 and, after N2 (basmala stripped), for 112:1. Verified: the code-point sequence `U+064A U+064E U+0643 U+064F U+0646 U+0652 U+0020 U+0644 U+064E U+0647 U+064F` (`يَكُنْ لَهُ`) matches line 1974 of `index.html` and the `quran-simple` block of `https://api.alquran.cloud/v1/surah/112/editions/...`.
* **AQC `quran-uthmani` 112:1-4**: `قُلْ هُوَ ٱللَّهُ أَحَدٌ` / `ٱللَّهُ ٱلصَّمَدُ` / `لَمْ يَلِدْ وَلَمْ يُولَدْ` / `وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ`.
* **Quran.com `text_uthmani` 112**: identical to the AQC Uthmani except for a leading space on 112:1. **Both** put the `ۢ` (U+06E2, small high meem isolated form) on **112:4** `أَحَدٌۢ`, not on 112:1. (The ticket body's example `قُلْ هُوَ ٱللَّهُ أَحَدٌۢ` does not reproduce in either source; 112:1 has no U+06E2.)
* **Quran.com `text_imlaei` 112**: 112:1-3 identical to the app; 112:4 is `وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ` versus the app's `... يَكُنْ لَهُ ...` - the imlaei text assimilates (`لَّ`, no sukun), the app does not.

### 4.3 `alFalaq` - al-Falaq 113:1-5 (lines 1980-1987)

App text: `قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ ﷿١﴾ مِنْ شَرِّ مَا خَلَقَ ﷿٢﴾ وَمِنْ شَرِّ غَاسِقٍ إِذَا وَقَبَ ﷿٣﴾ وَمِنْ شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ ﷿٤﴾ وَمِنْ شَرِّ حَاسِدٍ إِذَا حَسَدَ ﷿٥﴾`

* **AlQuran Cloud `quran-simple`: exact match** for 113:2-5, and for 113:1 after N2.
* **AQC `quran-uthmani`**: `بِرَبِّ ٱلْفَلَقِ`; `مِن شَرِّ` (no sukun); `وَمِن شَرِّ`; `وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ`; `وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ`.
* **Quran.com `text_uthmani`**: same class; 113:4 is `ٱلنَّفَّـٰثَـٰتِ فِى ٱلْعُقَدِ` - with U+0640 tatweel in front of each superscript alef, which AQC's Uthmani does not have. The two Uthmani sources differ from each other here.
* **Quran.com `text_imlaei`**: 113:1 identical to the app; 113:2-5 write `مِن شَرِّ` / `وَمِن شَرِّ` without the sukun the app has.

### 4.4 `anNas` - an-Nas 114:1-6 (lines 1989-1996)

App text: `قُلْ أَعُوذُ بِرَبِّ النَّاسِ ﷿١﴾ مَلِكِ النَّاسِ ﷿٢﴾ إِلَٰهِ النَّاسِ ﷿٣﴾ مِنْ شَرِّ الْوَسْوَاسِ الْخَنَّاسِ ﷿٤﴾ الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ ﷿٥﴾ مِنَ الْجِنَّةِ وَالنَّاسِ ﷿٦﴾`

* **AlQuran Cloud `quran-simple`: exact match** for 114:2-6 and for 114:1 after N2. Verified: the code-point sequence for `مِنْ شَرِّ الْوَسْوَاسِ الْخَنَّاسِ` (114:4) matches the `quran-simple` block of the 114 cross-edition response with the app's sukun and shadda order.
* **AQC `quran-uthmani`**: `بِرَبِّ ٱلنَّاسِ`; `مَلِكِ ٱلنَّاسِ`; `إِلَٰهِ ٱلنَّاسِ`; `مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ`; `ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ`; `مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ`.
* **Quran.com `text_uthmani`**: same class, with a leading space on 114:1.
* **Quran.com `text_imlaei`**: identical to the app except 114:4, which is `مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ` (no sukun after `مِن`).

Cross-check with the sibling corpus: `content.js` `nas-1-6` equals AlQuran Cloud `quran-uthmani` 114:1-6 ayah-for-ayah, verbatim, for all six ayahs (read from both the local file and the API on 2026-09-23). The ruqyah pack contains no al-Ikhlas (112) or al-Falaq (113) segment: its segment ids are `qaf-1-8`, `qaf-9-14`, `qaf-15-22`, `qaf-23-29`, `qaf-30-37`, `qaf-38-45`, `jinn-1-7`, `jinn-8-13`, `jinn-14-21`, `jinn-22-28`, `takwir-1-10`, `takwir-11-21`, `takwir-22-29`, `kafirun-1-6`, `nas-1-6`.

### 4.5 `comprehensiveDua` - al-Baqara 2:201 (lines 2083-2092)

App text: `رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ ﷿٢٠١﴾`

**The item is an excerpt, not the whole ayah.** `quran-simple` 2:201 is `وَمِنْهُمْ مَنْ يَقُولُ رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ`; the app quotes only the clause from `رَبَّنَا` onward. The card's `details` cite `«البقرة»` with no ayah number; the number exists only as the embedded `﷿٢٠١﴾`.

* **AlQuran Cloud `quran-simple`: the quoted clause matches exactly** (aside from §2.1's mark-order caveat).
* **Quran.com `text_imlaei`: the quoted clause matches exactly too** (`رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ`); the difference in that edition is in the words the app omits (`وَمِنْهُم مَّن يَقُولُ`).
* **AQC `quran-uthmani` 2:201**: `وَمِنْهُم مَّن يَقُولُ رَبَّنَآ ءَاتِنَا فِى ٱلدُّنْيَا حَسَنَةً وَفِى ٱلْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ ٱلنَّارِ`. Inside the quoted clause the app would differ at: `رَبَّنَآ` (U+0653 maddah) vs app `رَبَّنَا`; `ءَاتِنَا` (U+0621 hamza + U+0627 + maddah) vs app `آتِنَا` (U+0622 precomposed); `فِى` (U+0649) vs app `فِي` (U+064A); `ٱلدُّنْيَا` (U+0671) vs app `الدُّنْيَا`; `ٱلْآخِرَةِ` vs app `الْآخِرَةِ`; `ٱلنَّارِ` vs app `النَّارِ`.
* **Quran.com `text_uthmani` 2:201**: `وَمِنْهُم مَّن يَقُولُ رَبَّنَآ ءَاتِنَا فِى ٱلدُّنْيَا ... وَفِى ٱلـَءَاخِرَةِ ...` - note `ٱلـَءَاخِرَةِ` (tatweel + hamza) where AQC has `ٱلْآخِرَةِ`: another instance of the two Uthmani sources disagreeing.

---

## 5. What changes if these items move to the ruqyah's Uthmani edition

Section 5.1 of `NATIVE_APP_PLAN.md` states the same observation independently; this section makes the character-level delta explicit.

1. **Every item's code points change.** The tested delta classes are: insertion of U+0671 (alef wasla) before `لله`-type words; U+0653 maddah replacing the bare alef in `لَا`/`آ`; U+06E5/U+06E6 (small waw/yeh) after `ه` + damma; U+06E2/U+06ED (small high/low meem) on nunated forms at waqf; U+06E1-based sukun rendering; U+0649 (alef maksura) in `فى`, `ىشفع`, `ٱلَّذِى`; U+0640 tatweel before superscript alefs in the Quran.com variant; and the removal of sukun across idgham that the imlaei/simple-enhanced texts do (`مِن شَرِّ`). A per-item worked example is in §4.
2. **The `﷿١﴾` markers are data today, structure tomorrow.** In `index.html` the digits are inside `text` (`﷿` = U+FD3F, `﴾` = U+FD3E, digits U+0660-U+0669 - verified). In the ruqyah pack, `ayahs[].number` is a field and the marker is generated at render time: `segmentMarkup` in `ruqyah-al-qareen/index.html` line 1335 emits `${escapeHtml(ayah.text)} <span class="ayah-number">﷿${formatNumber(ayah.number)}﴾</span>`, with `Intl.NumberFormat("ar-EG")` for the digits and `.ayah-number { font-size: 0.78em; white-space: nowrap; }`. The ruqyah deck also carries the ayah range in the card header (`range`, e.g. `الآيات ١ - ٨`).
3. **The basmala changes form.** The app's `prefix` is undiacritised `بسم الله الرحمن الرحيم` (verified: no U+0652 sukun and no U+0670 anywhere on line 1973). The ruqyah app renders `بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ` in a `.basmala` paragraph (ruqyah `segmentMarkup`, line 1338).
4. **Volume of marks per card rises**, which is what the layout section below is about.

---

## 6. Rendering, line breaking and card auto-fit in the current PWA

1. **The font is already the Uthmani one.** `fonts/kfgqpc-uthman-taha-naskh.ttf` is bundled in this repo, and `.dhikr-card.quran .dhikr-prefix, .dhikr-card.quran .dhikr-text { font-family: "KFGQPC Uthman Taha Naskh", var(--font-arabic); font-weight: 400; }` (`index.html` lines 826-830). The same font file is bundled in the ruqyah repo, whose text is full Uthmani, so the typeface is in use with Uthmani text today. `[INFERENCE]` No per-glyph coverage test was run on the font in this session.
2. **Quran cards are excluded from auto-fit.** `fitCardContent(card)` starts `if (!card || card.matches(".quran, .needs-review")) return;` (`index.html` line 2653). The fitting pass only adds `.is-content-dense` / `.is-content-tight` to other cards, and those classes only adjust non-Quran selectors (lines 876-938); `.dhikr-card.quran .dhikr-text`'s own `font-size`/`line-height` would win anyway on specificity.
3. **Overflow is clipped, not scrolled, on Quran cards.** `.dhikr-card` is `display: grid; grid-template-rows: minmax(0, 1fr) auto; overflow: hidden; block-size: 100%` (lines 690-697). Only the `.needs-review` variant opts into `overflow-y: auto` (line 759). So a longer Quran text on a Quran card would be **clipped** rather than shrunk or scrolled, unless the text still has slack in the card box.
4. Line metrics that would apply: `--quran-text-size` and `--quran-line-height` (2.05 default, 1.82 compact, 2.3 wide) at lines 85-115 and 834-837.
5. **The ruqyah deck solves the same problem differently**: `fitCardText(card)` (ruqyah `index.html` line 1436) fits `.surah-card` bodies and `showCard` resets `.card-body` `scrollTop` (line 1421). This is the behaviour `NATIVE_APP_PLAN.md` §1.2 refers to when it says ruqyah uses `fitCardText` while athkar uses `fitCardContent`.
6. **Line breaking**: athkar's `.dhikr-text` sets `unicode-bidi: plaintext` and `text-align: start` (lines 819-823); no manual line breaking exists, so wrapping is the browser's. Uthmani text adds marks that attach to the same base letters, so new break opportunities are only created where the added small marks carry their own spacing; `[INFERENCE]` that the visible line count per card rises slightly for the same words.

---

## 7. Is there a citable source for the edition the items match?

* The edition the items match is the one served as **AlQuran Cloud edition identifier `quran-simple`**, whose own metadata (read from `https://api.alquran.cloud/v1/edition?format=text&language=ar&type=quran`) is `name: "القرآن الكريم المبسط (تشكيل بسيط) (simple)"`, `englishName: "Simple"`. That identifier is stable and addressable (`https://api.alquran.cloud/v1/surah/114/quran-simple`), so the edition can be cited exactly as "AlQuran Cloud `quran-simple`". AlQuran Cloud publishes no per-edition upstream/source statement that I could find (checked its API documentation page and the ``/edition`` endpoints; the GitHub path `github.com/islamic-network/api.alquran.cloud` returns 404).
* The authority for "Simple"-type Quran text in general is **Tanzil**: "Tanzil Quran text ... latest release of the text (Version 1.1) is published in February 2021", with a Terms of Use that permits verbatim copying only, requires that the source (Tanzil Project) be clearly indicated and a link to tanzil.net be made. Their download form separates `Simple (Imla'ei)`, **`Simple (Plain)` - "Simple text without Ikhfa and Idgham demonstration"**, `Simple (Minimal)`, `Simple (Clean)`, `Uthmani`, `Uthmani (Minimal)`, plus options to include pause marks, sajdah signs, rub-el-hizb signs and tatweel.
* Fetching Tanzil's own `simple-plain` output with pause marks on 2026-09-23 reproduces the `quran-simple` form on the sample compared (sukun retained: `مِنْ رَبِّهِمْ`, `لِلْمُتَّقِينَ`; pause marks present: `رَيْبَ ۛ فِيهِ ۛ هُدًى`), whereas Tanzil's plain `simple` output demonstrates ikhfa/idgham (`مِن رَّبِّهِمْ`, `لِّلْمُتَّقِينَ`) and does not match. The sample covered surahs 1-31 only (the downloaded text was truncated at ~50 KB), and it covered 2:255 and 2:201, including Tanzil's agreement with `quran-simple` on `يَئُودُهُ` and on the U+06DA before `وَهُوَ`.
* `[INFERENCE]` AlQuran Cloud's `quran-simple` is generated from the Tanzil "Simple (Plain)" text: no first-party statement was found, and the basis is (i) identical edition naming, (ii) the sampled text identity above. This linkage should be treated as unconfirmed until AlQuran Cloud or Tanzil states it.
* **No published edition in the checked set embeds `﷿...﴾` markers**, so the marker convention itself has no upstream edition to cite; it is app-side in both PWAs (embedded here, generated in ruqyah).
* The app's `يَؤُودُهُ` (U+0624) is not present in any of the 13 AlQuran Cloud Arabic text editions, nor in Quran.com `uthmani`/`imlaei`, nor in Tanzil's `simple`/`simple-plain`. `[INFERENCE]` It is a one-letter transcription deviation introduced when the card was written.

---

## 8. Method, and what is not proven

* Extraction: `index.html` was read at exact line ranges (`1962-1996`, `2083-2092`, plus the CSS and JS ranges cited above); the API responses were read directly from the endpoints in §1.2 on 2026-09-23.
* Character-level verification: single-code-point claims were tested with explicit escape patterns (`\x{...}`) against the local files and against greppable snapshots of the API responses, e.g. presence/absence of U+0624 vs U+0626 in `يَؤُودُهُ`, presence of U+06DA after `حِفْظُهُمَا`, absence of the Uthmani-only classes over the whole item ranges, the `﷿٢٥٥﴾` marker encoding, and the shadda/vowel order on both sides.
* A same-session tooling caveat worth knowing for any later check: patterns containing combining-mark sequences are not reliably matched against these files by literal text (the same visual word can be encoded in either mark order), and long escape patterns were observed to fail where the equivalent short ones succeeded. All claims above were re-checked with short escape patterns or with verbatim reads.
* Not proven here: a whole-string byte-level diff (no shell was available in this session), so "exact match" means every discriminating character class tested is identical **and** the two verbatim strings compare equal by inspection **and** targeted code-point equality probes on the differing segments agree. For `ayatAlKursi` the two deviations are asserted positively (their code points were probed on both sides).

---

## Sources (all read 2026-09-23)

| Source | URL |
| --- | --- |
| Ticket | https://github.com/t1nk333r/athkar/issues/11 |
| Map | https://github.com/t1nk333r/athkar/issues/1 |
| AlQuran Cloud ayah: 2:255, 2:201 - `quran-uthmani`, `quran-simple`, `quran-simple-enhanced`, `quran-simple-min`, `quran-uthmani-min`, `quran-tajweed`, `quran-kids`, `quran-unicode`, `quran-corpus-qd` | `https://api.alquran.cloud/v1/ayah/{2:255,2:201}/{edition}` |
| AlQuran Cloud surah: 112, 113, 114, 2 - `quran-uthmani`, `quran-simple`, and 112/113/114 across editions | `https://api.alquran.cloud/v1/surah/{112,113,114,2}/{edition}` |
| AlQuran Cloud Arabic text edition list | https://api.alquran.cloud/v1/edition?format=text&language=ar&type=quran |
| Quran.com API v4, `text_uthmani` (2:255, 2:201, 112, 113, 114) | `https://api.quran.com/api/v4/quran/verses/uthmani?verse_key=2%3A255` (and `2%3A201`), `?chapter_number={112,113,114}` |
| Quran.com API v4, `text_imlaei` (2:255, 2:201, 112, 113, 114) | `https://api.quran.com/api/v4/quran/verses/imlaei?verse_key=2%3A255` (and `2%3A201`), `?chapter_number={112,113,114}` |
| Tanzil Quran Text download page (form fields, text types, terms of use, version 1.1 Feb 2021) | https://tanzil.net/download/ |
| Tanzil Quran Text `simple` (Imla'ei, with ikhfa/idgham demonstration) | `https://tanzil.net/pub/download/index.php?quranType=simple&outType=txt-2&agree=true` |
| Tanzil Quran Text `simple-plain` (+ pause marks) | `https://tanzil.net/pub/download/index.php?quranType=simple-plain&outType=txt-2&agree=true&marks=true&sajdah=true` |
| Local corpus, athkar | `index.html` (lines cited inline) |
| Local corpus, ruqyah | `~/Projects/ruqyah-al-qareen/content.js`, `~/Projects/ruqyah-al-qareen/index.html` |
