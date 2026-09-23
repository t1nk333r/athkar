// Shared helpers for the content tools. Node ESM, no dependencies.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

export const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
export const contentDir = join(repoRoot, "content");

export const readJSON = path => JSON.parse(readFileSync(path, "utf8"));
export const sha256 = path => createHash("sha256").update(readFileSync(path)).digest("hex");

/** Evaluates the adhkar PWA's inline data and returns { morning, evening } exactly as the PWA builds them. */
export function loadPwaAdhkar(indexPath = join(repoRoot, "index.html")) {
  const html = readFileSync(indexPath, "utf8");
  const start = html.indexOf("const ayatAlKursi = {");
  const end = html.indexOf("const collections = {");
  if (start < 0 || end < 0) throw new Error("index.html: adhkar data block not found");
  const ctx = {};
  vm.runInNewContext(`${html.slice(start, end)}\nglobalThis.out = { morning: morningAthkar, evening: eveningAthkar };`, ctx);
  return ctx.out;
}

/** Converts a pack item back to the PWA's in-memory object shape (inverse of the extraction). */
export function packItemToPwa(item) {
  const { kind, edition, surah, ayahFrom, ayahTo, partial, ...rest } = item;
  return kind === "quran" ? { quran: true, ...rest } : rest;
}

/** Order-insensitive deep equality for plain JSON values. */
export function jsonEqual(a, b) {
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => jsonEqual(x, b[i]));
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const ka = Object.keys(a).sort();
    const kb = Object.keys(b).sort();
    return jsonEqual(ka, kb) && ka.every(k => jsonEqual(a[k], b[k]));
  }
  return a === b;
}

/** Serialises the ruqyah pack exactly as ruqyah-al-qareen/content.js is laid out. */
export function ruqyahContentJs(pack) {
  const segments = pack.segments.map(({ id, surah, range, repeat, basmala, ayahs }) => ({ id, surah, range, repeat, basmala, ayahs }));
  return `"use strict";\n\nconst RUQYAH_SEGMENTS = ${JSON.stringify(segments, null, 2)};\n`;
}
