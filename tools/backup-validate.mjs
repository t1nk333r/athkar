// Validates backup files against spec/backup/envelope-v1.schema.json (the PWAs' format 1) or envelope-v2.schema.json
// (the native app's format 2), plus rules the schema subset cannot express.
//   node tools/backup-validate.mjs <file.athkarbackup> [...]
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { readJSON, repoRoot, schemaErrors } from "./content-lib.mjs";

const schemas = {
  1: readJSON(join(repoRoot, "spec/backup/envelope-v1.schema.json")),
  2: readJSON(join(repoRoot, "spec/backup/envelope-v2.schema.json"))
};
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
  const format = envelope?.meta?.format;
  // An object without a known format reports against format 1, whose `meta.format` const names the problem.
  const schema = schemas[format] ?? schemas[1];
  const errors = schemaErrors(schema, envelope, "backup");
  if (!isObject(envelope)) return errors;
  calendarErrors(schema, envelope, "backup", errors);
  if (format === 2) return nativeErrors(envelope, errors);
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

/** The format 2 rules envelope-v2.md states beyond the schema: each table's key unique, IDs without U+0000, and the
 * tables' own checks (spec/schema.md). Mirrors NativeBackup.validate() in AthkarCore. */
function nativeErrors(backup, errors) {
  const list = value => (Array.isArray(value) ? value.filter(isObject) : []);
  const unique = (rows, path, key) => {
    const seen = new Set();
    rows.forEach((row, i) => {
      const value = JSON.stringify(key(row));
      if (seen.has(value)) errors.push(`backup.${path}[${i}]: repeats an earlier row's key`);
      seen.add(value);
    });
  };
  const noNul = (value, path) => {
    if (typeof value === "string" && value.includes("\u0000")) errors.push(`backup.${path}: contains U+0000`);
  };
  const adhkar = backup.adhkar ?? {};
  unique(list(adhkar.days), "adhkar.days", row => [row.date, row.period]);
  list(adhkar.items).forEach((row, i) => {
    noNul(row.itemId, `adhkar.items[${i}].itemId`);
    if (row.count === null && row.target === null) errors.push(`backup.adhkar.items[${i}]: neither count nor target`);
  });
  unique(list(adhkar.items), "adhkar.items", row => [row.date, row.period, row.itemId]);
  const ruqyah = backup.ruqyah ?? {};
  unique(list(ruqyah.days), "ruqyah.days", row => [row.date]);
  list(ruqyah.segments).forEach((row, i) => noNul(row.segmentId, `ruqyah.segments[${i}].segmentId`));
  unique(list(ruqyah.segments), "ruqyah.segments", row => [row.date, row.segmentId]);
  const suwar = backup.suwar ?? {};
  for (const [path, rows] of [["ruqyah.suras", list(ruqyah.suras)], ["suwar.suras", list(suwar.suras)]]) {
    rows.forEach((row, i) => noNul(row.suraId, `${path}[${i}].suraId`));
    unique(rows, path, row => [row.date, row.suraId]);
  }
  noNul(suwar.selected, "suwar.selected");
  list(suwar.pages).forEach((row, i) => {
    noNul(row.suraId, `suwar.pages[${i}].suraId`);
    noNul(row.pageId, `suwar.pages[${i}].pageId`);
  });
  unique(list(suwar.pages), "suwar.pages", row => [row.date, row.pageId]);
  const tasbih = backup.tasbih ?? {};
  noNul(tasbih.selected, "tasbih.selected");
  (Array.isArray(tasbih.phrases) ? tasbih.phrases : []).forEach((phrase, i) => {
    noNul(phrase, `tasbih.phrases[${i}]`);
    if (typeof phrase === "string" && phrase.length > 60) errors.push(`backup.tasbih.phrases[${i}]: longer than 60`);
  });
  list(tasbih.counts).forEach((row, i) => {
    noNul(row.phrase, `tasbih.counts[${i}].phrase`);
    // SQLite's length() counts code points.
    if (typeof row.phrase === "string" && [...row.phrase].length > 62) errors.push(`backup.tasbih.counts[${i}].phrase: longer than 62`);
  });
  unique(list(tasbih.counts), "tasbih.counts", row => [row.date, row.phrase]);
  unique(list(tasbih.counts), "tasbih.counts", row => [row.date, row.firstUse]);
  list(backup.prayers?.records).forEach((row, i) => {
    const path = `backup.prayers.records[${i}]`;
    noNul(row.zone, `prayers.records[${i}].zone`);
    noNul(row.profile, `prayers.records[${i}].profile`);
    if (row.timing !== null && row.state !== "prayed") errors.push(`${path}.timing: only a prayed record has a timing`);
    const friday = typeof row.date === "string" && datePattern.test(row.date) && new Date(`${row.date}T00:00:00Z`).getUTCDay() === 5;
    if (row.noonPrayer !== null && !(row.state === "prayed" && row.prayer === "dhuhr" && friday)) {
      errors.push(`${path}.noonPrayer: only a prayed Dhuhr on a Friday has a noon prayer`);
    }
    if ((row.loggedAt === null) !== (row.state === "unrecorded")) errors.push(`${path}.loggedAt: set exactly when the prayer is recorded`);
  });
  unique(list(backup.prayers?.records), "prayers.records", row => [row.date, row.prayer]);
  const reminders = backup.reminders ?? {};
  const rules = list(reminders.rules);
  rules.forEach((row, i) => {
    const path = `backup.reminders.rules[${i}]`;
    noNul(row.id, `reminders.rules[${i}].id`);
    if ((row.kind === "adhkar_morning" || row.kind === "adhkar_evening") && row.id !== row.kind) errors.push(`${path}.id: an adhkar rule's ID is its kind`);
    if ((row.prayer === null) !== (row.offsetMinutes === null)) errors.push(`${path}.offsetMinutes: set exactly when the rule follows a prayer`);
    if ((row.prayer === null) === (row.localTime === null)) errors.push(`${path}.localTime: set exactly when the rule follows no prayer`);
  });
  unique(rules, "reminders.rules", row => [row.id]);
  const ids = new Set(rules.map(row => row.id));
  for (const ruleId of Object.keys(isObject(reminders.lastShown) ? reminders.lastShown : {})) {
    if (!ids.has(ruleId)) errors.push(`backup.reminders.lastShown.${ruleId}: no such rule`);
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
    console.log(`✓ ${file}: valid ${envelope.meta.app} backup (format ${envelope.meta.format})${envelope.reminders?.location ? " (includes location)" : ""}`);
  }
}
process.exit(failed ? 1 : 0);
