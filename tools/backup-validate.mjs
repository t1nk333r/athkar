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

const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const instantPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
const isRealDate = value => {
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
};
const isRealInstant = value => isRealDate(value.slice(0, 10)) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(11, 19) === value.slice(11, 19);

/** Every date-shaped string (value or object key) must name a real calendar day; every instant a real time. */
function calendarErrors(value, path, errors) {
  if (typeof value === "string") {
    if (datePattern.test(value) && !isRealDate(value)) errors.push(`${path}: ${value} is not a calendar date`);
    if (instantPattern.test(value) && !isRealInstant(value)) errors.push(`${path}: ${value} is not a valid instant`);
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      if (!Array.isArray(value) && datePattern.test(key) && !isRealDate(key)) errors.push(`${path}: key ${key} is not a calendar date`);
      calendarErrors(child, `${path}.${key}`, errors);
    }
  }
  return errors;
}

function validate(envelope) {
  const errors = schemaErrors(schema, envelope, "backup");
  calendarErrors(envelope, "backup", errors);
  const rules = sections[envelope?.meta?.app];
  if (rules) {
    for (const key of rules.required) if (!(key in envelope)) errors.push(`backup: ${envelope.meta.app} must include ${key}`);
    for (const key of rules.forbidden) if (key in envelope) errors.push(`backup: ${envelope.meta.app} must not include ${key}`);
    for (const key of ["longOrder", "longOrderPromptAnswered"]) {
      if ((key in (envelope.preferences ?? {})) !== rules.athkarPreferences) errors.push(`backup.preferences.${key}: ${rules.athkarPreferences ? "missing" : "athkar-only"}`);
    }
  }
  const history = envelope?.adhkar?.history;
  if (Array.isArray(history) && history.some((entry, i) => i > 0 && !(entry?.date < history[i - 1]?.date))) {
    errors.push("backup.adhkar.history: not strictly newest-first");
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
    // Files that pass through Mail/Notes can gain a UTF-8 BOM; importers must tolerate it too.
    envelope = JSON.parse(readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
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
