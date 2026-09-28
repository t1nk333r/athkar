// Builds data/cities.tsv, the offline city list for manual location (search by name, nearest-city label), from two
// GeoNames dumps (https://download.geonames.org/export/dump/, CC BY 4.0):
//   node tools/cities-build.mjs <dir with cities15000.txt and alternateNamesV2.txt>
// cities15000.txt: every place with at least 15,000 people. alternateNamesV2.txt: names tagged by language; only the
// `ar` ones are kept (preferred first, historic and colloquial dropped), so no Persian or Urdu spelling is taken for
// Arabic. In countries where Arabic is official, a city with no `ar` name falls back to the first Arabic-script name in
// cities15000's untagged alternate names that has no Persian or Urdu letter; elsewhere it keeps its English names only.
//
// Output, one city per line, tab-separated, sorted by population (largest first):
//   geonameid  country  latitude  longitude  population  arabic names (| separated)  english names (| separated)
// Coordinates keep four decimals (about 10 m); the app rounds a chosen city to two, like every stored location.
import { createReadStream, readFileSync, writeFileSync } from "node:fs";
import { createInterface } from "node:readline";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) throw new Error("usage: node tools/cities-build.mjs <geonames dump dir>");

const cities = new Map();
for (const line of readFileSync(join(dir, "cities15000.txt"), "utf8").split("\n")) {
  if (!line) continue;
  const f = line.split("\t");
  const [id, name, ascii, alternates] = f;
  const english = [...new Set([name, ascii].filter(Boolean))];
  const untagged = (alternates || "").split(",")
    .find(n => /^[\u0621-\u064A\u064B-\u0652\u0670\u0671 \-]+$/.test(n) && n.length > 1);
  cities.set(id, {
    id, english, arabic: [], untagged,
    lat: Number(f[4]).toFixed(4), lon: Number(f[5]).toFixed(4), country: f[8], population: Number(f[14]) || 0,
  });
}

const tidy = s => s.replace(/\s+/g, " ").trim();
const arabic = new Map(); // id -> [{ name, preferred, short }]
const names = createInterface({ input: createReadStream(join(dir, "alternateNamesV2.txt")), crlfDelay: Infinity });
for await (const line of names) {
  const f = line.split("\t");
  if (f[2] !== "ar" || !cities.has(f[1])) continue;
  const [, id, , name, preferred, short, colloquial, historic] = f;
  if (colloquial === "1" || historic === "1" || !/[؀-ۿ]/.test(name)) continue;
  if (!arabic.has(id)) arabic.set(id, []);
  arabic.get(id).push({ name: tidy(name), preferred: preferred === "1", short: short === "1" });
}
for (const [id, list] of arabic) {
  list.sort((a, b) => (b.preferred - a.preferred) || (a.short - b.short));
  cities.get(id).arabic = [...new Set(list.map(n => n.name))].slice(0, 4);
}

const arabicOfficial = new Set("SA AE KW QA BH OM YE IQ SY JO LB PS EG SD LY TN DZ MA MR TD DJ KM SO ER EH".split(" "));
for (const city of cities.values()) {
  if (!city.arabic.length && city.untagged && arabicOfficial.has(city.country)) city.arabic = [tidy(city.untagged)];
}

const rows = [...cities.values()]
  .sort((a, b) => b.population - a.population || a.id.localeCompare(b.id))
  .map(c => [c.id, c.country, c.lat, c.lon, c.population, c.arabic.join("|"), c.english.join("|")].join("\t"));
const header = "# GeoNames (https://www.geonames.org/), CC BY 4.0; built by tools/cities-build.mjs\n";
writeFileSync(new URL("../data/cities.tsv", import.meta.url), header + rows.join("\n") + "\n");
const withArabic = [...cities.values()].filter(c => c.arabic.length).length;
console.log(`wrote data/cities.tsv: ${rows.length} cities, ${withArabic} with an Arabic name`);
