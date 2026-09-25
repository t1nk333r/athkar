// Validates PWA backup files against spec/backup/envelope-v1.schema.json plus rules the schema subset cannot express.
//   node tools/backup-validate.mjs <file.athkarbackup> [...]
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { readJSON, repoRoot, schemaErrors } from "./content-lib.mjs";

const schema = readJSON(join(repoRoot, "spec/backup/envelope-v1.schema.json"));
const sections = {
  "athkar-pwa": { required: ["adhkar", "reminders", "preferences"], forbidden: ["ruqyah"], athkarPreferences: true },
  "ruqyah-pwa": { required: ["ruqyah", "preferences"], forbidden: ["adhkar", "reminders"], athkarPreferences: false }
};

// Date and instant fields are the ones whose schema pattern is exactly one of these two.
const datePatternSource = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$";
const instantPatternSource = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$";
const datePattern = new RegExp(datePatternSource);
const instantPattern = new RegExp(instantPatternSource);
/** Proleptic Gregorian, years 0000–9999 (setUTCFullYear, unlike Date.UTC, does not map 0–99 to 1900–1999). */
const isRealDate = value => {
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
};
const isRealInstant = value => isRealDate(value.slice(0, 10)) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(11, 19) === value.slice(11, 19);

/**
 * Every schema date field (value or date-pattern key) must name a real calendar day; every instant field a real time.
 * Walks the schema the same way schemaErrors does, so no other string (timeZone, item ids) is calendar-checked.
 */
function calendarErrors(node, value, path, errors) {
  if (typeof value === "string") {
    if (node.pattern === datePatternSource && datePattern.test(value) && !isRealDate(value)) errors.push(`${path}: ${value} is not a calendar date`);
    if (node.pattern === instantPatternSource && instantPattern.test(value) && !isRealInstant(value)) errors.push(`${path}: ${value} is not a valid instant`);
  } else if (Array.isArray(value)) {
    if (node.items) value.forEach((child, i) => calendarErrors(node.items, child, `${path}[${i}]`, errors));
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      const childPath = `${path}.${key}`;
      if (node.properties && Object.hasOwn(node.properties, key)) { calendarErrors(node.properties[key], child, childPath, errors); continue; }
      const pattern = Object.keys(node.patternProperties ?? {}).find(p => new RegExp(p).test(key));
      if (pattern) {
        if (pattern === datePatternSource && !isRealDate(key)) errors.push(`${path}: key ${key} is not a calendar date`);
        calendarErrors(node.patternProperties[pattern], child, childPath, errors);
      } else if (typeof node.additionalProperties === "object") calendarErrors(node.additionalProperties, child, childPath, errors);
    }
  }
  return errors;
}

const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);

function validate(envelope) {
  const errors = schemaErrors(schema, envelope, "backup");
  if (!isObject(envelope)) return errors;
  calendarErrors(schema, envelope, "backup", errors);
  const rules = sections[envelope.meta?.app];
  if (rules) {
    for (const key of rules.required) if (!(key in envelope)) errors.push(`backup: ${envelope.meta.app} must include ${key}`);
    for (const key of rules.forbidden) if (key in envelope) errors.push(`backup: ${envelope.meta.app} must not include ${key}`);
    const preferences = isObject(envelope.preferences) ? envelope.preferences : {};
    for (const key of ["longOrder", "longOrderPromptAnswered"]) {
      if ((key in preferences) !== rules.athkarPreferences) errors.push(`backup.preferences.${key}: ${rules.athkarPreferences ? "missing" : "athkar-only"}`);
    }
  }
  // History is strictly before today (adhkar) / not after today (ruqyah, whose history includes today once completed).
  const adhkarToday = envelope.adhkar?.today?.date;
  const history = envelope.adhkar?.history;
  if (Array.isArray(history)) {
    if (history.some((entry, i) => i > 0 && !(entry?.date < history[i - 1]?.date))) errors.push("backup.adhkar.history: not strictly newest-first");
    if (typeof adhkarToday === "string" && history.some(entry => !(entry?.date < adhkarToday))) errors.push("backup.adhkar.history: entry on or after today.date");
  }
  const ruqyahToday = envelope.ruqyah?.today?.date;
  if (isObject(envelope.ruqyah?.history) && typeof ruqyahToday === "string" && Object.keys(envelope.ruqyah.history).some(date => date > ruqyahToday)) {
    errors.push("backup.ruqyah.history: entry after today.date");
  }
  // SQLite stores text only up to U+0000, so item and segment IDs must not contain it.
  const idMaps = [
    ...["progress", "targets"].flatMap(field => ["morning", "evening"].map(period => [`adhkar.today.${field}.${period}`, envelope.adhkar?.today?.[field]?.[period]])),
    ["ruqyah.today.counts", envelope.ruqyah?.today?.counts]
  ];
  for (const [path, map] of idMaps) {
    if (isObject(map) && Object.keys(map).some(key => key.includes("\u0000"))) errors.push(`backup.${path}: item id contains U+0000`);
  }
  return errors;
}

const files = process.argv.slice(2);
if (!files.length) {
  console.error("usage: node tools/backup-validate.mjs <file> [...]");
  process.exit(2);
}

let failed = false;
for (const file of files) {
  let errors;
  let envelope;
  try {
    // One UTF-8 document: invalid byte sequences reject the file rather than decoding to U+FFFD. Files that pass
    // through Mail/Notes can gain a UTF-8 BOM; importers must tolerate exactly one.
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(readFileSync(file));
    envelope = JSON.parse(text.replace(/^\uFEFF/, ""));
    errors = validate(envelope);
  } catch (error) {
    errors = [`not readable JSON (${error.message})`];
  }
  if (errors.length) {
    failed = true;
    for (const error of errors) console.error(`✗ ${file}: ${error}`);
  } else {
    console.log(`✓ ${file}: valid ${envelope.meta.app} backup${envelope.reminders?.location ? " (includes location)" : ""}`);
  }
}
process.exit(failed ? 1 : 0);
