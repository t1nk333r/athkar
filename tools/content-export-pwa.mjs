// Keeps the PWA in sync with the content packs (packs are the source of truth).
//   node tools/content-export-pwa.mjs --check   # fail if index.html drifted from a pack
// The PWA keeps its adhkar, ruqyah and suwar data inline in index.html; it is only checked (semantic equality), never
// rewritten. --check is the only mode and may be left out.
import { join } from "node:path";
import { contentDir, jsonEqual, loadPwaContent, packItemToPwa, readJSON } from "./content-lib.mjs";

let failed = false;

const adhkar = readJSON(join(contentDir, "adhkar.v1.json"));
const pwa = loadPwaContent();
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

// suwarContent is the suwar pack without its pack, version and edition fields.
const { pack: _pack, version: _version, edition: _edition, ...suwarFromPack } = readJSON(join(contentDir, "suwar.v1.json"));
if (jsonEqual(suwarFromPack, pwa.suwar)) console.log("✓ index.html suwarContent matches suwar pack");
else {
  failed = true;
  const pages = sura => sura.pages.map(page => page.id);
  const differing = suwarFromPack.suwar.flatMap(sura => pages(sura)).filter(id => {
    const find = suwar => suwar.suwar.flatMap(sura => sura.pages).find(page => page.id === id);
    return !jsonEqual(find(suwarFromPack), find(pwa.suwar));
  });
  console.error(`✗ index.html suwarContent differs from suwar pack${differing.length ? `: ${differing.join(", ")}` : " (basmala, sura fields or page split)"}`);
}

// ruqyahContent is the ruqyah pack without its pack, version and edition fields. The tab groups the segments into suras
// by ID prefix, so a sura's segments must be consecutive.
const { pack: _ruqyahPack, version: _ruqyahVersion, edition: _ruqyahEdition, ...ruqyahFromPack } = readJSON(join(contentDir, "ruqyah.v1.json"));
const suraOf = segment => segment.id.slice(0, segment.id.indexOf("-"));
const suraIds = ruqyahFromPack.segments.map(suraOf).filter((id, index, ids) => id !== ids[index - 1]);
if (new Set(suraIds).size !== suraIds.length) {
  failed = true;
  console.error(`✗ ruqyah pack: a sura's segments are not consecutive (${suraIds.join(", ")})`);
}
if (jsonEqual(ruqyahFromPack, pwa.ruqyah)) console.log("✓ index.html ruqyahContent matches ruqyah pack");
else {
  failed = true;
  const ids = new Set([...ruqyahFromPack.segments, ...pwa.ruqyah.segments].map(segment => segment.id));
  const find = (content, id) => content.segments.find(segment => segment.id === id);
  const differing = [...ids].filter(id => !jsonEqual(find(ruqyahFromPack, id), find(pwa.ruqyah, id)));
  console.error(`✗ index.html ruqyahContent differs from ruqyah pack${differing.length ? `: ${differing.join(", ")}` : " (segment order)"}`);
}

process.exit(failed ? 1 : 0);
