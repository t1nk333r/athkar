// Re-fetches the frozen Quran reference snapshots in content/reference/ for every ayah the packs use.
// Run only as a deliberate commit that records why the upstream text was refreshed (NATIVE_APP_PLAN.md 5.3.2).
//   node tools/content-reference-refresh.mjs
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { contentDir, readJSON } from "./content-lib.mjs";

const adhkar = readJSON(join(contentDir, "adhkar.v1.json"));
const ruqyah = readJSON(join(contentDir, "ruqyah.v1.json"));

const wanted = new Map(); // surah -> Set(ayah)
const want = (surah, ayah) => (wanted.get(surah) ?? wanted.set(surah, new Set()).get(surah)).add(ayah);
for (const item of [...adhkar.periods.morning, ...adhkar.periods.evening]) {
  if (item.kind !== "quran") continue;
  for (let a = item.ayahFrom; a <= item.ayahTo; a++) want(item.surah, a);
}
for (const segment of ruqyah.segments) for (const ayah of segment.ayahs) want(segment.surahNumber, ayah.number);

async function getJSON(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response.json();
}

const retrieved = new Date().toISOString().slice(0, 10);
const snapshots = {
  "alquran-cloud.quran-uthmani": { source: "https://api.alquran.cloud/v1 edition quran-uthmani", verses: {} },
  "alquran-cloud.quran-simple": { source: "https://api.alquran.cloud/v1 edition quran-simple", verses: {} },
  "quran-com.v4.uthmani": { source: "https://api.quran.com/api/v4 field text_uthmani", verses: {} },
  "quran-com.v4.imlaei": { source: "https://api.quran.com/api/v4 field text_imlaei", verses: {} }
};

for (const surah of [...wanted.keys()].sort((a, b) => a - b)) {
  const ayahs = wanted.get(surah);
  const aqc = await getJSON(`https://api.alquran.cloud/v1/surah/${surah}/editions/quran-uthmani,quran-simple`);
  for (const edition of aqc.data) {
    const target = snapshots[`alquran-cloud.${edition.edition.identifier}`];
    target.upstreamVersion ??= `${edition.edition.identifier} (${edition.edition.source ?? "tanzil"})`;
    for (const ayah of edition.ayahs) if (ayahs.has(ayah.numberInSurah)) target.verses[`${surah}:${ayah.numberInSurah}`] = ayah.text;
  }
  const qc = await getJSON(`https://api.quran.com/api/v4/verses/by_chapter/${surah}?fields=text_uthmani,text_imlaei&per_page=300`);
  for (const verse of qc.verses) {
    if (!ayahs.has(verse.verse_number)) continue;
    snapshots["quran-com.v4.uthmani"].verses[verse.verse_key] = verse.text_uthmani;
    snapshots["quran-com.v4.imlaei"].verses[verse.verse_key] = verse.text_imlaei;
  }
}

for (const [name, snapshot] of Object.entries(snapshots)) {
  const count = Object.keys(snapshot.verses).length;
  const expected = [...wanted.values()].reduce((n, s) => n + s.size, 0);
  if (count !== expected) throw new Error(`${name}: got ${count} verses, expected ${expected}`);
  writeFileSync(join(contentDir, "reference", `${name}.json`), `${JSON.stringify({ retrieved, ...snapshot }, null, 2)}\n`);
  console.log(`${name}: ${count} verses`);
}
