// Validates content/ (NATIVE_APP_PLAN.md 5.3). Exits non-zero on any failure.
//   node tools/content-validate.mjs
//
// Quran comparison (rule 2). Every quran item is checked against two independent sources:
//   alquran-cloud:quran-uthmani  -> alquran-cloud.quran-uthmani (exact)   + quran-com.v4.uthmani (encoding-normalised)
//   simplified-rasm              -> alquran-cloud.quran-simple (exact)     + quran-com.v4.imlaei  (letter skeleton)
// Common normalisation for all comparisons: Unicode NFC (canonical order of stacked marks), strip ayah
// markers ﴿…﴾, drop the leading basmala alquran.cloud prepends to ayah 1, collapse whitespace.
// Known, reviewed deviations live in content/reference/exceptions.json; each must match the observed diff exactly.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { contentDir, readJSON, sha256 } from "./content-lib.mjs";

const errors = [];
const fail = message => errors.push(message);

// ---- JSON Schema subset (the keywords used in content/schema) ----
function check(schema, value, path) {
  if ("const" in schema && value !== schema.const) return fail(`${path}: expected ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) return fail(`${path}: ${JSON.stringify(value)} not in ${schema.enum.join("|")}`);
  const type = Array.isArray(value) ? "array" : Number.isInteger(value) ? "integer" : typeof value;
  if (schema.type && schema.type !== type && !(schema.type === "number" && type === "integer")) return fail(`${path}: expected ${schema.type}, got ${type}`);
  if (type === "string") {
    if (schema.minLength && value.length < schema.minLength) fail(`${path}: empty string`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail(`${path}: ${JSON.stringify(value)} does not match ${schema.pattern}`);
  }
  if (type === "integer") {
    if (schema.minimum !== undefined && value < schema.minimum) fail(`${path}: ${value} < ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) fail(`${path}: ${value} > ${schema.maximum}`);
  }
  if (type === "array") {
    if (schema.minItems && value.length < schema.minItems) fail(`${path}: fewer than ${schema.minItems} items`);
    if (schema.items) value.forEach((v, i) => check(schema.items, v, `${path}[${i}]`));
  }
  if (type === "object") {
    for (const key of schema.required ?? []) if (!(key in value)) fail(`${path}: missing ${key}`);
    for (const [key, v] of Object.entries(value)) {
      if (schema.properties?.[key]) check(schema.properties[key], v, `${path}.${key}`);
      else if (schema.additionalProperties === false) fail(`${path}: unexpected property ${key}`);
    }
  }
}

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
const usedExceptions = new Set();

// ---- Manifest, versions, checksums, review records (rules 3, 4) ----
const reviewLog = readFileSync(join(contentDir, "REVIEW.md"), "utf8");
const reviewEntries = new Map();
for (const match of reviewLog.matchAll(/^\| (R\d+) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|$/gm)) {
  const [, id, pack, version, reviewer, scope, outcome] = match.map(s => s.trim());
  reviewEntries.set(id, { pack, version, reviewer, scope, outcome });
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
for (const [i, segment] of ruqyah.segments.entries()) {
  const where = `ruqyah.segments[${i}] ${segment.id}`;
  unique(segment.id, where);
  segment.ayahs.forEach((ayah, j) => {
    if (j > 0 && ayah.number !== segment.ayahs[j - 1].number + 1) fail(`${where}: ayah ${ayah.number} not contiguous`);
  });
}

// ---- Quran comparison (rule 2) ----
const normalise = text => text.normalize("NFC").replace(/\s*﴿[\u0660-\u0669]+﴾/g, "").replace(/\s+/g, " ").trim();
const dropBasmala = (key, text) => (key.endsWith(":1") && key !== "1:1" && text.startsWith("بِسْمِ") ? text.split(" ").slice(4).join(" ") : text);
// quran.com encodes a few marks differently from tanzil-derived alquran.cloud: tatweel before superscript alef,
// hamza above on tatweel instead of a bare hamza, and no small meem after tanween.
const quranComEncoding = text => text.replace(/\u0640([\u064B-\u0652]?)\u0654/g, "\u0621$1").replace(/[\u0640\u06ED]/g, "").replace(/([\u064B-\u064D])\u06E2/g, "$1");
// Letters only: drops harakat, Quranic annotation marks, superscript alef and tatweel.
const skeleton = text => text.replace(/[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]/g, "").replace(/\s+/g, " ").trim();

const comparisons = {
  "alquran-cloud:quran-uthmani": [["alquran-cloud.quran-uthmani", t => t], ["quran-com.v4.uthmani", quranComEncoding]],
  "simplified-rasm": [["alquran-cloud.quran-simple", t => t], ["quran-com.v4.imlaei", skeleton]]
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

function compareQuran(where, id, edition, surah, from, to, text, partial) {
  for (const [source, transform] of comparisons[edition]) {
    const keys = Array.from({ length: to - from + 1 }, (_, k) => `${surah}:${from + k}`);
    const missing = keys.filter(k => reference[source][k] === undefined);
    if (missing.length) { fail(`${where}: ${source} lacks ${missing.join(", ")} (run content-reference-refresh)`); continue; }
    const ours = transform(normalise(text));
    const ref = transform(normalise(keys.map(k => dropBasmala(k, reference[source][k])).join(" ")));
    if (partial ? ` ${ref} `.includes(` ${ours} `) : ours === ref) continue;
    const diff = partial ? ["excerpt not found in reference"] : wordDiff(ours, ref);
    const exception = exceptions.find(e => e.items.includes(id) && e.source === source);
    if (exception && JSON.stringify(exception.diff) === JSON.stringify(diff)) { usedExceptions.add(exception); continue; }
    fail(`${where}: differs from ${source}: ${diff.join(" ")}`);
  }
}

for (const period of ["morning", "evening"]) {
  for (const item of adhkar.periods[period]) {
    if (item.kind !== "quran") continue;
    compareQuran(`adhkar ${item.id}`, item.id, item.edition, item.surah, item.ayahFrom, item.ayahTo, item.text, item.partial === true);
  }
}
for (const segment of ruqyah.segments) {
  for (const ayah of segment.ayahs) {
    compareQuran(`ruqyah ${segment.id} ${segment.surahNumber}:${ayah.number}`, segment.id, ruqyah.edition, segment.surahNumber, ayah.number, ayah.number, ayah.text, false);
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
