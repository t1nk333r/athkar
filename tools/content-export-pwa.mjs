// Keeps the PWAs in sync with the content packs (packs are the source of truth).
//   node tools/content-export-pwa.mjs --ruqyah ../ruqyah-al-qareen/content.js          # rewrite content.js from the pack
//   node tools/content-export-pwa.mjs --check --ruqyah ../ruqyah-al-qareen/content.js  # fail if content.js or index.html drifted
// The adhkar PWA keeps its data inline in index.html; it is only checked (semantic equality), never rewritten.
import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { contentDir, jsonEqual, loadPwaAdhkar, packItemToPwa, readJSON, ruqyahContentJs } from "./content-lib.mjs";

const args = process.argv.slice(2);
const checkOnly = args.includes("--check");
const ruqyahIndex = args.indexOf("--ruqyah");
const ruqyahPath = ruqyahIndex >= 0 ? resolve(args[ruqyahIndex + 1] ?? "") : null;
if (ruqyahIndex >= 0 && !args[ruqyahIndex + 1]) throw new Error("--ruqyah needs the path to ruqyah-al-qareen/content.js");

let failed = false;

const adhkar = readJSON(join(contentDir, "adhkar.v1.json"));
const pwa = loadPwaAdhkar();
for (const period of ["morning", "evening"]) {
  const fromPack = adhkar.periods[period].map(packItemToPwa);
  if (jsonEqual(fromPack, pwa[period])) continue;
  failed = true;
  const ids = new Set([...fromPack, ...pwa[period]].map(i => i.id));
  const differing = [...ids].filter(id => !jsonEqual(fromPack.find(i => i.id === id), pwa[period].find(i => i.id === id)));
  const order = fromPack.map(i => i.id).join() !== pwa[period].map(i => i.id).join();
  console.error(`✗ index.html ${period} differs from adhkar pack: ${differing.join(", ") || "(none)"}${order ? "; item order differs" : ""}`);
}
if (!failed) console.log("✓ index.html adhkar data matches adhkar pack");

if (ruqyahPath) {
  const expected = ruqyahContentJs(readJSON(join(contentDir, "ruqyah.v1.json")));
  if (checkOnly) {
    if (readFileSync(ruqyahPath, "utf8") === expected) console.log(`✓ ${ruqyahPath} matches ruqyah pack byte-for-byte`);
    else { failed = true; console.error(`✗ ${ruqyahPath} differs from ruqyah pack; run without --check to regenerate`); }
  } else {
    writeFileSync(ruqyahPath, expected);
    console.log(`wrote ${ruqyahPath}`);
  }
}

process.exit(failed ? 1 : 0);
