# Fonts

Both fonts are published by the King Fahd Glorious Quran Printing Complex (KFGQPC) and are bundled unmodified. Their
end-user licence, embedded in each file (name record 13), grants free use, copying and distribution, and forbids
selling, modifying, translating or reverse engineering the font software.

| File | Font | Source | Used for |
|------|------|--------|----------|
| `kfgqpc-uthman-taha-naskh.ttf` | KFGQPC Uthman Taha Naskh 2.0 | https://fonts.qurancomplex.gov.sa/ | Quran text in the adhkar cards, ayah markers ﴿ ﴾ (both PWAs, iOS) |
| `kfgqpc-hafs-v30.ttf` | KFGQPC HAFS Uthmanic Script 3.0 (`KFGQPC Hafs V30.ttf` in `KFGQPC-Hafs-V30.zip`, SHA-256 `c9dd7e71…c47a`) | https://fonts.qurancomplex.gov.sa/hafs-reading/ | Ruqyah pages on iOS |

Uthman Taha has no glyphs for several Uthmani marks the ruqyah text uses (ٱ, U+06ED, U+06E2, U+06E5, U+06E6, U+06DF,
waqf signs). Core Text sets such a letter in a fallback font and breaks its join with the letter before, so the
ruqyah pages use HAFS, converted to the Complex's encoding by `MushafEncoding.kfgqpc` (AthkarCore).
`content/reference/kfgqpc-hafs.ruqyah.json` is the Complex's text of every ruqyah ayah, which that conversion is
tested against.
