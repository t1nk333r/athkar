// Validates content/ (NATIVE_APP_PLAN.md 5.3). Exits non-zero on any failure.
//   node tools/content-validate.mjs
//
// Quran comparison (rule 2). Every quran item is checked against two independent sources:
//   alquran-cloud:quran-uthmani  -> alquran-cloud.quran-uthmani (exact)   + quran-com.v4.uthmani (encoding-normalised)
//   simplified-rasm              -> alquran-cloud.quran-simple (exact)     + quran-com.v4.imlaei  (letters and vowels)
// For simplified-rasm, letters and fatha/damma/kasra/tanween are two-source. Shadda, sukun, pause and annotation
// marks, superscript alef and tatweel are checked against quran-simple only: imlaei marks idgham differently (no
// sukun on a final nun/meem, shadda on the next word) and carries no pause marks, so it is compared without them.
// Common normalisation for all comparisons: Unicode NFC (canonical order of stacked marks), drop the leading basmala
// alquran.cloud prepends to ayah 1, collapse whitespace. Adhkar texts carry ayah markers ﴿n﴾, which must number
// ayahFrom…ayahTo and close the text; each ayah is compared on its own. A `partial` item is an excerpt pinned by
// word indices in content/reference/excerpts.json and must equal exactly that slice of each source.
// Known, reviewed deviations live in content/reference/exceptions.json; each must match the observed diff exactly.
//
// Review (rules 3, 4). Each REVIEW.md row records the SHA-256 of the pack bytes it approved. The manifest's
// reviewRecord must name a row for the pack's current version whose SHA-256 equals the pack's, and each pack's
// rows must have strictly increasing versions, so any text or order change needs a new row and a version bump.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { contentDir, readJSON, schemaErrors, sha256 } from "./content-lib.mjs";

const errors = [];
const fail = message => errors.push(message);
const check = (schema, value, path) => errors.push(...schemaErrors(schema, value, path));

// ---- Load ----
const manifest = readJSON(join(contentDir, "manifest.json"));
check(readJSON(join(contentDir, "schema/manifest.schema.json")), manifest, "manifest");
const adhkar = readJSON(join(contentDir, "adhkar.v1.json"));
check(readJSON(join(contentDir, "schema/adhkar.schema.json")), adhkar, "adhkar");
const ruqyah = readJSON(join(contentDir, "ruqyah.v1.json"));
check(readJSON(join(contentDir, "schema/ruqyah.schema.json")), ruqyah, "ruqyah");
const reference = Object.fromEntries(
  ["alquran-cloud.quran-uthmani", "alquran-cloud.quran-simple", "quran-com.v4.uthmani", "quran-com.v4.imlaei"]
    .map(name => [name, readJSON(join(contentDir, "reference", `${name}.json`)).verses])
);
const exceptions = readJSON(join(contentDir, "reference/exceptions.json")).exceptions;
const excerpts = readJSON(join(contentDir, "reference/excerpts.json")).excerpts;
const usedExceptions = new Set();

// ---- Manifest, versions, checksums, review records (rules 3, 4) ----
const reviewLog = readFileSync(join(contentDir, "REVIEW.md"), "utf8");
const reviewEntries = new Map();
const semver = version => version.split(".").map(Number);
const newer = (a, b) => { const [x, y] = [semver(a), semver(b)]; const k = x.findIndex((n, i) => n !== y[i]); return k >= 0 && x[k] > y[k]; };
const latestReviewed = new Map();
for (const match of reviewLog.matchAll(/^\| (R\d+) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|$/gm)) {
  const [, id, pack, version, sha256, reviewer, scope, outcome] = match.map(s => s.trim());
  reviewEntries.set(id, { pack, version, sha256, reviewer, scope, outcome });
  if (!/^[0-9a-f]{64}$/.test(sha256)) fail(`REVIEW.md ${id}: Pack SHA-256 must be the 64-hex digest of the reviewed pack file`);
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) fail(`REVIEW.md ${id}: version ${version} is not semver`);
  else if (latestReviewed.has(pack) && !newer(version, latestReviewed.get(pack))) fail(`REVIEW.md ${id}: ${pack} ${version} does not bump ${latestReviewed.get(pack)}`);
  else latestReviewed.set(pack, version);
}
for (const [name, pack] of [["adhkar", adhkar], ["ruqyah", ruqyah]]) {
  const ref = manifest.packs[name];
  if (!ref) continue;
  if (ref.version !== pack.version) fail(`manifest.${name}.version ${ref.version} != pack ${pack.version}`);
  const actual = sha256(join(contentDir, ref.file));
  if (ref.sha256 !== actual) fail(`manifest.${name}.sha256 is stale (actual ${actual})`);
  const entry = reviewEntries.get(ref.reviewRecord);
  if (!entry) fail(`manifest.${name}.reviewRecord ${ref.reviewRecord} has no row in REVIEW.md`);
  else {
    if (entry.pack !== name || entry.version !== pack.version) fail(`REVIEW.md ${ref.reviewRecord} covers ${entry.pack} ${entry.version}, not ${name} ${pack.version}`);
    if (entry.sha256 !== ref.sha256) fail(`manifest.${name}.sha256 was not reviewed: ${ref.reviewRecord} approved ${entry.sha256}; a text or order change needs a new REVIEW.md row and a version bump`);
    if (!entry.reviewer && pack.version !== "1.0.0") fail(`REVIEW.md ${ref.reviewRecord}: a named reviewer is required to ship ${name} ${pack.version}`);
  }
}

// ---- IDs and structure (rule 1) ----
const seen = new Set();
const unique = (id, where) => (seen.has(id) ? fail(`${where}: duplicate id ${id}`) : seen.add(id));
for (const period of ["morning", "evening"]) {
  for (const [i, item] of adhkar.periods[period].entries()) {
    const where = `adhkar.${period}[${i}] ${item.id}`;
    unique(item.id, where);
    if (!item.id.startsWith(`${period}-`)) fail(`${where}: id prefix does not match period`);
    const quranFields = ["edition", "surah", "ayahFrom", "ayahTo"];
    if (item.kind === "quran") {
      for (const f of quranFields) if (item[f] === undefined) fail(`${where}: quran item missing ${f}`);
      if (item.ayahTo < item.ayahFrom) fail(`${where}: ayahTo < ayahFrom`);
    } else if ([...quranFields, "partial"].some(f => item[f] !== undefined)) fail(`${where}: quran fields on ${item.kind} item`);
    if ((item.kind === "review") !== (item.review === true)) fail(`${where}: kind review must match review: true`);
    if (item.count !== undefined && item.targetOptions) fail(`${where}: count and targetOptions are exclusive`);
    if (item.targetOptions && !item.targetOptions.includes(item.defaultTarget)) fail(`${where}: defaultTarget not in targetOptions`);
    if (item.noteIndex !== undefined && item.noteIndex >= item.details.length) fail(`${where}: noteIndex out of range`);
  }
}
// Surahs the ruqyah segments use: display name, id slug, ayah count. A new surah needs a row here.
const surahs = {
  50: ["سورة ق", "qaf", 45],
  72: ["سورة الجن", "jinn", 28],
  81: ["سورة التكوير", "takwir", 29],
  109: ["سورة الكافرون", "kafirun", 6],
  114: ["سورة الناس", "nas", 6]
};
const arabicDigits = n => String(n).replace(/[0-9]/g, d => String.fromCharCode(0x0660 + Number(d)));
for (const [i, segment] of ruqyah.segments.entries()) {
  const where = `ruqyah.segments[${i}] ${segment.id}`;
  unique(segment.id, where);
  segment.ayahs.forEach((ayah, j) => {
    if (j > 0 && ayah.number !== segment.ayahs[j - 1].number + 1) fail(`${where}: ayah ${ayah.number} not contiguous`);
    if (/[﴿﴾]/.test(ayah.text)) fail(`${where}: ayah ${ayah.number} text carries an ayah marker (the PWA numbers ayahs itself)`);
  });
  if (!segment.ayahs.length) continue;
  const first = segment.ayahs[0].number;
  const last = segment.ayahs.at(-1).number;
  const surah = surahs[segment.surahNumber];
  if (!surah) fail(`${where}: surah ${segment.surahNumber} is not in the validator's surah table`);
  else {
    const [name, slug, ayahCount] = surah;
    if (segment.surah !== name) fail(`${where}: surah «${segment.surah}» is not surah ${segment.surahNumber} «${name}»`);
    if (segment.id !== `${slug}-${first}-${last}`) fail(`${where}: id must be ${slug}-${first}-${last}`);
    if (last > ayahCount) fail(`${where}: surah ${segment.surahNumber} has ${ayahCount} ayahs`);
    const range = first === 1 && last === ayahCount ? "كاملة" : `الآيات ${arabicDigits(first)} – ${arabicDigits(last)}`;
    if (segment.range !== range) fail(`${where}: range «${segment.range}» must be «${range}»`);
  }
  const basmala = first === 1 && segment.surahNumber !== 9;
  if (segment.basmala !== basmala) fail(`${where}: basmala must be ${basmala} (only a segment opening a surah other than at-Tawbah)`);
  const previous = ruqyah.segments[i - 1];
  if (previous && (segment.surahNumber < previous.surahNumber || (segment.surahNumber === previous.surahNumber && first <= previous.ayahs.at(-1).number))) {
    fail(`${where}: segments must follow mushaf order (surah, then ayah) without overlap`);
  }
}

// ---- Quran comparison (rule 2) ----
const normalise = text => text.normalize("NFC").replace(/\s*﴿[\u0660-\u0669]+﴾/g, "").replace(/\s+/g, " ").trim();
const dropBasmala = (key, text) => (key.endsWith(":1") && key !== "1:1" && text.startsWith("بِسْمِ") ? text.split(" ").slice(4).join(" ") : text);
// quran.com encodes a few marks differently from tanzil-derived alquran.cloud: tatweel before superscript alef,
// hamza above on tatweel instead of a bare hamza, and no small meem after tanween.
const quranComEncoding = text => text.replace(/\u0640([\u064B-\u0652]?)\u0654/g, "\u0621$1").replace(/[\u0640\u06ED]/g, "").replace(/([\u064B-\u064D])\u06E2/g, "$1");
// Letters and vowels: drops shadda, sukun, Quranic annotation and pause marks, superscript alef and tatweel; keeps
// fatha, damma, kasra and tanween. Equal between quran-simple and imlaei on every reference verse.
const vowelled = text => text.replace(/[\u0651\u0652\u06D6-\u06ED\u0670\u0640]/g, "").replace(/\s+/g, " ").trim();

const comparisons = {
  "alquran-cloud:quran-uthmani": [["alquran-cloud.quran-uthmani", t => t], ["quran-com.v4.uthmani", quranComEncoding]],
  "simplified-rasm": [["alquran-cloud.quran-simple", t => t], ["quran-com.v4.imlaei", vowelled]]
};

/** Word-level diff (LCS) as ["-ours", "+reference", …]; empty when equal. */
function wordDiff(ours, ref) {
  const a = ours.split(" ");
  const b = ref.split(" ");
  const lcs = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--) for (let j = b.length - 1; j >= 0; j--) {
    lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  }
  const out = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) { i++; j++; }
    else if (j < b.length && (i === a.length || lcs[i][j + 1] >= lcs[i + 1][j])) out.push(`+${b[j++]}`);
    else out.push(`-${a[i++]}`);
  }
  return out;
}

/** Words wordFrom…wordTo (1-based, counting only tokens with a letter, so pause marks are not words) of `text`. */
function wordSlice(text, { wordFrom, wordTo }) {
  const tokens = text.split(" ");
  const words = tokens.flatMap((token, i) => (/\p{L}/u.test(token) ? [i] : []));
  if (!(Number.isInteger(wordFrom) && Number.isInteger(wordTo) && wordFrom >= 1 && wordFrom <= wordTo && wordTo <= words.length)) return null;
  return tokens.slice(words[wordFrom - 1], words[wordTo - 1] + 1).join(" ");
}

function compareQuran(where, id, edition, surah, from, to, text, excerpt) {
  for (const [source, transform] of comparisons[edition]) {
    const keys = Array.from({ length: to - from + 1 }, (_, k) => `${surah}:${from + k}`);
    const missing = keys.filter(k => reference[source][k] === undefined);
    if (missing.length) { fail(`${where}: ${source} lacks ${missing.join(", ")} (run content-reference-refresh)`); continue; }
    const ours = transform(normalise(text));
    let ref = transform(normalise(keys.map(k => dropBasmala(k, reference[source][k])).join(" ")));
    if (excerpt) {
      ref = wordSlice(ref, excerpt);
      if (ref === null) { fail(`${where}: excerpts.json words ${excerpt.wordFrom}…${excerpt.wordTo} are outside ${source}`); continue; }
    }
    if (ours === ref) continue;
    const diff = wordDiff(ours, ref);
    const exception = exceptions.find(e => e.items.includes(id) && e.source === source);
    if (exception && JSON.stringify(exception.diff) === JSON.stringify(diff)) { usedExceptions.add(exception); continue; }
    fail(`${where}: differs from ${source}: ${diff.join(" ")}`);
  }
}

/** Splits an adhkar Quran text at its ayah markers ﴿n﴾, which must number ayahFrom…ayahTo and close the text. */
function ayahTexts(where, item) {
  const markers = [...item.text.matchAll(/﴿([\u0660-\u0669]+)﴾/g)];
  const found = markers.map(m => m[1]).join(",");
  const expected = Array.from({ length: item.ayahTo - item.ayahFrom + 1 }, (_, k) => arabicDigits(item.ayahFrom + k)).join(",");
  if (found !== expected) { fail(`${where}: ayah markers ﴿${found || "none"}﴾, expected ﴿${expected}﴾`); return null; }
  if (item.text.match(/[﴿﴾]/g).length !== 2 * markers.length) { fail(`${where}: stray ﴿ or ﴾ outside an ayah marker`); return null; }
  if (item.text.slice(markers.at(-1).index + markers.at(-1)[0].length).trim()) { fail(`${where}: text continues after the last ayah marker`); return null; }
  return markers.map((m, k) => item.text.slice(k ? markers[k - 1].index + markers[k - 1][0].length : 0, m.index));
}

const partialItems = new Set();
for (const period of ["morning", "evening"]) {
  for (const item of adhkar.periods[period]) {
    if (item.kind !== "quran" || !(item.ayahTo >= item.ayahFrom)) continue;
    const where = `adhkar ${item.id}`;
    const texts = ayahTexts(where, item);
    if (!texts) continue;
    if (item.partial === true) {
      partialItems.add(item.id);
      if (!excerpts[item.id]) fail(`${where}: partial item needs its word range in reference/excerpts.json`);
      else compareQuran(where, item.id, item.edition, item.surah, item.ayahFrom, item.ayahTo, item.text, excerpts[item.id]);
      continue;
    }
    texts.forEach((text, k) => {
      const ayah = item.ayahFrom + k;
      compareQuran(`${where} ${item.surah}:${ayah}`, item.id, item.edition, item.surah, ayah, ayah, text, null);
    });
  }
}
for (const id of Object.keys(excerpts)) if (!partialItems.has(id)) fail(`excerpts.json: ${id} is not a partial Quran item`);
for (const segment of ruqyah.segments) {
  for (const ayah of segment.ayahs) {
    compareQuran(`ruqyah ${segment.id} ${segment.surahNumber}:${ayah.number}`, segment.id, ruqyah.edition, segment.surahNumber, ayah.number, ayah.number, ayah.text, null);
  }
}
for (const exception of exceptions) {
  if (!usedExceptions.has(exception)) fail(`exceptions.json: stale exception for ${exception.items.join(",")} vs ${exception.source}`);
  if (!reviewEntries.has(exception.reviewRecord)) fail(`exceptions.json: ${exception.reviewRecord} has no row in REVIEW.md`);
}

if (errors.length) {
  for (const error of errors) console.error(`✗ ${error}`);
  console.error(`${errors.length} content error(s)`);
  process.exit(1);
}
const quranItems = [...adhkar.periods.morning, ...adhkar.periods.evening].filter(i => i.kind === "quran").length;
const ayahs = ruqyah.segments.reduce((n, s) => n + s.ayahs.length, 0);
console.log(`✓ content valid: adhkar ${adhkar.version} (${quranItems} quran items), ruqyah ${ruqyah.version} (${ayahs} ayahs), ${usedExceptions.size} reviewed exception(s)`);
