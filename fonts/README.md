# Fonts

The King Fahd Glorious Quran Printing Complex (KFGQPC) publishes both fonts. The app bundles them unmodified.
The end-user licence in each file's name record 13 permits free use, copying, and distribution. It forbids
selling, modifying, translating, or reverse engineering the font software.

| File | Font | Source | Used for |
|------|------|--------|----------|
| `kfgqpc-uthman-taha-naskh.ttf` | KFGQPC Uthman Taha Naskh 2.0 | https://fonts.qurancomplex.gov.sa/ | Ayah markers ﴿ ﴾ (both PWAs, iOS) |
| `kfgqpc-hafs-v30.ttf` | KFGQPC HAFS Uthmanic Script 3.0 (`KFGQPC Hafs V30.ttf` in `KFGQPC-Hafs-V30.zip`, SHA-256 `c9dd7e71…c47a`) | https://fonts.qurancomplex.gov.sa/hafs-reading/ | Quran text: ruqyah pages and the adhkar Quran cards (both PWAs, iOS) |

Uthman Taha lacks glyphs for several Uthmani marks used in the ruqyah text: ٱ, U+06ED, U+06E2, U+06E5, U+06E6,
U+06DF, and waqf signs. Core Text sets such a letter in a fallback font, breaking its join with the preceding letter.
The ruqyah pages and adhkar Quran items therefore use HAFS.
The adhkar Quran items have used Uthmani text since adhkar 1.1.0. The app converts the Quran text to the
Complex's encoding with `MushafEncoding.kfgqpc` (AthkarCore) for use with HAFS.
The Complex's text of every ruqyah ayah is in `content/reference/kfgqpc-hafs.ruqyah.json`. Tests compare
that conversion against this file.
