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

/**
 * Validates `value` against the JSON Schema subset used in this repository: type (single or array, incl. null),
 * const, enum, minLength, pattern, minimum, maximum, minItems, items, required, properties,
 * patternProperties, additionalProperties (false or a schema). Returns error strings; empty when valid.
 */
export function schemaErrors(schema, value, path, errors = []) {
  const fail = message => errors.push(`${path}: ${message}`);
  if ("const" in schema && value !== schema.const) { fail(`expected ${JSON.stringify(schema.const)}`); return errors; }
  if (schema.enum && !schema.enum.includes(value)) { fail(`${JSON.stringify(value)} not in ${schema.enum.join("|")}`); return errors; }
  const type = value === null ? "null" : Array.isArray(value) ? "array" : Number.isInteger(value) ? "integer" : typeof value;
  if (schema.type) {
    const allowed = [schema.type].flat();
    if (!allowed.includes(type) && !(type === "integer" && allowed.includes("number"))) { fail(`expected ${allowed.join("|")}, got ${type}`); return errors; }
  }
  if (type === "string") {
    if (schema.minLength && value.length < schema.minLength) fail("empty string");
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail(`${JSON.stringify(value)} does not match ${schema.pattern}`);
  }
  if (type === "integer" || type === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) fail(`${value} < ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) fail(`${value} > ${schema.maximum}`);
  }
  if (type === "array") {
    if (schema.minItems && value.length < schema.minItems) fail(`fewer than ${schema.minItems} items`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) fail(`more than ${schema.maxItems} items`);
    if (schema.items) value.forEach((v, i) => schemaErrors(schema.items, v, `${path}[${i}]`, errors));
  }
  if (type === "object") {
    for (const key of schema.required ?? []) if (!(key in value)) fail(`missing ${key}`);
    for (const [key, v] of Object.entries(value)) {
      const childPath = `${path}.${key}`;
      if (schema.properties?.[key]) { schemaErrors(schema.properties[key], v, childPath, errors); continue; }
      const pattern = Object.keys(schema.patternProperties ?? {}).find(p => new RegExp(p).test(key));
      if (pattern) schemaErrors(schema.patternProperties[pattern], v, childPath, errors);
      else if (schema.additionalProperties === false) fail(`unexpected property ${key}`);
      else if (typeof schema.additionalProperties === "object") schemaErrors(schema.additionalProperties, v, childPath, errors);
    }
  }
  return errors;
}
