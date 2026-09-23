// Validates PWA backup files against spec/backup/envelope-v1.schema.json plus per-app section rules.
//   node tools/backup-validate.mjs <file.athkarbackup> [...]
import { join } from "node:path";
import { readJSON, repoRoot, schemaErrors } from "./content-lib.mjs";

const schema = readJSON(join(repoRoot, "spec/backup/envelope-v1.schema.json"));
const sections = {
  "athkar-pwa": { required: ["adhkar", "reminders", "preferences"], forbidden: ["ruqyah"], athkarPreferences: true },
  "ruqyah-pwa": { required: ["ruqyah", "preferences"], forbidden: ["adhkar", "reminders"], athkarPreferences: false }
};

const files = process.argv.slice(2);
if (!files.length) {
  console.error("usage: node tools/backup-validate.mjs <file> [...]");
  process.exit(2);
}

let failed = false;
for (const file of files) {
  const envelope = readJSON(file);
  const errors = schemaErrors(schema, envelope, "backup");
  const rules = sections[envelope?.meta?.app];
  if (rules) {
    for (const key of rules.required) if (!(key in envelope)) errors.push(`backup: ${envelope.meta.app} must include ${key}`);
    for (const key of rules.forbidden) if (key in envelope) errors.push(`backup: ${envelope.meta.app} must not include ${key}`);
    for (const key of ["longOrder", "longOrderPromptAnswered"]) {
      if ((key in (envelope.preferences ?? {})) !== rules.athkarPreferences) errors.push(`backup.preferences.${key}: ${rules.athkarPreferences ? "missing" : "athkar-only"}`);
    }
  }
  const history = envelope?.adhkar?.history ?? [];
  if (history.some((entry, i) => i > 0 && entry.date >= history[i - 1].date)) errors.push("backup.adhkar.history: not strictly newest-first");
  if (errors.length) {
    failed = true;
    for (const error of errors) console.error(`✗ ${file}: ${error}`);
  } else {
    console.log(`✓ ${file}: valid ${envelope.meta.app} backup${envelope.reminders?.location ? " (includes location)" : ""}`);
  }
}
process.exit(failed ? 1 : 0);
